import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../providers/tag_library_page_provider.dart';
import '../../../providers/tag_library_selection_provider.dart';
import '../../../widgets/bulk_action_bar.dart';
import '../../../widgets/gallery/gallery_library_toolbar.dart';
import '../../../widgets/gallery/gallery_sidebar.dart';
import 'tag_library_search_field.dart';

/// 宽屏词库工具栏：搜索、分组栏开关、排序、分组管理与批量操作。
class TagLibraryToolbar extends ConsumerWidget {
  const TagLibraryToolbar({
    super.key,
    this.onShowCategories,
    this.showCategoryPanel = true,
    this.onOpenFolder,
    this.onEnterSelectionMode,
    this.onBulkSend,
    this.onBulkDelete,
    this.onBulkMoveCategory,
    this.onBulkToggleFavorite,
    this.onBulkCopy,
    this.onImport,
    this.onExport,
    this.onAddEntry,
    this.onSort,
    this.onManageGroups,
    this.searchFocusNode,
    this.showPageTitle = true,
  });

  final VoidCallback? onShowCategories;
  final bool showCategoryPanel;
  final VoidCallback? onOpenFolder;
  final VoidCallback? onEnterSelectionMode;
  final VoidCallback? onBulkSend;
  final VoidCallback? onBulkDelete;
  final VoidCallback? onBulkMoveCategory;
  final VoidCallback? onBulkToggleFavorite;
  final VoidCallback? onBulkCopy;
  final VoidCallback? onImport;
  final VoidCallback? onExport;
  final VoidCallback? onAddEntry;
  final VoidCallback? onSort;
  final VoidCallback? onManageGroups;
  final FocusNode? searchFocusNode;
  final bool showPageTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(tagLibraryPageNotifierProvider);
    final selection = ref.watch(tagLibrarySelectionNotifierProvider);
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final allEntryIds = state.filteredEntries.map((entry) => entry.id).toList();
    final isAllSelected =
        allEntryIds.isNotEmpty &&
        allEntryIds.every(selection.selectedIds.contains);

    if (selection.isActive) {
      return BulkActionBar(
        selectedCount: selection.selectedIds.length,
        isAllSelected: isAllSelected,
        onExit: () =>
            ref.read(tagLibrarySelectionNotifierProvider.notifier).exit(),
        onSelectAll: () {
          final notifier = ref.read(
            tagLibrarySelectionNotifierProvider.notifier,
          );
          isAllSelected
              ? notifier.clearSelection()
              : notifier.selectAll(allEntryIds);
        },
        actions: [
          BulkActionItem(
            icon: Icons.send_rounded,
            label: l10n.tagLibrary_sendToPrompt,
            onPressed: onBulkSend,
            color: theme.colorScheme.primary,
          ),
          BulkActionItem(
            icon: Icons.drive_file_move_outline,
            label: l10n.tagLibrary_transferCategory,
            onPressed: onBulkMoveCategory,
            color: theme.colorScheme.secondary,
          ),
          BulkActionItem(
            icon: Icons.copy,
            label: l10n.tagLibrary_copyContent,
            onPressed: onBulkCopy,
            color: theme.colorScheme.tertiary,
          ),
          BulkActionItem(
            icon: Icons.favorite_outline,
            label: l10n.common_favorite,
            onPressed: onBulkToggleFavorite,
            color: Colors.pink,
          ),
          BulkActionItem(
            icon: Icons.delete_outline,
            label: l10n.common_delete,
            onPressed: onBulkDelete,
            color: theme.colorScheme.error,
            isDanger: true,
            showDividerBefore: true,
          ),
        ],
      );
    }

    final filtered = state.filteredEntries.length != state.entries.length;
    return GalleryLibraryToolbar(
      key: const Key('tag-library-toolbar'),
      title: showPageTitle
          ? GalleryCollectionPageTitle(
              icon: Icons.bookmarks_outlined,
              title: l10n.nav_dictionary,
            )
          : const SizedBox.shrink(),
      count: GalleryLibraryCountBadge(
        label: filtered
            ? '${state.filteredEntries.length}/${state.entries.length}'
            : '${state.entries.length}',
      ),
      search: TagLibrarySearchField(
        hintText: l10n.tagLibrary_searchHint,
        focusNode: searchFocusNode,
      ),
      actions: [
        if (onShowCategories != null)
          GalleryLibraryAction(
            key: const Key('tag-library-categories-button'),
            icon: showCategoryPanel
                ? Icons.view_sidebar
                : Icons.view_sidebar_outlined,
            label: l10n.tagLibrary_categories,
            tooltip: showCategoryPanel
                ? l10n.localGallery_hideCategoryPanel
                : l10n.localGallery_showCategoryPanel,
            onPressed: onShowCategories,
          ),
        GalleryLibraryAction(
          key: const Key('tag-library-sort-button'),
          icon: Icons.swap_vert_rounded,
          label: _sortLabel(context, state.sortBy),
          tooltip: l10n.tagLibrary_sortTitle,
          onPressed: onSort,
        ),
        GalleryLibraryAction(
          key: const Key('tag-library-manage-groups-button'),
          icon: Icons.folder_copy_outlined,
          label: l10n.tagLibrary_manageGroups,
          onPressed: onManageGroups,
        ),
        GalleryLibraryAction(
          icon: Icons.checklist,
          label: l10n.common_multiSelect,
          onPressed: onEnterSelectionMode,
        ),
        GalleryLibraryAction(
          icon: Icons.file_upload_outlined,
          label: l10n.common_import,
          onPressed: onImport,
        ),
        GalleryLibraryAction(
          icon: Icons.file_download_outlined,
          label: l10n.common_export,
          onPressed: state.entries.isEmpty ? null : onExport,
        ),
        if (onOpenFolder != null)
          GalleryLibraryAction(
            key: const Key('tag-library-folder-button'),
            icon: Icons.folder_open_outlined,
            label: l10n.common_folder,
            tooltip: l10n.shortcut_action_open_folder,
            onPressed: onOpenFolder,
          ),
      ],
      primaryAction: GalleryLibraryPrimaryAction(
        key: const Key('tag-library-add-entry-button'),
        icon: Icons.add,
        label: l10n.tagLibrary_addEntry,
        onPressed: onAddEntry,
      ),
    );
  }

  static String _sortLabel(BuildContext context, TagLibrarySortBy sortBy) =>
      switch (sortBy) {
        TagLibrarySortBy.order => context.l10n.tagLibrary_sortCustom,
        TagLibrarySortBy.name => context.l10n.tagLibrary_sortName,
        TagLibrarySortBy.frequent => context.l10n.tagLibrary_sortFrequent,
        TagLibrarySortBy.recentlyUsed => context.l10n.tagLibrary_sortRecent,
      };
}
