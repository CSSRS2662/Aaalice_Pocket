import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/cache/local_gallery_thumbnail_provider.dart';
import '../../../core/cache/local_image_aspect_ratio_cache.dart';
import '../../../core/utils/localization_extension.dart';
import '../../../data/models/gallery/gallery_prompt_group.dart';
import '../../../data/models/gallery/local_image_record.dart';
import '../../adaptive/adaptive_presenter.dart';
import '../../providers/generation/generation_models.dart';
import '../../providers/local_gallery_prompt_groups_provider.dart';
import '../common/image_card_frame.dart';
import 'gallery_grid.dart';
import 'gallery_state_views.dart';
import 'library_masonry_grid.dart';

Future<void> showLocalGalleryPromptGroup(
  BuildContext context, {
  required String promptKey,
  required int columns,
  required void Function(BuildContext, List<LocalImageRecord>, int) onOpenImage,
}) => AdaptivePresenter.showForm<void>(
  context: context,
  title: context.l10n.localGallery_samePrompt,
  dialogWidth: 760,
  maxCenteredHeight: 680,
  builder: (_, _) => Consumer(
    builder: (context, ref, _) {
      final groups = ref.watch(localGalleryPromptGroupsProvider);
      final group = groups
          .where((group) => group.promptKey == promptKey)
          .firstOrNull;
      if (group == null) {
        return GalleryEmptyView(
          title: context.l10n.localGallery_samePromptEmpty,
        );
      }
      return GalleryGrid(
        key: const ValueKey('local-gallery-same-prompt-dialog-grid'),
        images: group.images,
        columns: columns,
        enableDrag: false,
        onTap: (_, index) => onOpenImage(context, group.images, index),
      );
    },
  ),
);

class LocalGalleryPromptGroupGrid extends StatefulWidget {
  const LocalGalleryPromptGroupGrid({
    super.key,
    required this.groups,
    required this.preferredColumns,
    required this.history,
    required this.onOpen,
  });

  final List<GalleryPromptGroup> groups;
  final int preferredColumns;
  final Map<String, GeneratedImage> history;
  final ValueChanged<GalleryPromptGroup> onOpen;

  @override
  State<LocalGalleryPromptGroupGrid> createState() =>
      _LocalGalleryPromptGroupGridState();
}

class _LocalGalleryPromptGroupGridState
    extends State<LocalGalleryPromptGroupGrid> {
  final _ratios = LocalImageAspectRatioCache.instance;

  @override
  void initState() {
    super.initState();
    _resolveCoverRatios();
  }

  @override
  void didUpdateWidget(LocalGalleryPromptGroupGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.groups != widget.groups ||
        oldWidget.history != widget.history) {
      _resolveCoverRatios();
    }
  }

  void _resolveCoverRatios() {
    final unknown = [
      for (final group in widget.groups)
        if (widget.history[group.latestGenerationId] == null &&
            _ratios.ratioOf(group.favoriteCover) == null)
          group.favoriteCover,
    ];
    if (unknown.isEmpty) return;
    _ratios.resolve(unknown).then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return LibraryMasonryGrid(
      gridKey: const PageStorageKey<String>('local-gallery-same-prompt-grid'),
      preferredColumns: widget.preferredColumns,
      itemCount: widget.groups.length,
      aspectRatioOf: (index) {
        final group = widget.groups[index];
        final generation = widget.history[group.latestGenerationId];
        if (generation != null &&
            generation.width > 0 &&
            generation.height > 0) {
          return generation.width / generation.height;
        }
        return _ratios.ratioOf(group.favoriteCover) ?? 1;
      },
      itemBuilder: (context, index, size) {
        final group = widget.groups[index];
        return _PromptGroupCard(
          key: ValueKey(group.promptKey),
          group: group,
          generation: widget.history[group.latestGenerationId],
          size: size,
          onOpen: () => widget.onOpen(group),
        );
      },
    );
  }
}

class _PromptGroupCard extends StatelessWidget {
  const _PromptGroupCard({
    super.key,
    required this.group,
    required this.generation,
    required this.size,
    required this.onOpen,
  });

  final GalleryPromptGroup group;
  final GeneratedImage? generation;
  final Size size;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final countLabel = context.l10n.localGallery_imageCount(
      group.images.length,
    );
    return ImageCardFrame(
      information: Align(
        alignment: AlignmentDirectional.bottomEnd,
        child: Container(
          margin: const EdgeInsets.all(8),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '${group.images.length}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium,
          ),
        ),
      ),
      overlays: [
        Semantics(
          label: countLabel,
          button: true,
          child: Material(
            color: Colors.transparent,
            child: InkWell(onTap: onOpen),
          ),
        ),
      ],
      child: _buildCover(context),
    );
  }

  Widget _buildCover(BuildContext context) {
    final target = LocalGalleryThumbnailTarget.fromLogicalSize(
      logicalWidth: size.width,
      logicalHeight: size.height,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
    final image = generation;
    if (image == null) return _favoriteThumbnail(target);
    final path = image.storedPath;
    return Image(
      image: ResizeImage(
        path == null ? MemoryImage(image.bytes) : FileImage(File(path)),
        width: target.width,
      ),
      fit: BoxFit.contain,
      excludeFromSemantics: true,
      errorBuilder: (_, _, _) => _favoriteThumbnail(target),
    );
  }

  Widget _favoriteThumbnail(LocalGalleryThumbnailTarget target) {
    final cover = group.favoriteCover;
    return Image(
      image: LocalGalleryThumbnailProvider(
        source: LocalGallerySourceIdentity.fromRecord(
          path: cover.path,
          size: cover.size,
          modifiedAt: cover.modifiedAt,
        ),
        target: target,
        fit: LocalGalleryThumbnailFit.contain,
      ),
      fit: BoxFit.contain,
      excludeFromSemantics: true,
      errorBuilder: (context, error, stackTrace) => const Center(
        child: Icon(Icons.broken_image_outlined, color: Colors.white70),
      ),
    );
  }
}
