import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/agent/agent_types.dart';
import '../../../core/agent/resources/agent_chat_resource_reference.dart';
import '../../../core/agent/resources/agent_chat_resource_reference_codec.dart';
import '../../../core/database/database_providers.dart';
import '../../../core/utils/locale_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../providers/image_generation_provider.dart';
import '../../providers/local_gallery_provider.dart';
import '../../screens/generation/services/generated_image_file_link.dart';
import 'defined_agent_tool.dart';
import 'generation_image_resource.dart';
import 'toolbox_json.dart';

typedef GeneratedImageFavoriteResolver = GeneratedImage? Function(String id);
typedef LocalGalleryFavoriteReader =
    Future<LocalGalleryFavoriteRecord?> Function(String path);
typedef LocalGalleryFavoriteWriter =
    Future<bool> Function(String path, bool favorite);

/// Saves a generated image into the gallery and returns its file path.
typedef GeneratedImageGallerySaver = Future<String> Function(GeneratedImage);

class LocalGalleryFavoriteRecord {
  const LocalGalleryFavoriteRecord({required this.id, required this.favorite});

  final int id;
  final bool favorite;
}

/// Mutates the favorite state owned by the indexed local gallery.
///
/// The gallery holds favorites only: favoriting saves the generated image into
/// it, exactly like the favorite button, and unfavoriting removes it again.
/// This toolbox never creates a parallel favorite state for generation history.
class GenerationImageFavoriteToolbox {
  GenerationImageFavoriteToolbox(
    Ref ref, {
    GeneratedImageFavoriteResolver? resolveImage,
    LocalGalleryFavoriteReader? readFavorite,
    LocalGalleryFavoriteWriter? writeFavorite,
    GeneratedImageGallerySaver? saveToGallery,
  }) : _ref = ref,
       _resolveImage =
           resolveImage ??
           ((id) =>
               ref.read(imageGenerationNotifierProvider).findImageById(id)),
       _readFavorite = readFavorite,
       _writeFavorite = writeFavorite,
       _saveToGallery = saveToGallery;

  GenerationImageFavoriteToolbox.forTesting({
    required GeneratedImageFavoriteResolver resolveImage,
    required LocalGalleryFavoriteReader readFavorite,
    required LocalGalleryFavoriteWriter writeFavorite,
    GeneratedImageGallerySaver? saveToGallery,
  }) : _ref = null,
       _resolveImage = resolveImage,
       _readFavorite = readFavorite,
       _writeFavorite = writeFavorite,
       _saveToGallery = saveToGallery;

  final Ref? _ref;
  final GeneratedImageFavoriteResolver _resolveImage;
  final LocalGalleryFavoriteReader? _readFavorite;
  final LocalGalleryFavoriteWriter? _writeFavorite;
  final GeneratedImageGallerySaver? _saveToGallery;

  List<AgentTool> tools() => [_setFavorite()];

  DefinedAgentTool _setFavorite() => DefinedAgentTool(
    name: 'set_generated_image_favorite',
    label: 'Set Generated Image Favorite',
    description:
        'Favorite or unfavorite a generated image. The local gallery holds '
        'favorites only: favoriting saves the image into it, unfavoriting '
        'removes it from the gallery a few seconds later. Saving to the '
        'system album is separate. Pass the stable generated-image '
        'resource_ref.',
    parameters: toolboxObject(
      properties: {
        'resource_ref': {'type': 'object'},
        'favorite': {'type': 'boolean'},
      },
      required: const ['resource_ref', 'favorite'],
    ),
    executionModeOverride: ToolExecutionMode.sequential,
    executeFn: (_, params) => setFavorite(params),
  );

  Future<AgentToolResult> setFavorite(Map<String, dynamic> params) async {
    final AgentChatResourceReference reference;
    try {
      reference = parseGenerationImageResource(params);
    } on GenerationImageResourceException catch (error) {
      return agentToolError(
        error.code,
        'set_generated_image_favorite: ${error.message}',
      );
    }
    final ref = _ref;
    if (ref != null) {
      await ref
          .read(imageGenerationNotifierProvider.notifier)
          .ensureGenerationHistoryRestored();
    }
    final image = _resolveImage(reference.resourceId);
    if (image == null) {
      return agentToolError(
        'stale_image_resource',
        'set_generated_image_favorite: generated image '
            '${reference.resourceId} is no longer available.',
      );
    }
    if (!image.canFavorite) {
      return agentToolError(
        'failed_stream_snapshot',
        'set_generated_image_favorite: generated image '
            '${reference.resourceId} is a failed stream snapshot.',
      );
    }
    final requested = params['favorite'] as bool;
    var path = image.filePath;
    if (path == null || path.isEmpty || !await File(path).exists()) {
      // Not in the gallery means not a favorite.
      if (!requested) {
        return agentToolJsonResult({
          'ok': true,
          'image_id': reference.resourceId,
          'favorite': false,
          'resource_ref': AgentChatResourceReferenceCodec.encodeJsonMap(
            reference,
          ),
        });
      }
      final save = _saveToGallery ?? _saveIndexed;
      if (_saveToGallery == null && _ref == null) {
        return agentToolError(
          'local_record_required',
          'set_generated_image_favorite: generated image '
              '${reference.resourceId} has no available persisted local file.',
        );
      }
      try {
        path = await save(image);
      } on Object catch (error) {
        return agentToolError(
          'favorite_save_failed',
          'set_generated_image_favorite: generated image '
              '${reference.resourceId} could not be saved into the local '
              'gallery ($error).',
        );
      }
    }

    final LocalGalleryFavoriteRecord? record;
    try {
      record = await (_readFavorite ?? _readIndexedFavorite)(path);
    } on Object catch (error) {
      return agentToolError(
        'favorite_read_failed',
        'set_generated_image_favorite: generated image '
            '${reference.resourceId} failed while reading its indexed '
            'local-gallery record (${error.runtimeType}).',
      );
    }
    if (record == null) {
      return agentToolError(
        'local_record_required',
        'set_generated_image_favorite: generated image '
            '${reference.resourceId} has no indexed local-gallery record.',
      );
    }
    final currentImage = _resolveImage(reference.resourceId);
    if (currentImage == null) {
      return agentToolError(
        'stale_image_resource',
        'set_generated_image_favorite: generated image '
            '${reference.resourceId} became unavailable before mutation.',
      );
    }
    if (!currentImage.canFavorite) {
      return agentToolError(
        'failed_stream_snapshot',
        'set_generated_image_favorite: generated image '
            '${reference.resourceId} became a failed stream snapshot before '
            'mutation.',
      );
    }
    if (currentImage.filePath != path || !await File(path).exists()) {
      return agentToolError(
        'stale_image_resource',
        'set_generated_image_favorite: generated image '
            '${reference.resourceId} changed before mutation.',
      );
    }

    var favorite = record.favorite;
    if (favorite != requested) {
      try {
        favorite = await (_writeFavorite ?? _writeIndexedFavorite)(
          path,
          requested,
        );
      } on Object catch (error) {
        return agentToolError(
          'favorite_update_failed',
          'set_generated_image_favorite: generated image '
              '${reference.resourceId} failed while persisting local-gallery '
              'favorite state (${error.runtimeType}).',
        );
      }
      if (favorite != requested) {
        return agentToolError(
          'favorite_update_failed',
          'set_generated_image_favorite: generated image '
              '${reference.resourceId} local-gallery favorite state did not persist.',
        );
      }
    }
    return agentToolJsonResult({
      'ok': true,
      'image_id': reference.resourceId,
      'local_gallery_image_id': record.id,
      'favorite': favorite,
      'resource_ref': AgentChatResourceReferenceCodec.encodeJsonMap(reference),
      'local_gallery_resource_ref':
          AgentChatResourceReferenceCodec.encodeJsonMap(
            AgentChatResourceReference(
              kind: AgentChatResourceKind.localGalleryImage,
              source: 'local_gallery',
              resourceId: '${record.id}',
            ),
          ),
    });
  }

  Future<String> _saveIndexed(GeneratedImage image) async {
    final ref = _ref!;
    final path = await GeneratedImageFileLink.ensureSaved(
      ref.read,
      image,
      lookupAppLocalizations(ref.read(localeNotifierProvider)),
    );
    // Waiting for the gallery service admits the new file to the index.
    await ref.read(localGalleryNotifierProvider.notifier).getService();
    return path;
  }

  Future<LocalGalleryFavoriteRecord?> _readIndexedFavorite(String path) async {
    final source = (await _ref!.read(
      databaseManagerProvider.future,
    )).galleryDataSource;
    if (source == null) return null;
    final id = await source.getImageIdByPath(path);
    if (id == null) return null;
    final record = await source.getImageById(id);
    if (record == null || record.isDeleted) return null;
    return LocalGalleryFavoriteRecord(
      id: id,
      favorite: await source.isFavorite(id),
    );
  }

  Future<bool> _writeIndexedFavorite(String path, bool favorite) async {
    final notifier = _ref!.read(localGalleryNotifierProvider.notifier);
    final current = await notifier.isFavorite(path);
    if (current != favorite) await notifier.toggleFavorite(path);
    return notifier.isFavorite(path);
  }
}
