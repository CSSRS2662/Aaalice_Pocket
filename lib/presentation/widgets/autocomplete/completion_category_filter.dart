import 'package:flutter/material.dart';

import '../../../core/autocomplete/completion_models.dart';
import '../../../core/utils/localization_extension.dart';
import '../../adaptive/interaction_policy.dart';
import 'completion_category_style.dart';
import 'completion_tile_layout.dart';

/// The categories the open popup is narrowed to, and how its header
/// buttons change them. Typed tags and related tags each keep their own.
class CompletionCategoryFilter {
  const CompletionCategoryFilter({
    required this.categories,
    required this.chosen,
    required this.onToggleCategory,
    required this.onClear,
    this.counts,
    this.listsOnlineRows = false,
  });

  /// Buttons for typed tags, in header order.
  static const List<TagCategory> typedCategories = [
    TagCategory.general,
    TagCategory.character,
    TagCategory.copyright,
    TagCategory.artist,
    TagCategory.meta,
  ];

  /// Related suggestions narrow to these, in the same order.
  static const List<TagCategory> relatedCategories = [
    TagCategory.general,
    TagCategory.character,
    TagCategory.copyright,
  ];

  final List<TagCategory> categories;
  final Set<TagCategory> chosen;

  /// Local matches per category; null until counted.
  final Map<TagCategory, int>? counts;

  /// Whether online rows may add to a category the local data has none of.
  final bool listsOnlineRows;
  final ValueChanged<TagCategory> onToggleCategory;
  final VoidCallback onClear;

  bool get active => chosen.isNotEmpty;

  /// A category with nothing to list cannot be chosen.
  bool canChoose(TagCategory category) =>
      chosen.contains(category) ||
      listsOnlineRows ||
      counts == null ||
      (counts![category] ?? 0) > 0;
}

/// The category buttons at the start of the popup header: each shows the
/// category icon with its count raised at the corner. A tap adds or removes
/// the category; any chosen category lists only those. Like the other popup
/// controls they never take focus from the field.
class CompletionCategoryBar extends StatelessWidget {
  const CompletionCategoryBar({super.key, required this.filter});

  final CompletionCategoryFilter filter;

  /// Width of the buttons for [count] categories.
  static double widthFor(BuildContext context, int count) =>
      count * _CategoryButton.extentOf(context).width;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const ValueKey('autocomplete-popup-categories'),
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final category in filter.categories)
          _CategoryButton(
            category: category,
            chosen: filter.chosen.contains(category),
            count: filter.counts?[category],
            enabled: filter.canChoose(category),
            onPressed: () => filter.onToggleCategory(category),
          ),
      ],
    );
  }
}

class _CategoryButton extends StatefulWidget {
  const _CategoryButton({
    required this.category,
    required this.chosen,
    required this.count,
    required this.enabled,
    required this.onPressed,
  });

  final TagCategory category;
  final bool chosen;
  final int? count;
  final bool enabled;
  final VoidCallback onPressed;

  static Size extentOf(BuildContext context) {
    final policy = context.interactionPolicy;
    return policy.touchAvailable
        ? Size(policy.minimumControlExtent, policy.minimumControlExtent - 4)
        : const Size(32, 28);
  }

  @override
  State<_CategoryButton> createState() => _CategoryButtonState();
}

class _CategoryButtonState extends State<_CategoryButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final policy = context.interactionPolicy;
    final extent = _CategoryButton.extentOf(context);
    final label = CompletionCategoryStyle.label(context, widget.category);
    final count = widget.count;
    final enabled = widget.enabled;
    final iconColor = !enabled
        ? colors.outline.withValues(alpha: 0.6)
        : widget.chosen
        ? colors.onPrimaryContainer
        : CompletionCategoryStyle.color(context, widget.category);
    final background = widget.chosen
        ? colors.primaryContainer
        : _hovered && enabled
        ? colors.onSurface.withValues(alpha: 0.08)
        : Colors.transparent;
    return Focus(
      canRequestFocus: false,
      descendantsAreFocusable: false,
      child: Tooltip(
        message: label,
        child: Semantics(
          button: true,
          enabled: enabled,
          selected: widget.chosen,
          label: count == null
              ? label
              : context.l10n.autocomplete_relatedFilterCount(label, count),
          excludeSemantics: true,
          child: MouseRegion(
            cursor: enabled
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            onEnter: policy.precisePointerAvailable
                ? (_) => setState(() => _hovered = true)
                : null,
            onExit: policy.precisePointerAvailable
                ? (_) => setState(() => _hovered = false)
                : null,
            child: Material(
              key: ValueKey(
                'autocomplete-popup-category-${widget.category.name}',
              ),
              color: background,
              borderRadius: BorderRadius.circular(10),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: enabled ? widget.onPressed : null,
                child: SizedBox(
                  width: extent.width,
                  height: extent.height,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(
                        CompletionCategoryStyle.icon(widget.category),
                        size: policy.touchAvailable ? 20 : 16,
                        color: iconColor,
                      ),
                      if (count != null)
                        PositionedDirectional(
                          top: policy.touchAvailable ? 3 : 1,
                          end: policy.touchAvailable ? 4 : 2,
                          child: Text(
                            _countLabel(count),
                            maxLines: 1,
                            textScaler: MediaQuery.textScalerOf(
                              context,
                            ).clamp(maxScaleFactor: 1.3),
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontFamily: completionTileFontFamily,
                              fontSize: policy.touchAvailable ? 11 : 9.5,
                              height: 1,
                              color: widget.chosen
                                  ? colors.onPrimaryContainer
                                  : colors.onSurfaceVariant,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _countLabel(int count) {
    if (count >= 10000) return '${count ~/ 1000}K';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return '$count';
  }
}
