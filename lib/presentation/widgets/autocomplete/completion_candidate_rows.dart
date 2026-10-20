import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import '../../../core/autocomplete/completion_models.dart';
import 'completion_tile.dart';
import 'completion_tile_layout.dart';

/// Where the candidate rows sit in the popup's scroll view; the field uses
/// it to keep the keyboard selection in view and to translate what is
/// on screen.
class CompletionListGeometry {
  CompletionRowsLayout layout = CompletionRowsLayout.empty;

  /// Offset of the first row inside the scroll view.
  double top = 0;

  /// Scroll span of the row holding candidate [index], or null when the
  /// rows have not been laid out for the current list.
  ({double top, double bottom})? spanOf(int index) {
    if (index < 0 || layout.isEmpty) return null;
    if (index > layout.rows.last.end - 1) return null;
    final span = layout.spanOf(index);
    return (top: span.top + top, bottom: span.bottom + top);
  }

  /// Candidates whose rows show in a viewport scrolled to [offset].
  ({int first, int last})? visibleIndices(double offset, double viewport) =>
      layout.indicesBetween(offset - top, offset + viewport - top - 0.5);
}

/// The candidates as wrapped, justified rows of [CompletionTile]s in match
/// order, followed by [trailing] in the same scroll view. Rows are built
/// lazily with their exact heights, so long lists stay cheap.
class CompletionCandidateRows extends StatelessWidget {
  const CompletionCandidateRows({
    super.key,
    required this.state,
    required this.selectedIndex,
    required this.scrollController,
    required this.touchCompact,
    required this.showAliases,
    required this.showTranslations,
    required this.showCategory,
    required this.showCount,
    required this.showMatchNote,
    required this.tagSections,
    required this.measurer,
    required this.geometry,
    required this.onSelected,
    this.onLongPressed,
    this.pickedIds,
    this.trailing = const [],
  });

  static const double gap = 4;

  final CompletionState state;
  final int selectedIndex;
  final ScrollController scrollController;
  final bool touchCompact;
  final bool showAliases;
  final bool showTranslations;
  final bool showCategory;
  final bool showCount;
  final bool showMatchNote;
  final Map<String, List<int>> tagSections;
  final CompletionTileMeasurer measurer;
  final CompletionListGeometry geometry;
  final ValueChanged<int> onSelected;
  final ValueChanged<int>? onLongPressed;

  /// Tiles picked in multi-select, by stable id; null outside that mode,
  /// which also hides the keyboard selection.
  final Set<String>? pickedIds;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = EdgeInsetsDirectional.fromSTEB(
          6,
          6,
          touchCompact ? 6 : 12,
          6,
        );
        final metrics = CompletionTileMetrics.of(context);
        final contents = [
          for (final candidate in state.candidates)
            CompletionTileContent.resolve(
              context,
              candidate,
              showCategory: showCategory,
              showCount: showCount,
              showTranslations: showTranslations,
              showAliases: showAliases,
              showMatchNote: showMatchNote,
              sections: candidate.isExisting
                  ? tagSections[candidate.canonicalTag]
                  : null,
            ),
        ];
        final layout = CompletionRowsLayout.pack(
          contents: contents,
          measurer: measurer,
          metrics: metrics,
          width: math.max(constraints.maxWidth - padding.horizontal, 0),
          gap: gap,
        );
        geometry
          ..layout = layout
          ..top = padding.top;
        final heat = _heatOf(state.candidates);
        final picked = pickedIds;
        final rows = layout.rows;
        final long = rows.length > 5;
        return Scrollbar(
          key: const ValueKey('autocomplete-popup-scrollbar'),
          controller: scrollController,
          thumbVisibility: long,
          trackVisibility: long,
          interactive: !touchCompact,
          thickness: touchCompact ? 4 : 8,
          radius: const Radius.circular(8),
          child: CustomScrollView(
            key: const ValueKey('autocomplete-popup-list'),
            controller: scrollController,
            shrinkWrap: true,
            scrollCacheExtent: const ScrollCacheExtent.pixels(400),
            slivers: [
              SliverPadding(
                padding: padding,
                sliver: SliverVariedExtentList.builder(
                  itemCount: rows.length,
                  itemExtentBuilder: (index, _) {
                    if (index >= rows.length) return null;
                    return rows[index].height +
                        (index == rows.length - 1 ? 0 : gap);
                  },
                  itemBuilder: (context, rowIndex) {
                    final row = rows[rowIndex];
                    return Align(
                      alignment: AlignmentDirectional.topStart,
                      child: SizedBox(
                        height: row.height,
                        child: Row(
                          children: [
                            for (
                              var index = row.start;
                              index < row.end;
                              index++
                            ) ...[
                              if (index > row.start) const SizedBox(width: gap),
                              SizedBox(
                                width: row.widths[index - row.start],
                                child: CompletionTile(
                                  key: ValueKey(
                                    'autocomplete-candidate-'
                                    '${state.candidates[index].stableId}',
                                  ),
                                  content: contents[index],
                                  metrics: metrics,
                                  selected:
                                      picked == null && index == selectedIndex,
                                  picked: picked?.contains(
                                    state.candidates[index].stableId,
                                  ),
                                  heat: heat?.call(state.candidates[index]),
                                  onTap: () => onSelected(index),
                                  onLongPress: onLongPressed == null
                                      ? null
                                      : () => onLongPressed!(index),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              for (final widget in trailing) SliverToBoxAdapter(child: widget),
            ],
          ),
        );
      },
    );
  }

  /// Popularity against the list for typed tags (log of the post count) and
  /// relatedness against the strongest suggestion for related tags.
  static double? Function(CompletionCandidate)? _heatOf(
    List<CompletionCandidate> candidates,
  ) {
    if (candidates.isEmpty) return null;
    final related = candidates.any(
      (candidate) => candidate.relatedScore != null,
    );
    if (related) {
      final top = candidates
          .map((candidate) => candidate.relatedScore ?? 0)
          .fold<double>(0, math.max);
      if (top <= 0) return null;
      return (candidate) {
        final score = candidate.relatedScore;
        return score == null ? null : score / top;
      };
    }
    final top = candidates
        .map((candidate) => candidate.postCount)
        .fold<int>(0, math.max);
    if (top <= 0) return null;
    final scale = math.log(top + 1);
    return (candidate) => candidate.postCount <= 0
        ? null
        : math.log(candidate.postCount + 1) / scale;
  }
}
