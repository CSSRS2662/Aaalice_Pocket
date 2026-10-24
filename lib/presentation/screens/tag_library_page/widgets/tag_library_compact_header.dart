import 'package:flutter/material.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../adaptive/interaction_policy.dart';
import 'tag_library_search_field.dart';

/// What the phone header's ⋮ menu offers.
enum TagLibraryMenuAction { select, manageGroups, import, export }

/// The phone header: search, a new-entry button and the ⋮ menu; while
/// selecting it shows the count with exit and select-all instead.
class TagLibraryCompactHeader extends StatelessWidget {
  const TagLibraryCompactHeader({
    super.key,
    required this.entryCount,
    required this.onAdd,
    required this.onMenu,
    required this.selecting,
    required this.selectedCount,
    required this.allSelected,
    required this.onExitSelection,
    required this.onToggleSelectAll,
    this.searchFocusNode,
    this.canExport = true,
  });

  final int entryCount;
  final VoidCallback onAdd;
  final ValueChanged<TagLibraryMenuAction> onMenu;
  final bool selecting;
  final int selectedCount;
  final bool allSelected;
  final VoidCallback onExitSelection;
  final VoidCallback onToggleSelectAll;
  final FocusNode? searchFocusNode;
  final bool canExport;

  @override
  Widget build(BuildContext context) {
    final extent = context.interactionPolicy.minimumControlExtent;
    return Padding(
      key: const ValueKey('tag-library-compact-header'),
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: extent < 48 ? 48 : extent),
        child: selecting ? _selectionRow(context) : _searchRow(context),
      ),
    );
  }

  Widget _searchRow(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      children: [
        Expanded(
          child: TagLibrarySearchField(
            hintText: l10n.tagLibrary_searchCount(entryCount),
            focusNode: searchFocusNode,
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filled(
          key: const ValueKey('tag-library-add-entry-button'),
          tooltip: l10n.tagLibrary_addEntry,
          onPressed: onAdd,
          style: IconButton.styleFrom(minimumSize: const Size.square(48)),
          icon: const Icon(Icons.add_rounded),
        ),
        PopupMenuButton<TagLibraryMenuAction>(
          key: const ValueKey('tag-library-more-menu'),
          tooltip: MaterialLocalizations.of(context).moreButtonTooltip,
          onSelected: onMenu,
          itemBuilder: (_) => [
            _item(
              TagLibraryMenuAction.select,
              Icons.checklist_rounded,
              l10n.common_multiSelect,
            ),
            _item(
              TagLibraryMenuAction.manageGroups,
              Icons.folder_copy_outlined,
              l10n.tagLibrary_manageGroups,
            ),
            const PopupMenuDivider(),
            _item(
              TagLibraryMenuAction.import,
              Icons.file_upload_outlined,
              l10n.common_import,
            ),
            _item(
              TagLibraryMenuAction.export,
              Icons.file_download_outlined,
              l10n.common_export,
              enabled: canExport,
            ),
          ],
        ),
      ],
    );
  }

  Widget _selectionRow(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Row(
      key: const ValueKey('tag-library-selection-header'),
      children: [
        IconButton(
          key: const ValueKey('tag-library-exit-selection'),
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          onPressed: onExitSelection,
          icon: const Icon(Icons.close_rounded),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            l10n.tagLibrary_selectedCount(selectedCount),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        IconButton(
          key: const ValueKey('tag-library-select-all'),
          tooltip: allSelected
              ? l10n.common_deselectAll
              : l10n.common_selectAll,
          isSelected: allSelected,
          onPressed: onToggleSelectAll,
          icon: const Icon(Icons.done_all_rounded),
        ),
      ],
    );
  }

  static PopupMenuItem<TagLibraryMenuAction> _item(
    TagLibraryMenuAction value,
    IconData icon,
    String label, {
    bool enabled = true,
  }) => PopupMenuItem(
    key: ValueKey('tag-library-menu-${value.name}'),
    value: value,
    enabled: enabled,
    child: Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Text(label)),
      ],
    ),
  );
}
