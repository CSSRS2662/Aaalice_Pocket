import 'dart:convert';
import 'dart:math';

import '../../../core/constants/api_constants.dart';
import '../../../core/constants/model_capabilities.dart';
import 'local_image_record.dart';
import 'nai_image_metadata.dart';

typedef GalleryPromptGeneration = ({
  String id,
  NaiImageMetadata? metadata,
  DateTime createdAt,
});

class GalleryPromptGroup {
  const GalleryPromptGroup._(
    this.promptKey,
    this.images,
    this.latestActivity,
    this.latestGenerationId,
  );

  final String promptKey;
  final List<LocalImageRecord> images;
  final DateTime latestActivity;
  final String? latestGenerationId;

  LocalImageRecord get favoriteCover => images.first;

  static List<GalleryPromptGroup> fromFavorites(
    Iterable<LocalImageRecord> records, {
    Iterable<GalleryPromptGeneration> recentGenerations = const [],
  }) {
    final byPrompt = <String, List<LocalImageRecord>>{};
    for (final record in records) {
      if (!record.isFavorite) continue;
      final key = _promptKey(record.metadata);
      if (key != null) (byPrompt[key] ??= []).add(record);
    }

    final latestByPrompt = <String, GalleryPromptGeneration>{};
    for (final generation in recentGenerations) {
      final metadata = generation.metadata;
      if (metadata == null) continue;
      final exactKey = _promptKey(metadata);
      final key = byPrompt.containsKey(exactKey)
          ? exactKey
          : _requestPromptKey(metadata);
      if (key == null || !byPrompt.containsKey(key)) continue;
      final previous = latestByPrompt[key];
      if (previous == null ||
          generation.createdAt.isAfter(previous.createdAt)) {
        latestByPrompt[key] = generation;
      }
    }

    final groups = byPrompt.entries.map((entry) {
      final images = entry.value..sort(_newestFirst);
      final latestGeneration = latestByPrompt[entry.key];
      final generatedAt = latestGeneration?.createdAt;
      final latestFavorite = images.first.modifiedAt;
      return GalleryPromptGroup._(
        entry.key,
        List.unmodifiable(images),
        generatedAt != null && generatedAt.isAfter(latestFavorite)
            ? generatedAt
            : latestFavorite,
        latestGeneration?.id,
      );
    }).toList();
    return groups..sort((a, b) {
      final byActivity = b.latestActivity.compareTo(a.latestActivity);
      return byActivity != 0
          ? byActivity
          : _newestFirst(a.favoriteCover, b.favoriteCover);
    });
  }

  // History can store the input fields while the PNG stores the request's
  // expanded quality and undesired-content presets.
  static String? _requestPromptKey(NaiImageMetadata metadata) {
    final model = metadata.model;
    if (model == null) return null;
    final baseModel = ImageModels.resolveBaseModel(model);
    final capabilities = ModelCapabilityRegistry.of(baseModel);
    final preset = metadata.ucPreset;
    return _promptKey(
      metadata.copyWith(
        prompt: QualityTags.applySuffix(
          metadata.prompt,
          QualityTags.composeSuffix(
            baseModel,
            qualityToggle: metadata.qualityToggle == true,
            transparentBackground:
                metadata.transparentBackground == true &&
                capabilities.supportsTransparentBackground,
            qualityTier: metadata.qualityTier ?? QualityTags.standardTier,
          ),
          capabilities,
        ),
        negativePrompt: preset == null
            ? metadata.negativePrompt
            : UcPresets.applyPresetWithNsfwCheck(
                metadata.negativePrompt,
                metadata.prompt,
                baseModel,
                preset,
              ),
      ),
    );
  }

  static int _newestFirst(LocalImageRecord a, LocalImageRecord b) {
    final byDate = b.modifiedAt.compareTo(a.modifiedAt);
    return byDate != 0 ? byDate : a.path.compareTo(b.path);
  }

  static String? _promptKey(NaiImageMetadata? metadata) {
    if (metadata == null) return null;
    final infos = metadata.characterInfos;
    final prompts = metadata.characterPrompts;
    final negatives = metadata.characterNegativePrompts;
    final characters = infos.isNotEmpty
        ? [
            for (final info in infos) [info.prompt, info.negativePrompt ?? ''],
          ]
        : [
            for (var i = 0; i < max(prompts.length, negatives.length); i++)
              [
                i < prompts.length ? prompts[i] : '',
                i < negatives.length ? negatives[i] : '',
              ],
          ];
    if (metadata.prompt.trim().isEmpty &&
        metadata.negativePrompt.trim().isEmpty &&
        characters.every((pair) => pair.every((text) => text.trim().isEmpty))) {
      return null;
    }
    return jsonEncode([metadata.prompt, metadata.negativePrompt, characters]);
  }
}
