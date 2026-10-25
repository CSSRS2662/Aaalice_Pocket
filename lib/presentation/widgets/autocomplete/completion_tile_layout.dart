import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/autocomplete/completion_models.dart';
import '../../../core/utils/localization_extension.dart';
import '../../adaptive/interaction_policy.dart';
import 'completion_category_style.dart';
import 'completion_source_style.dart';

/// Font of the tag, the count and the source codes: a condensed face fits
/// more tags on a row; other scripts fall back to the theme font.
const String completionTileFontFamily = 'Roboto Condensed';

/// What one candidate tile shows, resolved from the candidate and the
/// display settings. The tile widget and the row packing both read it, so
/// what is measured is exactly what is drawn.
@immutable
class CompletionTileContent {
  const CompletionTileContent({
    required this.candidate,
    required this.showIcon,
    required this.metric,
    required this.metricTooltip,
    required this.seal,
    required this.sealTooltip,
    required this.secondary,
    required this.secondaryKind,
    required this.sections,
    required this.showSources,
    this.writtenLabel,
  });

  factory CompletionTileContent.resolve(
    BuildContext context,
    CompletionCandidate candidate, {
    required bool showCategory,
    required bool showCount,
    required bool showTranslations,
    required bool showAliases,
    required bool showMatchNote,
    List<int>? sections,
  }) {
    final l10n = context.l10n;
    final (secondary, kind) = switch (candidate) {
      _ when showTranslations && candidate.translation?.isNotEmpty == true => (
        candidate.translation!,
        CompletionSecondaryKind.translation,
      ),
      _ when showTranslations && candidate.isTranslating => (
        l10n.autocomplete_translating,
        CompletionSecondaryKind.translating,
      ),
      _ when showTranslations => (
        l10n.autocomplete_missingTranslation,
        CompletionSecondaryKind.missing,
      ),
      _ when showAliases && candidate.matchedAlias?.isNotEmpty == true => (
        l10n.autocomplete_aliasMatch(candidate.matchedAlias!),
        CompletionSecondaryKind.alias,
      ),
      _ => ('', CompletionSecondaryKind.none),
    };
    final note = showMatchNote ? completionMatchSeal(context, candidate) : null;
    final inSections = sections != null && sections.isNotEmpty;
    return CompletionTileContent(
      candidate: candidate,
      showIcon:
          showCategory && CompletionCategoryStyle.marksTile(candidate.category),
      metric: showCount ? completionMetricLabel(candidate) : '',
      metricTooltip: completionMetricTooltip(context, candidate),
      seal: note?.seal,
      sealTooltip: note?.tooltip,
      secondary: secondary,
      secondaryKind: kind,
      sections: inSections ? sections : null,
      showSources: candidate.sources.isNotEmpty,
      writtenLabel: candidate.isExisting && !inSections
          ? l10n.autocomplete_writtenBadge
          : null,
    );
  }

  final CompletionCandidate candidate;
  final bool showIcon;
  final String metric;
  final String metricTooltip;
  final String? seal;
  final String? sealTooltip;
  final String secondary;
  final CompletionSecondaryKind secondaryKind;
  final List<int>? sections;
  final bool showSources;

  /// The badge of a tag already written outside a grouped prompt, which has
  /// no sections to name.
  final String? writtenLabel;

  /// Section numbers shown on the badge: three at most, the rest counted.
  String? get sectionLabel {
    final numbers = sections;
    if (numbers == null) return null;
    return [
      numbers.take(3).join(' · '),
      if (numbers.length > 3) '+${numbers.length - 3}',
    ].join(' ');
  }

  /// The text of the badge on an already written tag: where it sits in a
  /// grouped prompt, else that it is written.
  String? get badgeLabel => sectionLabel ?? writtenLabel;

  /// Everything that changes the tile's natural size.
  String get signature => [
    candidate.stableId,
    candidate.category.name,
    showIcon,
    metric,
    seal,
    secondary,
    secondaryKind.name,
    badgeLabel,
    candidate.sources.length,
  ].join('\u0001');
}

enum CompletionSecondaryKind { translation, translating, missing, alias, none }

/// The one-character seal for a non-literal match (pinyin, typo fix, …) and
/// its full description; null for literal matches.
({String seal, String tooltip})? completionMatchSeal(
  BuildContext context,
  CompletionCandidate candidate,
) {
  final l10n = context.l10n;
  final (kind, label) = switch (candidate.matchKind) {
    CompletionMatchKind.homophone => (
      'homophone',
      l10n.autocomplete_matchHomophone,
    ),
    CompletionMatchKind.fuzzyPinyin => (
      'fuzzyPinyin',
      l10n.autocomplete_matchFuzzyPinyin,
    ),
    CompletionMatchKind.pinyin => ('pinyin', l10n.autocomplete_matchPinyin),
    CompletionMatchKind.shuangpin => (
      'shuangpin',
      l10n.autocomplete_matchShuangpin,
    ),
    CompletionMatchKind.pinyinInitials => (
      'initials',
      l10n.autocomplete_matchInitials,
    ),
    CompletionMatchKind.approximate => (
      'approximate',
      l10n.autocomplete_matchApproximate,
    ),
    CompletionMatchKind.crossLingual => (
      'crossLingual',
      l10n.autocomplete_matchCrossLingual,
    ),
    CompletionMatchKind.spellCorrected => (
      'spellCorrected',
      l10n.autocomplete_matchSpellCorrected,
    ),
    CompletionMatchKind.englishVariant => (
      'englishVariant',
      l10n.autocomplete_matchEnglishVariant,
    ),
    CompletionMatchKind.fullText when candidate.semanticScore != null => (
      'semantic',
      l10n.autocomplete_matchSemantic,
    ),
    _ => (null, null),
  };
  if (kind == null || label == null) return null;
  final hint = candidate.matchHint;
  return (
    seal: l10n.autocomplete_matchSeal(kind),
    tooltip: hint == null || hint.isEmpty ? label : '$label · $hint',
  );
}

/// Post count, or the related share for related suggestions.
String completionMetricLabel(CompletionCandidate candidate) {
  final score = candidate.relatedScore;
  if (score != null) {
    final percent = score * 100;
    return percent >= 10
        ? '${percent.toStringAsFixed(0)}%'
        : '${percent.toStringAsFixed(1)}%';
  }
  return candidate.postCount > 0
      ? compactCompletionCount(candidate.postCount)
      : '';
}

String completionMetricTooltip(
  BuildContext context,
  CompletionCandidate candidate,
) {
  final score = candidate.relatedScore;
  if (score == null) return compactCompletionCount(candidate.postCount);
  return context.l10n.autocomplete_relatedMetric(
    candidate.cooccurrenceCount ?? 0,
    '${(score * 100).toStringAsFixed(2)}%',
  );
}

String compactCompletionCount(int value) {
  if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
  return '$value';
}

/// Type sizes, spacing and minimum height of candidate tiles for the
/// current theme, text scale and input.
class CompletionTileMetrics {
  CompletionTileMetrics.of(BuildContext context)
    : scaler = MediaQuery.textScalerOf(context),
      direction = Directionality.of(context),
      minHeight = context.interactionPolicy.touchAvailable
          ? context.interactionPolicy.minimumControlExtent
          : 0,
      tag = Theme.of(context).textTheme.bodyLarge!.copyWith(
        fontFamily: completionTileFontFamily,
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1.1,
        letterSpacing: 0,
      ),
      metric = Theme.of(context).textTheme.labelSmall!.copyWith(
        fontFamily: completionTileFontFamily,
        fontSize: 11,
        fontWeight: FontWeight.w400,
        height: 1,
        letterSpacing: 0,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      secondary = Theme.of(context).textTheme.bodySmall!.copyWith(
        fontSize: 11.5,
        height: 1.2,
        letterSpacing: 0,
      ),
      seal = Theme.of(context).textTheme.labelSmall!.copyWith(
        fontSize: 10.5,
        height: 1,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      section = Theme.of(context).textTheme.labelSmall!.copyWith(
        fontFamily: completionTileFontFamily,
        fontSize: 11,
        height: 1,
        letterSpacing: 0,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static const double horizontalPadding = 8;
  static const double topPadding = 3;
  static const double bottomPadding = 4;
  static const double lineGap = 1;
  static const double iconGap = 3;
  static const double metricGap = 3;
  static const double sealGap = 4;
  static const double trailingGap = 6;
  static const double sectionIconGap = 2;

  final TextScaler scaler;
  final TextDirection direction;
  final double minHeight;
  final TextStyle tag;
  final TextStyle metric;
  final TextStyle secondary;
  final TextStyle seal;
  final TextStyle section;

  double get iconSize => scaler.scale(13);
  double get tagLineHeight => scaler.scale(tag.fontSize!) * tag.height!;
  double get sealExtent => scaler.scale(15);
  double get spinnerSize => scaler.scale(11);
  double get sectionIconSize => scaler.scale(11);

  /// Identifies the metrics in layout caches.
  String get signature =>
      '${scaler.scale(100).toStringAsFixed(2)}|${minHeight.toStringAsFixed(1)}|'
      '${tag.fontFamily}|${secondary.fontFamily}|${direction.name}';
}

/// Natural size of one tile and the pieces its rows are built from.
@immutable
class CompletionTileMeasure {
  const CompletionTileMeasure({
    required this.width,
    required this.height,
    required this.leadWidth,
    required this.trailWidth,
    required this.lineOneHeight,
  });

  /// Width with every text on one line.
  final double width;

  /// Height with every text on one line, at least the minimum height.
  final double height;

  /// Space on line one besides the tag text: the icon and the count.
  final double leadWidth;

  /// Space on line two besides the secondary text: seal, badge and dots.
  final double trailWidth;
  final double lineOneHeight;
}

/// Measures tiles with text painters, caching natural sizes per content.
class CompletionTileMeasurer {
  final Map<String, CompletionTileMeasure> _cache = {};
  String? _metricsSignature;

  CompletionTileMeasure measure(
    CompletionTileContent content,
    CompletionTileMetrics metrics,
  ) {
    if (_metricsSignature != metrics.signature) {
      _cache.clear();
      _metricsSignature = metrics.signature;
    }
    if (_cache.length > 2000) _cache.clear();
    return _cache.putIfAbsent(
      content.signature,
      () => _measure(content, metrics),
    );
  }

  /// Height when the tile is held to [width]: long texts wrap.
  double heightAt(
    CompletionTileContent content,
    CompletionTileMetrics metrics,
    CompletionTileMeasure natural,
    double width,
  ) {
    final inner = width - CompletionTileMetrics.horizontalPadding * 2;
    final tag = _painter(
      content.candidate.canonicalTag,
      metrics.tag,
      metrics,
      maxWidth: math.max(inner - natural.leadWidth, 1),
    );
    final secondary = _painter(
      content.secondary,
      metrics.secondary,
      metrics,
      maxWidth: math.max(inner - natural.trailWidth, 1),
    );
    final lineTwo = math.max(secondary.height, _lineTwoMinimum(metrics));
    final height =
        CompletionTileMetrics.topPadding +
        math.max(tag.height, natural.lineOneHeight) +
        CompletionTileMetrics.lineGap +
        lineTwo +
        CompletionTileMetrics.bottomPadding;
    tag.dispose();
    secondary.dispose();
    return math.max(height, metrics.minHeight);
  }

  CompletionTileMeasure _measure(
    CompletionTileContent content,
    CompletionTileMetrics metrics,
  ) {
    final tag = _painter(content.candidate.canonicalTag, metrics.tag, metrics);
    final metric = content.metric.isEmpty
        ? null
        : _painter(content.metric, metrics.metric, metrics);
    final secondary = _painter(content.secondary, metrics.secondary, metrics);
    final seal = content.seal == null
        ? null
        : _painter(content.seal!, metrics.seal, metrics);
    final section = content.badgeLabel == null
        ? null
        : _painter(content.badgeLabel!, metrics.section, metrics);

    final leadWidth =
        (content.showIcon
            ? metrics.iconSize + CompletionTileMetrics.iconGap
            : 0.0) +
        (metric == null ? 0.0 : CompletionTileMetrics.metricGap + metric.width);
    final lineOneHeight = math.max(
      tag.height,
      content.showIcon ? metrics.iconSize : 0.0,
    );
    final sealWidth = seal == null
        ? 0.0
        : math.max(metrics.sealExtent, seal.width + 6) +
              CompletionTileMetrics.sealGap;
    final spinnerWidth =
        content.secondaryKind == CompletionSecondaryKind.translating
        ? metrics.spinnerSize + CompletionTileMetrics.sealGap
        : 0.0;
    final sectionWidth = section == null
        ? 0.0
        : CompletionTileMetrics.trailingGap +
              metrics.sectionIconSize +
              CompletionTileMetrics.sectionIconGap +
              section.width +
              10;
    final dotsWidth = content.showSources
        ? CompletionTileMetrics.trailingGap +
              CompletionSourceDots.widthFor(content.candidate.sources.length)
        : 0.0;
    final trailWidth = sealWidth + spinnerWidth + sectionWidth + dotsWidth;
    final lineTwoHeight = math.max(secondary.height, _lineTwoMinimum(metrics));
    final width =
        CompletionTileMetrics.horizontalPadding * 2 +
        math.max(tag.width + leadWidth, secondary.width + trailWidth);
    final height =
        CompletionTileMetrics.topPadding +
        lineOneHeight +
        CompletionTileMetrics.lineGap +
        lineTwoHeight +
        CompletionTileMetrics.bottomPadding;
    for (final painter in [tag, metric, secondary, seal, section]) {
      painter?.dispose();
    }
    return CompletionTileMeasure(
      width: width.ceilToDouble(),
      height: math.max(height, metrics.minHeight).ceilToDouble(),
      leadWidth: leadWidth,
      trailWidth: trailWidth,
      lineOneHeight: lineOneHeight,
    );
  }

  static double _lineTwoMinimum(CompletionTileMetrics metrics) =>
      math.max(metrics.sealExtent, metrics.sectionIconSize + 4);

  static TextPainter _painter(
    String text,
    TextStyle style,
    CompletionTileMetrics metrics, {
    double maxWidth = double.infinity,
  }) => TextPainter(
    text: TextSpan(text: text, style: style),
    textScaler: metrics.scaler,
    textDirection: metrics.direction,
    maxLines: maxWidth.isFinite ? null : 1,
  )..layout(maxWidth: maxWidth);
}

/// One row of tiles: candidates `start` to `end` (exclusive) with the
/// widths they are drawn at.
@immutable
class CompletionRow {
  const CompletionRow({
    required this.start,
    required this.end,
    required this.widths,
    required this.height,
    required this.top,
  });

  final int start;
  final int end;
  final List<double> widths;
  final double height;

  /// Offset of the row inside the list, gaps included.
  final double top;
}

/// Candidates laid out in match order as wrapped rows. A tile that does not
/// fit after the previous ones starts the next row; rows other than the last
/// share their spare width among their tiles.
class CompletionRowsLayout {
  CompletionRowsLayout._(this.rows, this._rowOfIndex, this.gap, this.width);

  static final CompletionRowsLayout empty = CompletionRowsLayout._(
    const [],
    const [],
    0,
    0,
  );

  factory CompletionRowsLayout.pack({
    required List<CompletionTileContent> contents,
    required CompletionTileMeasurer measurer,
    required CompletionTileMetrics metrics,
    required double width,
    required double gap,
  }) {
    if (contents.isEmpty || width <= 0) return empty;
    final measures = [
      for (final content in contents) measurer.measure(content, metrics),
    ];
    final rows = <CompletionRow>[];
    final rowOfIndex = List<int>.filled(contents.length, 0);
    var top = 0.0;
    var start = 0;
    while (start < contents.length) {
      var end = start + 1;
      var used = math.min(measures[start].width, width);
      while (end < contents.length &&
          used + gap + measures[end].width <= width) {
        used += gap + measures[end].width;
        end++;
      }
      final last = end == contents.length;
      final count = end - start;
      final spare = last ? 0.0 : math.max(width - used, 0.0) / count;
      final widths = <double>[];
      var height = 0.0;
      for (var index = start; index < end; index++) {
        final natural = measures[index];
        final drawn = math.min(natural.width + spare, width);
        widths.add(drawn);
        height = math.max(
          height,
          natural.width > width
              ? measurer.heightAt(contents[index], metrics, natural, width)
              : natural.height,
        );
        rowOfIndex[index] = rows.length;
      }
      rows.add(
        CompletionRow(
          start: start,
          end: end,
          widths: widths,
          height: height,
          top: top,
        ),
      );
      top += height + gap;
      start = end;
    }
    return CompletionRowsLayout._(rows, rowOfIndex, gap, width);
  }

  final List<CompletionRow> rows;
  final List<int> _rowOfIndex;
  final double gap;
  final double width;

  bool get isEmpty => rows.isEmpty;

  /// Height of all rows with the gaps between them.
  double get extent => rows.isEmpty ? 0 : rows.last.top + rows.last.height;

  int rowOf(int index) => _rowOfIndex[index];

  /// Vertical span of the row holding candidate [index].
  ({double top, double bottom}) spanOf(int index) {
    final row = rows[_rowOfIndex[index]];
    return (top: row.top, bottom: row.top + row.height);
  }

  /// First and last candidates whose rows meet `[top, bottom]`.
  ({int first, int last})? indicesBetween(double top, double bottom) {
    int? first;
    int? last;
    for (final row in rows) {
      if (row.top + row.height < top) continue;
      if (row.top > bottom) break;
      first ??= row.start;
      last = row.end - 1;
    }
    if (first == null || last == null) return null;
    return (first: first, last: last);
  }
}
