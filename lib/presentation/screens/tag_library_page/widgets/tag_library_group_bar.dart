import 'package:flutter/material.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../../data/models/tag_library/tag_library_category.dart';
import '../../../adaptive/interaction_policy.dart';
import '../../../themes/core/layered_surface_style.dart';
import '../../../widgets/tag_library/library_group_style.dart';
import '../../../providers/tag_library_page_provider.dart';
import '../tag_library_sections.dart';

/// The phone's group filter: 全部, 收藏 and each top-level group with its
/// count, the sort button at the end, and a row of subgroups under it when
/// the chosen group has any.
class TagLibraryGroupBar extends StatelessWidget {
  const TagLibraryGroupBar({
    super.key,
    required this.categories,
    required this.counts,
    required this.totalCount,
    required this.favoritesCount,
    required this.selectedCategoryId,
    required this.onSelected,
    required this.onSort,
  });

  final List<TagLibraryCategory> categories;

  /// Entries per group, subgroups included.
  final Map<String, int> counts;
  final int totalCount;
  final int favoritesCount;
  final String? selectedCategoryId;
  final ValueChanged<String?> onSelected;
  final VoidCallback onSort;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tree = TagLibraryGroupTree(categories);
    final root = tree.rootOf(selectedCategoryId);
    final subgroups = root == null
        ? const <TagLibraryCategory>[]
        : tree.childrenOf(root.id);
    return Column(
      key: const ValueKey('tag-library-group-bar'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(end: 8),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  key: const ValueKey('tag-library-group-chips'),
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(12, 2, 8, 2),
                  child: Row(
                    children: [
                      _GroupChip(
                        key: const ValueKey('tag-library-chip-all'),
                        icon: Icons.grid_view_rounded,
                        label: l10n.tagLibrary_allEntries,
                        count: totalCount,
                        selected: selectedCategoryId == null,
                        onTap: () => onSelected(null),
                      ),
                      _GroupChip(
                        key: const ValueKey('tag-library-chip-favorites'),
                        icon: Icons.favorite_border_rounded,
                        label: l10n.tagLibrary_favorites,
                        count: favoritesCount,
                        selected:
                            selectedCategoryId == tagLibraryFavoritesFilter,
                        onTap: () => onSelected(tagLibraryFavoritesFilter),
                      ),
                      for (final category in tree.roots)
                        _GroupChip(
                          key: ValueKey('tag-library-chip-${category.id}'),
                          icon: LibraryGroupStyle.of(
                            category.id,
                            categories,
                          ).icon,
                          label: category.displayName,
                          count: counts[category.id] ?? 0,
                          selected: root?.id == category.id,
                          onTap: () => onSelected(category.id),
                        ),
                    ],
                  ),
                ),
              ),
              Tooltip(
                message: l10n.tagLibrary_sortTitle,
                child: IconButton(
                  key: const ValueKey('tag-library-sort-button'),
                  onPressed: onSort,
                  style: IconButton.styleFrom(
                    backgroundColor: controlSurfaceColor(
                      Theme.of(context).colorScheme,
                    ),
                    minimumSize: const Size.square(_chipHeight),
                    tapTargetSize: MaterialTapTargetSize.padded,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.swap_vert_rounded, size: 20),
                ),
              ),
            ],
          ),
        ),
        if (root != null && subgroups.isNotEmpty)
          SingleChildScrollView(
            key: const ValueKey('tag-library-subgroups'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
            child: Row(
              children: [
                _SubgroupChip(
                  key: const ValueKey('tag-library-subgroup-all'),
                  label: l10n.tagLibrary_allEntries,
                  count: counts[root.id] ?? 0,
                  selected: selectedCategoryId == root.id,
                  onTap: () => onSelected(root.id),
                ),
                for (final child in subgroups)
                  _SubgroupChip(
                    key: ValueKey('tag-library-subgroup-${child.id}'),
                    label: child.displayName,
                    count: counts[child.id] ?? 0,
                    selected: tree.isWithin(selectedCategoryId, child.id),
                    onTap: () => onSelected(child.id),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _GroupChip extends StatelessWidget {
  const _GroupChip({
    super.key,
    required this.icon,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final foreground = selected ? colors.onPrimaryContainer : colors.onSurface;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: _HitArea(
        onTap: onTap,
        selected: selected,
        child: Material(
          color: selected
              ? colors.primaryContainer
              : controlSurfaceColor(colors),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: _chipHeight),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 17, color: foreground),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: foreground,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '$count',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: selected
                            ? colors.onPrimaryContainer.withValues(alpha: 0.72)
                            : colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SubgroupChip extends StatelessWidget {
  const _SubgroupChip({
    super.key,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return _HitArea(
      onTap: onTap,
      selected: selected,
      child: Material(
        color: selected ? controlSurfaceColor(colors) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: _subgroupHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: selected
                          ? colors.onSurface
                          : colors.onSurfaceVariant,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$count',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Visual heights of the chips; their touch targets stay at the control
/// extent through [_HitArea].
const double _chipHeight = 38;
const double _subgroupHeight = 34;

/// Keeps a compact chip's touch target at the full control extent: taps just
/// above or below the chip still reach it.
class _HitArea extends StatelessWidget {
  const _HitArea({
    required this.onTap,
    required this.selected,
    required this.child,
  });

  final VoidCallback onTap;
  final bool selected;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: context.interactionPolicy.minimumControlExtent,
        ),
        child: Center(widthFactor: 1, child: child),
      ),
    ),
  );
}
