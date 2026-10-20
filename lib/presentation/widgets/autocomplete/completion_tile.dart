import 'package:flutter/material.dart';

import '../../../core/utils/localization_extension.dart';
import '../../themes/core/layered_surface_style.dart';
import 'completion_category_style.dart';
import 'completion_source_style.dart';
import 'completion_tile_layout.dart';

/// One candidate as a compact block: the tag on the first line with its
/// count raised after it, the translation under it like ruby text, and on
/// that second line the match seal, the grouped-prompt sections and one dot
/// per source. Tags already written are faded and cannot be inserted; their
/// section badge stays clear.
class CompletionTile extends StatelessWidget {
  const CompletionTile({
    super.key,
    required this.content,
    required this.metrics,
    required this.selected,
    required this.heat,
    required this.onTap,
    this.picked,
    this.onLongPress,
  });

  final CompletionTileContent content;
  final CompletionTileMetrics metrics;

  /// The keyboard selection.
  final bool selected;

  /// Whether the tile is picked in multi-select; null outside that mode.
  final bool? picked;

  /// Popularity or relatedness against the list, 0 to 1; drawn as a thin
  /// bar along the bottom edge. Null draws none.
  final double? heat;
  final VoidCallback onTap;

  /// Starts multi-select, or picks the tile while it is on.
  final VoidCallback? onLongPress;

  static const double radius = 9;
  static const double pickedRingWidth = 1.5;
  static const double heatBarHeight = 2;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final candidate = content.candidate;
    final categoryColor = CompletionCategoryStyle.color(
      context,
      candidate.category,
    );
    final existing = candidate.isExisting;
    Widget faded(Widget child) =>
        existing ? Opacity(opacity: 0.42, child: child) : child;

    final body = Padding(
      padding: const EdgeInsets.fromLTRB(
        CompletionTileMetrics.horizontalPadding,
        CompletionTileMetrics.topPadding,
        CompletionTileMetrics.horizontalPadding,
        CompletionTileMetrics.bottomPadding,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          faded(
            _TagLine(content: content, metrics: metrics, color: categoryColor),
          ),
          const SizedBox(height: CompletionTileMetrics.lineGap),
          _SecondaryLine(content: content, metrics: metrics, faded: faded),
        ],
      ),
    );

    final heat = this.heat;
    final picked = this.picked;
    return Semantics(
      button: !existing,
      selected: picked == null ? selected : null,
      checked: picked,
      enabled: !existing,
      label: _semanticLabel(context),
      onTap: existing ? null : onTap,
      onLongPress: existing ? null : onLongPress,
      excludeSemantics: true,
      child: Material(
        color: (picked ?? selected)
            ? colors.primaryContainer
            : controlSurfaceColor(colors),
        // A pick also carries a ring, so it never reads as the keyboard
        // selection of a single insert.
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: picked == true
              ? BorderSide(color: colors.primary, width: pickedRingWidth)
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: existing ? null : onTap,
          onLongPress: existing ? null : onLongPress,
          child: Stack(
            children: [
              Positioned.fill(child: body),
              if (heat != null && heat > 0)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: heatBarHeight,
                  child: faded(
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: FractionallySizedBox(
                        key: const ValueKey('autocomplete-candidate-heat'),
                        widthFactor: heat.clamp(0.06, 1.0),
                        heightFactor: 1,
                        child: ColoredBox(
                          color: categoryColor.withValues(alpha: 0.55),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _semanticLabel(BuildContext context) {
    final candidate = content.candidate;
    final sections = content.sections;
    return [
      candidate.canonicalTag,
      CompletionCategoryStyle.label(context, candidate.category),
      if (content.metric.isNotEmpty) content.metricTooltip,
      if (content.secondary.isNotEmpty) content.secondary,
      if (content.sealTooltip case final note?) note,
      CompletionSourceStyle.ordered(candidate.sources)
          .map((source) => CompletionSourceStyle.name(context, source))
          .join(' · '),
      if (sections != null)
        context.l10n.autocomplete_duplicateInSections(sections.join('、')),
    ].where((part) => part.isNotEmpty).join(', ');
  }
}

class _TagLine extends StatelessWidget {
  const _TagLine({
    required this.content,
    required this.metrics,
    required this.color,
  });

  final CompletionTileContent content;
  final CompletionTileMetrics metrics;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final category = content.candidate.category;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (content.showIcon) ...[
          Padding(
            // Centred on the first line of the tag.
            padding: EdgeInsets.only(
              top: ((metrics.tagLineHeight - metrics.iconSize) / 2).clamp(
                0.0,
                double.infinity,
              ),
            ),
            child: Tooltip(
              message: CompletionCategoryStyle.label(context, category),
              child: Icon(
                CompletionCategoryStyle.icon(category),
                key: ValueKey('autocomplete-category-${category.name}'),
                size: metrics.iconSize,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: CompletionTileMetrics.iconGap),
        ],
        Flexible(
          child: Text(
            content.candidate.canonicalTag,
            style: metrics.tag.copyWith(color: color),
          ),
        ),
        if (content.metric.isNotEmpty) ...[
          const SizedBox(width: CompletionTileMetrics.metricGap),
          Tooltip(
            message: content.metricTooltip,
            child: Text(
              content.metric,
              key: const ValueKey('autocomplete-candidate-metric'),
              maxLines: 1,
              style: metrics.metric.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SecondaryLine extends StatelessWidget {
  const _SecondaryLine({
    required this.content,
    required this.metrics,
    required this.faded,
  });

  final CompletionTileContent content;
  final CompletionTileMetrics metrics;
  final Widget Function(Widget child) faded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final kind = content.secondaryKind;
    final textColor = switch (kind) {
      CompletionSecondaryKind.missing => colors.outline,
      _ => colors.onSurfaceVariant,
    };
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: metrics.sealExtent),
      child: Row(
        children: [
          if (content.seal case final seal?)
            faded(
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  end: CompletionTileMetrics.sealGap,
                ),
                child: _MatchSeal(
                  seal: seal,
                  tooltip: content.sealTooltip ?? seal,
                  metrics: metrics,
                ),
              ),
            ),
          if (kind == CompletionSecondaryKind.translating)
            faded(
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  end: CompletionTileMetrics.sealGap,
                ),
                child: SizedBox.square(
                  dimension: metrics.spinnerSize,
                  child: CircularProgressIndicator(
                    value: MediaQuery.disableAnimationsOf(context)
                        ? 0.75
                        : null,
                    strokeWidth: 1.5,
                    color: colors.primary,
                  ),
                ),
              ),
            ),
          Expanded(
            child: faded(
              Text(
                content.secondary,
                style: metrics.secondary.copyWith(
                  color: textColor,
                  fontStyle: kind == CompletionSecondaryKind.missing
                      ? FontStyle.italic
                      : null,
                ),
              ),
            ),
          ),
          if (content.sections case final sections?) ...[
            const SizedBox(width: CompletionTileMetrics.trailingGap),
            _SectionBadge(
              sections: sections,
              label: content.sectionLabel!,
              metrics: metrics,
            ),
          ],
          if (content.showSources) ...[
            const SizedBox(width: CompletionTileMetrics.trailingGap),
            faded(CompletionSourceDots(sources: content.candidate.sources)),
          ],
        ],
      ),
    );
  }
}

/// A one-character mark for how a non-literal row matched; the tooltip
/// gives the full name and the corrected or split words.
class _MatchSeal extends StatelessWidget {
  const _MatchSeal({
    required this.seal,
    required this.tooltip,
    required this.metrics,
  });

  final String seal;
  final String tooltip;
  final CompletionTileMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.tertiary;
    return Tooltip(
      message: tooltip,
      child: Container(
        key: const ValueKey('autocomplete-candidate-seal'),
        constraints: BoxConstraints(
          minWidth: metrics.sealExtent,
          minHeight: metrics.sealExtent,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 3),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          seal,
          maxLines: 1,
          style: metrics.seal.copyWith(color: color),
        ),
      ),
    );
  }
}

/// Where an already written tag sits in a grouped prompt: the section icon
/// and the section numbers, counted like the cards (left to right, top to
/// bottom). Three numbers at most; the tooltip lists them all.
class _SectionBadge extends StatelessWidget {
  const _SectionBadge({
    required this.sections,
    required this.label,
    required this.metrics,
  });

  final List<int> sections;
  final String label;
  final CompletionTileMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final description = context.l10n.autocomplete_duplicateInSections(
      sections.join('、'),
    );
    return Tooltip(
      message: description,
      child: Container(
        key: const ValueKey('autocomplete-candidate-sections'),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: colors.secondaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.view_agenda_outlined,
              size: metrics.sectionIconSize,
              color: colors.onSecondaryContainer,
            ),
            const SizedBox(width: CompletionTileMetrics.sectionIconGap),
            Text(
              label,
              maxLines: 1,
              style: metrics.section.copyWith(
                color: colors.onSecondaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
