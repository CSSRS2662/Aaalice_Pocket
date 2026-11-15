import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/gallery/gallery_prompt_group.dart';
import 'image_generation_provider.dart';
import 'local_gallery_provider.dart';

final localGalleryPromptGroupHistoryProvider =
    Provider.autoDispose<Map<String, GeneratedImage>>((ref) {
      final history = ref.watch(
        imageGenerationNotifierProvider.select((state) => state.history),
      );
      return {
        for (final image in history)
          if (image.canUseAsGenerationInput) image.id: image,
      };
    });

final localGalleryPromptGroupsProvider =
    Provider.autoDispose<List<GalleryPromptGroup>>((ref) {
      final records = ref.watch(
        localGalleryNotifierProvider.select((state) => state.groupedImages),
      );
      final history = ref.watch(localGalleryPromptGroupHistoryProvider);
      return GalleryPromptGroup.fromFavorites(
        records,
        recentGenerations: history.values.map(
          (image) => (
            id: image.id,
            metadata: image.metadata,
            createdAt: image.createdAt,
          ),
        ),
      );
    });
