import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/autocomplete/completion_models.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/widgets/autocomplete/completion_tile_layout.dart';

CompletionCandidate _candidate(
  String tag, {
  TagCategory category = TagCategory.general,
  int postCount = 1200,
  String? translation = '翻译',
  CompletionMatchKind matchKind = CompletionMatchKind.englishPrefix,
  Set<CompletionSourceKind> sources = const {CompletionSourceKind.base},
  bool isExisting = false,
  double? relatedScore,
}) => CompletionCandidate(
  canonicalTag: tag,
  category: category,
  postCount: postCount,
  translation: translation,
  matchKind: matchKind,
  sources: sources,
  isExisting: isExisting,
  relatedScore: relatedScore,
);

Future<BuildContext> _context(WidgetTester tester, {double scale = 1}) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Builder(
          builder: (context) {
            captured = context;
            return const SizedBox();
          },
        ),
      ),
    ),
  );
  return captured;
}

CompletionTileContent _content(
  BuildContext context,
  CompletionCandidate candidate, {
  List<int>? sections,
}) => CompletionTileContent.resolve(
  context,
  candidate,
  showCategory: true,
  showCount: true,
  showTranslations: true,
  showAliases: true,
  showMatchNote: true,
  sections: sections,
);

void main() {
  testWidgets('rows keep match order and wrap a tile that does not fit', (
    tester,
  ) async {
    final context = await _context(tester);
    final metrics = CompletionTileMetrics.of(context);
    final contents = [
      for (final tag in [
        'seaside',
        'seaside_sukeban_(smg)_(blue_archive)',
        'sky',
        'beach',
        'ocean',
        'cloud',
      ])
        _content(context, _candidate(tag)),
    ];
    final layout = CompletionRowsLayout.pack(
      contents: contents,
      measurer: CompletionTileMeasurer(),
      metrics: metrics,
      width: 330,
      gap: 4,
    );

    final order = [
      for (final row in layout.rows)
        for (var index = row.start; index < row.end; index++) index,
    ];
    expect(order, [0, 1, 2, 3, 4, 5]);
    for (final row in layout.rows) {
      final used =
          row.widths.fold<double>(0, (sum, width) => sum + width) +
          (row.end - row.start - 1) * 4;
      expect(used, lessThanOrEqualTo(330.01));
      if (row != layout.rows.last) {
        // Justified: the spare width is shared out.
        expect(used, moreOrLessEquals(330, epsilon: 0.01));
      }
    }
    expect(layout.rowOf(0), 0);
    expect(layout.rowOf(5), layout.rows.length - 1);
  });

  testWidgets('the last row keeps natural widths', (tester) async {
    final context = await _context(tester);
    final metrics = CompletionTileMetrics.of(context);
    final measurer = CompletionTileMeasurer();
    final content = _content(context, _candidate('sky'));
    final layout = CompletionRowsLayout.pack(
      contents: [content],
      measurer: measurer,
      metrics: metrics,
      width: 330,
      gap: 4,
    );
    expect(
      layout.rows.single.widths.single,
      measurer.measure(content, metrics).width,
    );
  });

  testWidgets('a tile wider than the row takes the row and grows taller', (
    tester,
  ) async {
    final context = await _context(tester, scale: 3);
    final metrics = CompletionTileMetrics.of(context);
    final measurer = CompletionTileMeasurer();
    final content = _content(
      context,
      _candidate('very_long_character_name_(costume)_(some_long_series_name)'),
    );
    final natural = measurer.measure(content, metrics);
    expect(natural.width, greaterThan(320));
    final layout = CompletionRowsLayout.pack(
      contents: [content, _content(context, _candidate('sky'))],
      measurer: measurer,
      metrics: metrics,
      width: 320,
      gap: 4,
    );
    expect(layout.rows.first.widths.single, 320);
    expect(layout.rows.first.height, greaterThan(natural.height));
    expect(layout.rows, hasLength(2));
  });

  testWidgets('every tile is at least as tall as the touch target', (
    tester,
  ) async {
    final context = await _context(tester);
    final metrics = CompletionTileMetrics.of(context);
    final measure = CompletionTileMeasurer().measure(
      _content(context, _candidate('sky', translation: null)),
      metrics,
    );
    expect(measure.height, greaterThanOrEqualTo(metrics.minHeight));
  });

  testWidgets('content shows every piece of candidate information', (
    tester,
  ) async {
    final context = await _context(tester);
    final related = _content(
      context,
      _candidate(
        'kousaka_honoka',
        category: TagCategory.character,
        translation: null,
        matchKind: CompletionMatchKind.pinyin,
        relatedScore: 0.014,
        sources: const {
          CompletionSourceKind.cooccurrence,
          CompletionSourceKind.base,
        },
        isExisting: true,
      ),
      sections: const [1, 2, 3, 4],
    );
    expect(related.showIcon, isTrue);
    expect(related.metric, '1.4%');
    expect(related.seal, '拼');
    expect(related.secondaryKind, CompletionSecondaryKind.missing);
    expect(related.secondary, '未汉化');
    expect(related.sectionLabel, '1 · 2 · 3 +1');
    expect(related.badgeLabel, '1 · 2 · 3 +1');
    expect(related.writtenLabel, isNull);

    // Outside a grouped prompt a written tag says so without sections.
    final written = _content(context, _candidate('sky', isExisting: true));
    expect(written.sectionLabel, isNull);
    expect(written.badgeLabel, '已写');

    final general = _content(context, _candidate('sky', postCount: 1250000));
    expect(general.showIcon, isFalse);
    expect(general.metric, '1.3M');
    expect(general.seal, isNull);
  });

  testWidgets('geometry maps candidates to row spans and back', (tester) async {
    final context = await _context(tester);
    final metrics = CompletionTileMetrics.of(context);
    final contents = [
      for (var index = 0; index < 30; index++)
        _content(context, _candidate('tag_$index')),
    ];
    final layout = CompletionRowsLayout.pack(
      contents: contents,
      measurer: CompletionTileMeasurer(),
      metrics: metrics,
      width: 330,
      gap: 4,
    );
    final last = layout.rows.last;
    final span = layout.spanOf(29);
    expect(span.top, last.top);
    expect(span.bottom, last.top + last.height);
    final visible = layout.indicesBetween(0, layout.rows.first.height);
    expect(visible!.first, 0);
    expect(visible.last, layout.rows.first.end - 1);
  });
}
