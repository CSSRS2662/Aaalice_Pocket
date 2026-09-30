import 'dart:math';
import 'dart:typed_data';

import '../../../core/services/system_album.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/utils/image_save_utils.dart';
import '../../../core/utils/nai_resolution_adapter.dart';
import '../../../data/models/image/image_params.dart';
import '../../../data/models/fixed_tag/fixed_tag_usage_snapshot.dart';
import '../../../data/services/image_metadata_service.dart';
import '../../services/generation_history_storage_service.dart';
import 'generation_models.dart';

class GenerationResultLifecycleDependencies {
  const GenerationResultLifecycleDependencies({
    required this.historyStorage,
    required this.systemAlbum,
  });

  final GenerationHistoryStorageService historyStorage;

  /// Where auto-save puts results; the gallery holds favorites only.
  final SystemAlbum systemAlbum;
}

class GenerationSaveSnapshot {
  const GenerationSaveSnapshot({
    this.fixedTagUsageSnapshot,
    this.useCoords = false,
  });

  final FixedTagUsageSnapshot? fixedTagUsageSnapshot;
  final bool useCoords;
}

class GenerationSaveResult {
  const GenerationSaveResult(
    this.images,
    this.albumLocations, {
    this.systemGalleryExportFailureCount = 0,
  });

  final List<GeneratedImage> images;

  /// Where each image that was saved, or already there, is in the album.
  final List<String> albumLocations;
  final int systemGalleryExportFailureCount;
}

class GeneratedImageRemovalResult {
  const GeneratedImageRemovalResult({this.removedCount = 0});

  final int removedCount;
}

class ExternalImagePreparationResult {
  const ExternalImagePreparationResult({
    required this.image,
    required this.params,
  });

  final GeneratedImage image;
  final ImageParams params;
}

/// Handles durable/result-side effects. It never reads Ref and never mutates
/// ImageGenerationState; callers apply its typed results through the reducer.
class GenerationResultLifecycleService {
  const GenerationResultLifecycleService(this.dependencies);

  static const int historyLimit = GenerationHistoryStorageService.maxEntries;

  final GenerationResultLifecycleDependencies dependencies;

  Future<List<GeneratedImage>> loadHistory() =>
      dependencies.historyStorage.load();

  /// Returns where each persisted image's PNG now lives, keyed by id.
  Future<Map<String, String>> persistHistory({
    required Iterable<GeneratedImage> changedImages,
    required List<String> order,
  }) => dependencies.historyStorage.persistImages(
    changedImages: changedImages,
    order: order,
  );

  Future<void> flushHistory() => dependencies.historyStorage.flush();

  List<GeneratedImage> mergeHistory(
    List<GeneratedImage> current,
    List<GeneratedImage> restored,
  ) {
    final seen = <String>{};
    return <GeneratedImage>[
      for (final image in current)
        if (seen.add(image.id)) image,
      for (final image in restored)
        if (seen.add(image.id)) image,
    ].take(historyLimit).toList(growable: false);
  }

  Future<ExternalImagePreparationResult> prepareExternalImage(
    Uint8List bytes, {
    required ImageParams params,
    int? width,
    int? height,
    ImageComparisonSource? comparisonSource,
    required bool embedNaiMetadata,
  }) async {
    final size =
        _resolveImageSize(bytes, width: width, height: height) ??
        (params.width, params.height);
    final effectiveParams = params.copyWith(width: size.$1, height: size.$2);
    final Uint8List normalized;
    if (embedNaiMetadata) {
      final metadata = await ImageMetadataService().getMetadataFromBytes(bytes);
      normalized = await ImageSaveUtils.rebuildImageBytesWithMetadata(
        imageBytes: bytes,
        params: effectiveParams,
        actualSeed: metadata?.seed,
      );
    } else {
      normalized = bytes;
    }
    return ExternalImagePreparationResult(
      image: GeneratedImage.create(
        normalized,
        width: size.$1,
        height: size.$2,
        comparisonSource: comparisonSource,
        preserveOriginalBytesOnSave: !embedNaiMetadata,
      ),
      params: effectiveParams,
    );
  }

  /// Auto-save: puts [images] in the system album, the same place the save
  /// button does. An image the album already has is not written again.
  Future<GenerationSaveResult> saveImages(
    List<GeneratedImage> images,
    ImageParams params, {
    required GenerationSaveSnapshot snapshot,
  }) async {
    final charCaptions = <Map<String, dynamic>>[];
    final charNegCaptions = <Map<String, dynamic>>[];
    for (final character in params.characters) {
      charCaptions.add({
        'char_caption': character.prompt,
        'centers': [
          {'x': 0.5, 'y': 0.5},
        ],
      });
      charNegCaptions.add({
        'char_caption': character.negativePrompt,
        'centers': [
          {'x': 0.5, 'y': 0.5},
        ],
      });
    }

    final locations = <String>[];
    var failures = 0;
    for (final image in images) {
      try {
        final hasMetadata = ImageSaveUtils.hasEmbeddedNovelAiMetadata(
          image.bytes,
        );
        var actualSeed = params.seed;
        if (actualSeed < 0 || hasMetadata) {
          final metadata = await ImageMetadataService().getMetadataFromBytes(
            image.bytes,
          );
          actualSeed = metadata?.seed ?? actualSeed;
          if (actualSeed < 0) {
            actualSeed = Random().nextInt(4294967295);
          }
        }
        final bytes = await ImageSaveUtils.resultBytesForSave(
          imageBytes: image.bytes,
          preserveOriginalBytes: image.preserveOriginalBytesOnSave,
          fixedTagUsageSnapshot:
              image.fixedTagUsageSnapshot ?? snapshot.fixedTagUsageSnapshot,
          rebuild: () => ImageSaveUtils.rebuildImageBytesWithMetadata(
            imageBytes: image.bytes,
            params: params.copyWith(width: image.width, height: image.height),
            actualSeed: actualSeed,
            charCaptions: charCaptions,
            charNegCaptions: charNegCaptions,
            useCoords: snapshot.useCoords,
            useStealth: false,
          ),
        );
        final saved = await dependencies.systemAlbum.save(
          bytes: bytes,
          identity: image.bytes,
          fileName: ImageSaveUtils.albumFileName(seed: actualSeed),
          source: 'auto-save',
        );
        locations.add(saved.location);
      } catch (error, stackTrace) {
        AppLogger.e('自动保存图像失败', error, stackTrace);
        failures++;
      }
    }

    // 统计缓存记的是图库图片数；自动保存只进系统相册，不改变它。
    return GenerationSaveResult(
      images,
      locations,
      systemGalleryExportFailureCount: failures,
    );
  }

  (int, int)? _resolveImageSize(Uint8List bytes, {int? width, int? height}) {
    final encoded = NaiResolutionAdapter.readImageSize(bytes);
    if (encoded != null) return encoded;
    if (width != null && height != null) return (width, height);
    return null;
  }
}
