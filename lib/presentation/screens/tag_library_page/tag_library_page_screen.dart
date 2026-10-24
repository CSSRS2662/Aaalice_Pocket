import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../../core/agent/resources/agent_chat_resource_reference.dart';
import '../../../core/constants/storage_keys.dart';
import '../../../core/platform/platform_capabilities.dart';
import '../../../core/shortcuts/default_shortcuts.dart';
import '../../../core/utils/file_explorer_utils.dart';
import '../../../core/utils/localization_extension.dart';
import '../../../data/models/gallery/gallery_tree_drop_slot.dart';
import '../../../data/models/tag_library/tag_library_category.dart';
import '../../../data/models/tag_library/tag_library_entry.dart';
import '../../agent_chat/widgets/agent_resource_drop_region.dart';
import '../../providers/fixed_tags_provider.dart';
import '../../providers/library_sidebar_sort_provider.dart';
import '../../providers/tag_library_page_provider.dart';
import '../../providers/tag_library_selection_provider.dart';
import '../../selection/card_selection_scope.dart';
import '../../services/library_sidebar_move_service.dart';
import '../../utils/library_sidebar_sort.dart';
import '../../widgets/common/app_toast.dart';
import '../../widgets/common/context_menu_anchor.dart';
import '../../widgets/common/library_classification_drag.dart';
import '../../widgets/common/owned_scroll_controller.dart';
import '../../widgets/gallery/gallery_album_tree_view.dart';
import '../../widgets/gallery/gallery_sidebar.dart';
import '../../widgets/gallery/gallery_sidebar_sort_control.dart';
import '../../widgets/gallery/library_sidebar_root_drop_target.dart';
import '../../widgets/shortcuts/shortcut_aware_widget.dart';
import '../../widgets/tag_library/library_group_style.dart';
import 'tag_library_actions.dart';
import 'tag_library_sections.dart';
import 'widgets/category_tree_view.dart';
import 'widgets/entry_card.dart';
import 'widgets/tag_library_compact_header.dart';
import 'widgets/tag_library_group_bar.dart';
import 'widgets/tag_library_group_create_sheet.dart';
import 'widgets/tag_library_sections_view.dart';
import 'widgets/tag_library_selection_bar.dart';
import 'widgets/tag_library_toolbar.dart';

/// 词库页面
///
/// 手机上是搜索栏、分组筛选与分节的两列词条；宽屏保留工具栏与分组侧栏。
/// 点词条看详情，长按多选；发送后留在词库，通知里可以去生成。
class TagLibraryPageScreen extends ConsumerStatefulWidget {
  const TagLibraryPageScreen({super.key, this.showPageTitle = true});

  /// Off where the 词库 page names it above, see DictionaryScreen.
  final bool showPageTitle;

  @override
  ConsumerState<TagLibraryPageScreen> createState() =>
      _TagLibraryPageScreenState();
}

class _TagLibraryPageScreenState extends ConsumerState<TagLibraryPageScreen> {
  final FocusNode _searchFocusNode = FocusNode();
  final OwnedScrollController _scrollController = OwnedScrollController(
    viewport: OwnedViewportOffset(),
  );
  final ValueNotifier<Set<String>> _expandedCategoryIds =
      ValueNotifier<Set<String>>(<String>{});
  final ValueNotifier<bool> _categoriesExpanded = ValueNotifier(true);
  bool _showCategoryPanel = true;

  TagLibraryActions get _actions => TagLibraryActions(ref, context);

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _expandedCategoryIds.dispose();
    _categoriesExpanded.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  List<TagLibraryEntry> _selectedEntries() => _actions.entriesOf(
    ref.read(tagLibrarySelectionNotifierProvider).selectedIds,
  );

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(tagLibraryPageNotifierProvider);
    final selection = ref.watch(tagLibrarySelectionNotifierProvider);
    final selectionNotifier = ref.read(
      tagLibrarySelectionNotifierProvider.notifier,
    );
    final orderedIds = state.filteredEntries.map((entry) => entry.id).toList();

    void whenSelecting(VoidCallback action) {
      final current = ref.read(tagLibrarySelectionNotifierProvider);
      if (current.isActive && current.hasSelection) action();
    }

    final shortcuts = <String, VoidCallback>{
      ShortcutIds.selectAllTags: () {
        if (ref.read(tagLibrarySelectionNotifierProvider).isActive) {
          selectionNotifier.selectAll(orderedIds);
        }
      },
      ShortcutIds.exitSelectionMode: selectionNotifier.exit,
      ShortcutIds.deselectAllTags: selectionNotifier.clearSelection,
      ShortcutIds.newCategory: () =>
          showTagLibraryGroupCreateSheet(context: context),
      ShortcutIds.newTag: () => _actions.addEntry(_selectedGroupId(state)),
      ShortcutIds.searchTags: _searchFocusNode.requestFocus,
      ShortcutIds.batchDeleteTags: () =>
          whenSelecting(() => _actions.confirmDelete(_selectedEntries())),
      ShortcutIds.batchCopyTags: () =>
          whenSelecting(() => _actions.copy(_selectedEntries())),
      ShortcutIds.sendToHome: () =>
          whenSelecting(() => _actions.sendToPrompt(_selectedEntries())),
    };

    return CardSelectionScope(
      selection: selection,
      commands: selectionNotifier,
      orderedIds: orderedIds,
      child: CardSelectionShortcuts(
        child: PopScope<void>(
          canPop: !selection.isActive,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && selection.isActive) selectionNotifier.exit();
          },
          child: PageShortcuts(
            contextType: ShortcutContext.tagLibrary,
            shortcuts: shortcuts,
            child: Scaffold(
              body: LayoutBuilder(
                builder: (context, constraints) => constraints.maxWidth >= 840
                    ? _buildWorkspace(state)
                    : _buildCompact(state, selection),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ==================== 布局 ====================

  Widget _buildWorkspace(TagLibraryPageState state) {
    return GalleryCollectionWorkspace(
      sidebarWidthKey: StorageKeys.tagLibrarySidebarWidth,
      toolbar: TagLibraryToolbar(
        showPageTitle: widget.showPageTitle,
        showCategoryPanel: _showCategoryPanel,
        searchFocusNode: _searchFocusNode,
        onShowCategories: () =>
            setState(() => _showCategoryPanel = !_showCategoryPanel),
        onOpenFolder: PlatformCapabilities.current.supportsOpenFolder
            ? _openLibraryFolder
            : null,
        onEnterSelectionMode: () =>
            ref.read(tagLibrarySelectionNotifierProvider.notifier).enter(),
        onBulkSend: () => _actions.sendToPrompt(_selectedEntries()),
        onBulkDelete: () => _actions.confirmDelete(_selectedEntries()),
        onBulkMoveCategory: () => _actions.moveToGroup(
          _selectedEntries().map((entry) => entry.id).toList(),
        ),
        onBulkToggleFavorite: () =>
            _actions.toggleFavorites(_selectedEntries()),
        onBulkCopy: () => _actions.copy(_selectedEntries()),
        onImport: _actions.import,
        onExport: _actions.export,
        onAddEntry: () => _actions.addEntry(_selectedGroupId(state)),
        onSort: _actions.showSort,
        onManageGroups: _actions.showGroupManager,
      ),
      sidebar: _showCategoryPanel ? _buildCategorySidebar() : null,
      body: _buildContent(state, bottomPadding: 24),
    );
  }

  Widget _buildCompact(
    TagLibraryPageState state,
    SelectionModeState selection,
  ) {
    final orderedIds = state.filteredEntries.map((entry) => entry.id).toList();
    final allSelected =
        orderedIds.isNotEmpty &&
        orderedIds.every(selection.selectedIds.contains);
    final selected = selection.isActive
        ? _selectedEntries()
        : const <TagLibraryEntry>[];
    final notifier = ref.read(tagLibrarySelectionNotifierProvider.notifier);
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TagLibraryCompactHeader(
              entryCount: state.entries.length,
              searchFocusNode: _searchFocusNode,
              canExport: state.entries.isNotEmpty,
              onAdd: () => _actions.addEntry(_selectedGroupId(state)),
              onMenu: (action) => switch (action) {
                TagLibraryMenuAction.select => notifier.enter(),
                TagLibraryMenuAction.manageGroups =>
                  _actions.showGroupManager(),
                TagLibraryMenuAction.import => _actions.import(),
                TagLibraryMenuAction.export => _actions.export(),
              },
              selecting: selection.isActive,
              selectedCount: selection.selectedIds.length,
              allSelected: allSelected,
              onExitSelection: notifier.exit,
              onToggleSelectAll: () => allSelected
                  ? notifier.clearSelection()
                  : notifier.selectAll(orderedIds),
            ),
            TagLibraryGroupBar(
              categories: state.categories,
              counts: state.categoryEntryCounts,
              totalCount: state.entries.length,
              favoritesCount: state.favoritesCount,
              selectedCategoryId: state.selectedCategoryId,
              onSelected: ref
                  .read(tagLibraryPageNotifierProvider.notifier)
                  .selectCategory,
              onSort: _actions.showSort,
            ),
            const SizedBox(height: 4),
            Expanded(
              child: _buildContent(
                state,
                bottomPadding: selection.isActive ? 96 : 24,
              ),
            ),
          ],
        ),
        if (selection.isActive)
          PositionedDirectional(
            start: 12,
            end: 12,
            bottom: 12,
            child: SafeArea(
              top: false,
              child: TagLibrarySelectionBar(
                count: selected.length,
                allFavorite:
                    selected.isNotEmpty && selected.every((e) => e.isFavorite),
                onSend: () => _actions.sendToPrompt(selected),
                onToggleFavorite: () => _actions.toggleFavorites(selected),
                onMove: () => _actions.moveToGroup(
                  selected.map((entry) => entry.id).toList(),
                ),
                onCopy: () => _actions.copy(selected),
                onAddAsFixed: () => _actions.addAsFixed(selected),
                onDelete: () => _actions.confirmDelete(selected),
              ),
            ),
          ),
      ],
    );
  }

  String? _selectedGroupId(TagLibraryPageState state) {
    final selected = state.selectedCategoryId;
    return state.categories.any((category) => category.id == selected)
        ? selected
        : null;
  }

  // ==================== 内容 ====================

  Widget _buildContent(
    TagLibraryPageState state, {
    required double bottomPadding,
  }) {
    if (state.isLoading) {
      return Center(
        child: CircularProgressIndicator(
          value: MediaQuery.disableAnimationsOf(context) ? 0.72 : null,
        ),
      );
    }
    final selection = ref.watch(tagLibrarySelectionNotifierProvider);
    final fixedIds = ref.watch(_fixedEntryIdsProvider);
    final orderedIds = state.filteredEntries.map((e) => e.id).toList();
    final searching = state.searchQuery.trim().isNotEmpty;
    final sections = buildTagLibrarySections(
      entries: state.filteredEntries,
      categories: state.categories,
      selectedCategoryId: state.selectedCategoryId,
      favoritesFirst: state.favoritesFirst,
      searching: searching,
    );
    final Widget content = sections.isEmpty
        ? _EmptyState(
            searching: searching,
            filtered: state.selectedCategoryId != null,
            onAdd: () => _actions.addEntry(_selectedGroupId(state)),
          )
        : TagLibrarySectionsView(
            sections: sections,
            categories: state.categories,
            scrollController: _scrollController,
            bottomPadding: bottomPadding,
            entryBuilder: (entry) =>
                _buildEntryItem(entry, state, selection, fixedIds, orderedIds),
          );
    // Only a mouse sends secondary taps, so touch never sees this menu.
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onSecondaryTapUp: (details) =>
          _showEntryCreationContextMenu(details.globalPosition, state),
      child: content,
    );
  }

  Widget _buildEntryItem(
    TagLibraryEntry entry,
    TagLibraryPageState state,
    SelectionModeState selection,
    Set<String> fixedIds,
    List<String> orderedIds,
  ) {
    final notifier = ref.read(tagLibrarySelectionNotifierProvider.notifier);

    void toggleSelection() {
      if (HardwareKeyboard.instance.isShiftPressed) {
        notifier.selectRange(entry.id, orderedIds);
      } else if (!selection.isActive) {
        notifier.enterAndSelect(entry.id);
      } else {
        notifier.toggle(entry.id);
      }
    }

    return AgentResourceDragSource(
      key: ValueKey(entry.id),
      reference: AgentChatResourceReference(
        kind: AgentChatResourceKind.tagLibraryEntry,
        source: 'tag_library',
        resourceId: entry.id,
        display: {'name': entry.displayName},
      ),
      child: EntryCard(
        entry: entry,
        groupStyle: LibraryGroupStyle.of(entry.categoryId, state.categories),
        isFixedTag: fixedIds.contains(entry.id),
        isSelectionMode: selection.isActive,
        isSelected: selection.isSelected(entry.id),
        onToggleSelection: toggleSelection,
        onTap: () => _actions.openEntry(entry),
        onContextMenu: (position) => _actions.showEntryMenu(entry, position),
      ),
    );
  }

  Future<void> _showEntryCreationContextMenu(
    Offset position,
    TagLibraryPageState state,
  ) async {
    final create = await showMenu<bool>(
      context: context,
      position: contextMenuAnchorAt(context, position),
      items: [
        PopupMenuItem(
          key: const Key('tag-library-context-create-entry'),
          value: true,
          child: Row(
            children: [
              const Icon(Icons.add_box_outlined, size: 18),
              const SizedBox(width: 8),
              Text(context.l10n.tagLibrary_addEntry),
            ],
          ),
        ),
      ],
    );
    if (create == true && mounted) _actions.addEntry(_selectedGroupId(state));
  }

  // ==================== 宽屏分组侧栏 ====================

  Widget _buildCategorySidebar() => ValueListenableBuilder<bool>(
    valueListenable: _categoriesExpanded,
    builder: (context, expanded, _) => Consumer(
      builder: (context, sidebarRef, _) => _buildCategorySidebarContents(
        sidebarRef.watch(tagLibraryPageNotifierProvider),
        sidebarRef
            .watch(
              librarySidebarSortProvider(LibrarySidebarSection.tagCategories),
            )
            .sort,
        expanded: expanded,
      ),
    ),
  );

  Widget _buildCategorySidebarContents(
    TagLibraryPageState state,
    LibrarySidebarSort sort, {
    required bool expanded,
  }) {
    void selectCategory(String? id) =>
        ref.read(tagLibraryPageNotifierProvider.notifier).selectCategory(id);

    final allEntries = GestureDetector(
      onSecondaryTapUp: (details) =>
          _showEntryCreationContextMenu(details.globalPosition, state),
      child: LibraryClassificationDropTarget<TagLibraryEntry>(
        kind: AgentChatResourceKind.tagLibraryEntry,
        resolve: (id) => ref
            .read(tagLibraryPageNotifierProvider)
            .entries
            .where((entry) => entry.id == id)
            .firstOrNull,
        needsChange: (entry) => entry.categoryId != null,
        onAccept: (entry) => ref
            .read(tagLibraryPageNotifierProvider.notifier)
            .moveEntryToCategory(entry.id, null),
        child: GalleryAllImagesItem(
          key: const Key('tag-library-all-entries'),
          icon: Icons.grid_view_outlined,
          selectedIcon: Icons.grid_view_rounded,
          label: context.l10n.tagLibrary_allEntries,
          count: state.entries.length,
          isSelected: state.selectedCategoryId == null,
          onTap: () => selectCategory(null),
        ),
      ),
    );

    return GallerySidebarSurface(
      key: const Key('tag-library-category-sidebar'),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const SizedBox(height: GalleryCollectionChrome.navigationTopPadding),
          allEntries,
          LibrarySidebarRootDropTarget<TagLibraryCategory>(
            canDrop: (category) => category.parentId != null,
            onDrop: (category) async {
              await ref
                  .read(librarySidebarMoveServiceProvider)
                  .moveTagCategory(
                    category.id,
                    null,
                    GalleryTreeDropSlot.child,
                  );
            },
            child: GallerySidebarSectionHeader(
              toggleKey: const Key('tag-library-category-section-toggle'),
              icon: Icons.folder_copy_outlined,
              title: context.l10n.tagLibrary_categories,
              trailing: const GallerySidebarSortControl(
                section: LibrarySidebarSection.tagCategories,
              ),
              isExpanded: expanded,
              onToggle: () => _categoriesExpanded.value = !expanded,
              onCreate: () => showTagLibraryGroupCreateSheet(context: context),
            ),
          ),
          if (expanded) _buildCategoryTree(state, sort, selectCategory),
        ],
      ),
    );
  }

  Widget _buildCategoryTree(
    TagLibraryPageState state,
    LibrarySidebarSort sort,
    ValueChanged<String?> selectCategory,
  ) => ValueListenableBuilder<Set<String>>(
    valueListenable: _expandedCategoryIds,
    builder: (context, expandedCategoryIds, _) => CategoryTreeView(
      categories: state.categories,
      sort: sort,
      entries: state.entries,
      selectedCategoryId: state.selectedCategoryId,
      expandedCategoryIds: expandedCategoryIds,
      includeAllEntries: false,
      embedded: true,
      onExpandedCategoryIdsChanged: (ids) => _expandedCategoryIds.value = ids,
      onCategorySelected: selectCategory,
      onCategoryRename: (id, name) => ref
          .read(tagLibraryPageNotifierProvider.notifier)
          .renameCategory(id, name),
      onCategoryDelete: _actions.confirmDeleteGroup,
      onAddSubCategory: (parentId) =>
          showTagLibraryGroupCreateSheet(context: context, parentId: parentId),
      onAddEntry: _actions.addEntry,
      onCategoryMove: (categoryId, newParentId) => ref
          .read(tagLibraryPageNotifierProvider.notifier)
          .moveCategory(categoryId, newParentId),
      onCategoryMoveToSlot: (id, targetId, slot) => ref
          .read(librarySidebarMoveServiceProvider)
          .moveTagCategory(id, targetId, slot),
      onEntryDrop: (entryId, categoryId) async {
        await ref
            .read(tagLibraryPageNotifierProvider.notifier)
            .moveEntryToCategory(entryId, categoryId);
        if (!context.mounted) return;
        AppToast.success(context, context.l10n.tagLibrary_entryMoved);
      },
      onEntryFavoriteDrop: (entryId) => ref
          .read(tagLibraryPageNotifierProvider.notifier)
          .setFavorite([entryId], true),
    ),
  );

  Future<void> _openLibraryFolder() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final directory = Directory(
        path.join(appDir.path, 'tag_library_thumbnails'),
      );
      await directory.create(recursive: true);
      await FileExplorerUtils.openDirectory(directory.path);
    } catch (error) {
      if (mounted) {
        AppToast.error(
          context,
          context.l10n.localGallery_openFolderFailed('$error'),
        );
      }
    }
  }
}

/// Ids of library entries that are fixed tags, for the pin on their cards.
final _fixedEntryIdsProvider = Provider.autoDispose<Set<String>>(
  (ref) => {
    for (final tag in ref.watch(fixedTagsNotifierProvider).entries)
      if (tag.sourceEntryId != null) tag.sourceEntryId!,
  },
);

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.searching,
    required this.filtered,
    required this.onAdd,
  });

  final bool searching;
  final bool filtered;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              searching ? Icons.search_off_rounded : Icons.bookmarks_outlined,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              searching
                  ? l10n.tagLibrary_noSearchResults
                  : filtered
                  ? l10n.tagLibrary_categoryEmpty
                  : l10n.tagLibrary_empty,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              searching
                  ? l10n.tagLibrary_tryDifferentSearch
                  : l10n.tagLibrary_addFirstEntry,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (!searching) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const ValueKey('tag-library-empty-add'),
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded),
                label: Text(l10n.tagLibrary_addEntry),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
