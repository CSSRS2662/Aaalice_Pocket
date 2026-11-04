import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nai_launcher/core/autocomplete/tag_translation_lookup.dart';
import 'package:nai_launcher/presentation/adaptive/interaction_policy.dart';
import 'package:nai_launcher/presentation/themes/modules/color/palettes/pocket_palette.dart';
import 'package:nai_launcher/presentation/themes/core/layered_surface_style.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/utils/detail_prompt_groups.dart';
import 'package:nai_launcher/presentation/widgets/common/image_detail/components/detail_prompt_groups.dart';
import 'package:nai_launcher/presentation/widgets/common/image_detail/components/detail_tag_picks.dart';

const _groups = [
  DetailPromptGroup(
    kind: DetailPromptGroupKind.section,
    tags: ['cat', 'dog'],
    offset: 0,
    number: 1,
  ),
  DetailPromptGroup(
    kind: DetailPromptGroupKind.fixed,
    tags: ['cat'],
    offset: 2,
    name: 'Saved style',
  ),
  DetailPromptGroup(
    kind: DetailPromptGroupKind.section,
    tags: ['bird'],
    offset: 3,
    number: 2,
  ),
];

Future<void> _pump(
  WidgetTester tester,
  DetailTagPicks picks, {
  required ValueChanged<DetailPromptGroup> reuse,
  double scale = 1,
  List<DetailPromptGroup> groups = _groups,
}) => tester.pumpWidget(
  ProviderScope(
    overrides: [
      tagTranslationLookupProvider.overrideWithValue(
        TagTranslationLookup.fromResolver((tags) async => {}),
      ),
    ],
    child: MaterialApp(
      theme: ThemeData(
        colorScheme: resolveLayeredSurfaceColors(
          const PocketPalette().lightScheme,
        ),
      ),
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: InteractionPolicyScope(
                initialPolicy: InteractionPolicy.touchFirst,
                child: DetailPromptGroups(
                  groups: groups,
                  negative: false,
                  tagPicks: picks,
                  onReuse: reuse,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('unnamed fixed cards do not expose tags until expanded', (
    tester,
  ) async {
    final picks = DetailTagPicks();
    addTearDown(picks.dispose);
    await _pump(
      tester,
      picks,
      reuse: (_) {},
      groups: const [
        DetailPromptGroup(
          kind: DetailPromptGroupKind.fixed,
          tags: ['private_tag', 'secret_words'],
          offset: 0,
          name: 'private_tag, secret_words',
        ),
      ],
    );
    expect(find.text('Fixed Tags'), findsOneWidget);
    expect(find.text('private_tag, secret_words'), findsNothing);
    await tester.tap(find.text('Fixed Tags'));
    await tester.pumpAndSettle();
    expect(find.text('private_tag'), findsOneWidget);
    expect(find.text('secret_words'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('two columns align row bottoms and keep an eight-pixel gap', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final picks = DetailTagPicks();
    addTearDown(picks.dispose);
    await _pump(tester, picks, reuse: (_) {});
    final first = find.byKey(const ValueKey('detail-group-positive-0'));
    final fixed = find.byKey(const ValueKey('detail-group-positive-2'));
    final third = find.byKey(const ValueKey('detail-group-positive-3'));
    void checkRows() {
      final a = tester.getRect(first);
      final b = tester.getRect(fixed);
      final c = tester.getRect(third);
      expect(a.top, b.top);
      expect(a.bottom, b.bottom);
      expect(b.left - a.right, closeTo(8, 0.1));
      expect(c.top - a.bottom, closeTo(8, 0.1));
      expect(a.width, b.width);
    }

    checkRows();
    expect(
      find.descendant(of: fixed, matching: find.text('cat')),
      findsNothing,
    );
    await tester.tap(find.text('Section 1'));
    await tester.pumpAndSettle();
    checkRows();
    expect(find.text('dog'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'cards expand, reuse one card, and share tag picks without collisions',
    (tester) async {
      final picks = DetailTagPicks();
      addTearDown(picks.dispose);
      final reused = <String>[];
      await _pump(tester, picks, reuse: (group) => reused.add(group.text));
      await tester.tap(find.byKey(const ValueKey('detail-reuse-group')).at(1));
      expect(reused, ['cat']);
      await tester.tap(find.text('Section 1'));
      await tester.tap(find.text('Saved style'));
      await tester.pumpAndSettle();
      final cats = find.text('cat');
      expect(cats, findsNWidgets(2));
      await tester.longPress(cats.first);
      await tester.pumpAndSettle();
      await tester.tap(cats.last);
      await tester.pumpAndSettle();
      expect(picks.count, 2);
      expect(picks.text, 'cat, cat');
      final card = find.byKey(const ValueKey('detail-group-positive-0'));
      final all = find.descendant(
        of: card,
        matching: find.byTooltip('Select All'),
      );
      await tester.tap(all);
      await tester.pumpAndSettle();
      expect(picks.count, 3);
      await tester.tap(
        find.descendant(of: card, matching: find.byTooltip('Deselect All')),
      );
      await tester.pumpAndSettle();
      expect(picks.count, 1);
      expect(picks.isPicked(DetailTagSide.positive, 2), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [320.0, 600.0, 840.0, 1180.0, 1600.0]) {
    testWidgets('cards and reuse stay reachable at $width and 3x text', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final picks = DetailTagPicks();
      addTearDown(picks.dispose);
      var reused = 0;
      await _pump(tester, picks, scale: 3, reuse: (_) => reused++);
      await tester.tap(find.byKey(const ValueKey('detail-reuse-group')).first);
      expect(reused, 1);
      await tester.tap(find.text('Section 1'));
      await tester.pumpAndSettle();
      expect(find.text('dog'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
