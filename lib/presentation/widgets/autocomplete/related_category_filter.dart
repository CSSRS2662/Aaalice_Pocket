import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/autocomplete/completion_models.dart';
import '../../../core/utils/localization_extension.dart';
import '../../adaptive/interaction_policy.dart';
import '../../themes/core/layered_surface_style.dart';

/// The categories the related suggestions of one tag are narrowed to, and
/// how the popup changes them.
class RelatedCategoryFilter {
  const RelatedCategoryFilter({
    required this.chosen,
    required this.open,
    required this.onTogglePanel,
    required this.onToggleCategory,
    required this.onClear,
    this.counts,
    this.listsOnlineRows = false,
  });

  /// The categories on offer, in the order of the cards.
  static const List<TagCategory> categories = [
    TagCategory.character,
    TagCategory.copyright,
    TagCategory.general,
  ];

  final Set<TagCategory> chosen;

  /// Whether the cards are showing.
  final bool open;

  /// Related tags per category in the local data; null until counted.
  final Map<TagCategory, int>? counts;

  /// Whether online rows may add to a category the local data has none of.
  final bool listsOnlineRows;
  final VoidCallback onTogglePanel;
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

/// The funnel in the header of a related popup: a tap shows or hides the
/// category cards, a long press clears the chosen categories. Filled and
/// tinted while any are chosen. Like the other popup controls it never takes
/// focus from the field.
class RelatedCategoryFilterButton extends StatefulWidget {
  const RelatedCategoryFilterButton({super.key, required this.filter});

  final RelatedCategoryFilter filter;

  @override
  State<RelatedCategoryFilterButton> createState() =>
      _RelatedCategoryFilterButtonState();
}

class _RelatedCategoryFilterButtonState
    extends State<RelatedCategoryFilterButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final policy = context.interactionPolicy;
    final filter = widget.filter;
    final extent = policy.touchAvailable ? policy.minimumControlExtent : 28.0;
    final tinted = filter.active || _hovered;
    final label = context.l10n.autocomplete_relatedFilter;
    return Focus(
      canRequestFocus: false,
      descendantsAreFocusable: false,
      child: Tooltip(
        message: label,
        // A long press clears the filter; it must not open the tooltip.
        triggerMode: TooltipTriggerMode.manual,
        child: Semantics(
          label: label,
          button: true,
          selected: filter.active,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: policy.precisePointerAvailable
                ? (_) => setState(() => _hovered = true)
                : null,
            onExit: policy.precisePointerAvailable
                ? (_) => setState(() => _hovered = false)
                : null,
            child: AnimatedContainer(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              width: extent,
              height: extent,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: tinted
                    ? colors.primary.withValues(
                        alpha: filter.active ? 0.2 : 0.16,
                      )
                    : filter.open
                    ? colors.onSurface.withValues(alpha: 0.08)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  key: const ValueKey('autocomplete-popup-related-filter'),
                  canRequestFocus: false,
                  onTap: filter.onTogglePanel,
                  // Handled even with nothing chosen, so that a long press
                  // never ends as a tap on the cards.
                  onLongPress: () {
                    if (filter.active) filter.onClear();
                  },
                  child: Icon(
                    filter.active
                        ? Icons.filter_alt_rounded
                        : Icons.filter_alt_outlined,
                    size: policy.touchAvailable ? 20 : 16,
                    color: tinted
                        ? colors.primary
                        : filter.open
                        ? colors.onSurface
                        : colors.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The category cards of a related popup. A tap lists only that category;
/// several chosen list any of them. Tall cards (icon over name over count)
/// where there is room, one-line cards otherwise.
class RelatedCategoryFilterPanel extends StatelessWidget {
  const RelatedCategoryFilterPanel({
    super.key,
    required this.filter,
    required this.compact,
    this.floating = true,
  });

  final RelatedCategoryFilter filter;
  final bool compact;

  /// Floats over the list with a shadow. Otherwise a plain row that scrolls
  /// sideways, for a popup too short to float anything.
  final bool floating;

  static const double _padding = 8;
  static const double _gap = 6;

  /// The panel's height at the current text size.
  static double extentOf(BuildContext context, {required bool compact}) =>
      _cardExtent(context, compact: compact) + _padding * 2;

  static double _cardExtent(BuildContext context, {required bool compact}) {
    final scaler = MediaQuery.textScalerOf(context);
    final name = scaler.scale(_nameSize) * _lineHeight;
    final count = scaler.scale(_countSize) * _lineHeight;
    if (!compact) return 24 + 2 + name + count + 20;
    final minimum = context.interactionPolicy.touchAvailable ? 44.0 : 32.0;
    return math.max(minimum, math.max(name, 18.0) + 14);
  }

  static const double _nameSize = 13;
  static const double _countSize = 11;
  static const double _lineHeight = 1.3;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final surface = overlaySurfaceColor(colors);
    final cards = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (index, category)
            in RelatedCategoryFilter.categories.indexed) ...[
          if (index > 0) const SizedBox(width: _gap),
          _CategoryCard(
            filter: filter,
            category: category,
            compact: compact,
            extent: _cardExtent(context, compact: compact),
            surface: surface,
          ),
        ],
      ],
    );
    return Focus(
      canRequestFocus: false,
      descendantsAreFocusable: false,
      child: floating
          ? Container(
              key: const ValueKey('autocomplete-related-filter-panel'),
              padding: const EdgeInsets.all(_padding),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 24,
                    offset: const Offset(0, 9),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 5,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: cards,
            )
          : Container(
              key: const ValueKey('autocomplete-related-filter-panel'),
              color: surface,
              alignment: AlignmentDirectional.centerEnd,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                padding: const EdgeInsets.all(_padding),
                child: cards,
              ),
            ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.filter,
    required this.category,
    required this.compact,
    required this.extent,
    required this.surface,
  });

  final RelatedCategoryFilter filter;
  final TagCategory category;
  final bool compact;
  final double extent;

  /// The colour of the panel the card sits on.
  final Color surface;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final selected = filter.chosen.contains(category);
    final enabled = filter.canChoose(category);
    final count = filter.counts?[category];
    final name = _name(context);
    final ink = selected ? colors.onPrimaryContainer : colors.onSurface;
    final nameText = Text(
      name,
      maxLines: 1,
      style: theme.textTheme.labelMedium?.copyWith(
        color: ink,
        fontSize: RelatedCategoryFilterPanel._nameSize,
        height: RelatedCategoryFilterPanel._lineHeight,
        fontWeight: FontWeight.w600,
      ),
    );
    final countText = Text(
      count == null ? '' : '$count',
      maxLines: 1,
      style: theme.textTheme.labelSmall?.copyWith(
        color: selected ? ink : colors.onSurfaceVariant,
        fontSize: RelatedCategoryFilterPanel._countSize,
        height: RelatedCategoryFilterPanel._lineHeight,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    final icon = Icon(
      _icon(selected),
      size: compact ? 18 : 24,
      color: selected ? ink : colors.onSurfaceVariant,
    );
    return Semantics(
      label: count == null
          ? name
          : context.l10n.autocomplete_relatedFilterCount(name, count),
      button: true,
      selected: selected,
      enabled: enabled,
      onTap: enabled ? () => filter.onToggleCategory(category) : null,
      excludeSemantics: true,
      child: Opacity(
        opacity: enabled ? 1 : 0.38,
        child: Material(
          color: selected
              ? colors.primaryContainer
              : Color.alphaBlend(
                  colors.onSurface.withValues(alpha: 0.07),
                  surface,
                ),
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('autocomplete-related-filter-${category.name}'),
            canRequestFocus: false,
            onTap: enabled ? () => filter.onToggleCategory(category) : null,
            child: Stack(
              children: [
                Container(
                  constraints: BoxConstraints(minWidth: compact ? 0 : 84),
                  height: extent,
                  padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 10),
                  alignment: Alignment.center,
                  child: compact
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            icon,
                            const SizedBox(width: 6),
                            nameText,
                            const SizedBox(width: 5),
                            countText,
                          ],
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            icon,
                            const SizedBox(height: 2),
                            nameText,
                            countText,
                          ],
                        ),
                ),
                if (selected)
                  PositionedDirectional(
                    top: 3,
                    end: 4,
                    child: Icon(Icons.check_rounded, size: 13, color: ink),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _name(BuildContext context) => switch (category) {
    TagCategory.character => context.l10n.autocomplete_relatedFilterCharacter,
    TagCategory.copyright => context.l10n.autocomplete_relatedFilterSeries,
    _ => context.l10n.autocomplete_relatedFilterGeneral,
  };

  IconData _icon(bool selected) => switch (category) {
    TagCategory.character =>
      selected ? Icons.person_rounded : Icons.person_outline_rounded,
    TagCategory.copyright =>
      selected ? Icons.menu_book_rounded : Icons.menu_book_outlined,
    _ => selected ? Icons.sell_rounded : Icons.sell_outlined,
  };
}
