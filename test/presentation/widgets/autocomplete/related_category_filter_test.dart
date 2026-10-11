import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/autocomplete/autocomplete_settings.dart';
import 'package:nai_launcher/core/autocomplete/completion_models.dart';
import 'package:nai_launcher/core/autocomplete/zh_dictionary_service.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/adaptive/interaction_policy.dart';
import 'package:nai_launcher/presentation/widgets/autocomplete/completion_overlay.dart';
import 'package:nai_launcher/presentation/widgets/autocomplete/related_category_filter.dart';

const _funnel = ValueKey('autocomplete-popup-related-filter');
const _panel = ValueKey('autocomplete-related-filter-panel');
const _character = ValueKey('autocomplete-related-filter-character');
const _series = ValueKey('autocomplete-related-filter-copyright');
const _general = ValueKey('autocomplete-related-filter-general');
const _clear = ValueKey('autocomplete-related-filter-clear');

const _relatedQuery = CompletionQuery(
  fullText: 'blue_archive, ',
  cursorPosition: 14,
  token: '',
  replacementRange: TextReplacementRange(start: 14, end: 14),
  existingTags: {'blue_archive'},
  limit: 100,
  locale: 'zh-CN',
  relatedTag: 'blue_archive',
);

CompletionCandidate _row(String tag, TagCategory category) =>
    CompletionCandidate(
      canonicalTag: tag,
      category: category,
      postCount: 1000,
      matchKind: CompletionMatchKind.related,
      sources: const {CompletionSourceKind.cooccurrence},
      relatedScore: 0.5,
      cooccurrenceCount: 500,
    );

Future<void> _pumpPopup(
  WidgetTester tester, {
  required RelatedCategoryFilter filter,
  required ScrollController scrollController,
  List<CompletionCandidate>? candidates,
  CompletionQuery query = _relatedQuery,
  double width = 388,
  double maxHeight = 250,
  double textScale = 1,
  bool touch = true,
}) {
  return tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: InteractionPolicyScope(
        initialPolicy: InteractionPolicy(
          modality: touch
              ? InteractionModality.touch
              : InteractionModality.pointer,
          touchAvailable: touch,
          precisePointerAvailable: !touch,
        ),
        child: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 700),
              textScaler: TextScaler.linear(textScale),
            ),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: CompletionOverlay(
                  state: CompletionState(
                    query: query,
                    candidates:
                        candidates ??
                        [
                          _row('halo', TagCategory.general),
                          _row('yuuka_(blue_archive)', TagCategory.character),
                          _row('hina_(blue_archive)', TagCategory.character),
                          _row('long_hair', TagCategory.general),
                          _row('blush', TagCategory.general),
                        ],
                  ),
                  selectedIndex: 0,
                  maxHeight: maxHeight,
                  scrollController: scrollController,
                  settings: const AutocompleteSettings(),
                  dictionaryState: const ZhDictionaryState(),
                  showAliases: true,
                  showTranslations: true,
                  showCategory: true,
                  showCount: true,
                  onSelected: (_) {},
                  onClose: () {},
                  onOpenSettings: () {},
                  onToggleRelatedPin: () {},
                  relatedFilter: filter,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('the funnel opens the cards, shows what is chosen and clears', (
    tester,
  ) async {
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    final toggled = <TagCategory>[];
    var panelToggles = 0;
    var clears = 0;
    RelatedCategoryFilter filter({
      Set<TagCategory> chosen = const {},
      bool open = false,
    }) => RelatedCategoryFilter(
      chosen: chosen,
      open: open,
      counts: const {
        TagCategory.character: 276,
        TagCategory.copyright: 7,
        TagCategory.general: 2463,
      },
      onTogglePanel: () => panelToggles++,
      onToggleCategory: toggled.add,
      onClear: () => clears++,
    );

    await _pumpPopup(
      tester,
      filter: filter(),
      scrollController: scrollController,
    );
    expect(find.byKey(_panel), findsNothing);
    expect(find.byIcon(Icons.filter_alt_outlined), findsOneWidget);
    // Nothing is chosen, so a long press has nothing to clear; it does not
    // count as a tap either.
    await tester.longPress(find.byKey(_funnel));
    expect(clears, 0);
    expect(panelToggles, 0);
    await tester.tap(find.byKey(_funnel));
    expect(panelToggles, 1);

    await _pumpPopup(
      tester,
      filter: filter(chosen: {TagCategory.character}, open: true),
      scrollController: scrollController,
    );
    expect(find.byIcon(Icons.filter_alt_rounded), findsOneWidget);
    final panel = find.byKey(_panel);
    for (final text in ['角色', '作品', '一般', '276', '7', '2463']) {
      expect(find.descendant(of: panel, matching: find.text(text)), findsOne);
    }
    // Only the chosen card carries the check mark.
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(_character),
        matching: find.byIcon(Icons.check_rounded),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(_series));
    await tester.tap(find.byKey(_general));
    expect(toggled, [TagCategory.copyright, TagCategory.general]);

    await tester.longPress(find.byKey(_funnel));
    expect(clears, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the cards float inside the popup, under its header', (
    tester,
  ) async {
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    RelatedCategoryFilter open() => RelatedCategoryFilter(
      chosen: const {},
      open: true,
      counts: const {TagCategory.character: 13},
      onTogglePanel: () {},
      onToggleCategory: (_) {},
      onClear: () {},
    );

    // Keyboard up on a phone, a roomy popup, a narrow one with huge text
    // and one with a single short row.
    for (final (width, maxHeight, textScale, rows) in [
      (388.0, 250.0, 1.0, 5),
      (388.0, 320.0, 1.0, 5),
      (320.0, 250.0, 3.0, 5),
      (388.0, 250.0, 1.0, 1),
      (320.0, 150.0, 2.0, 0),
    ]) {
      await _pumpPopup(
        tester,
        filter: open(),
        scrollController: scrollController,
        width: width,
        maxHeight: maxHeight,
        textScale: textScale,
        candidates: [
          for (var index = 0; index < rows; index++)
            _row('tag_$index', TagCategory.general),
        ],
      );
      final reason = '$width x $maxHeight at ${textScale}x, $rows rows';
      expect(tester.takeException(), isNull, reason: reason);
      final popup = tester.getRect(
        find.byKey(const ValueKey('autocomplete-popup-surface')),
      );
      final header = tester.getRect(
        find.byKey(const ValueKey('autocomplete-popup-header')),
      );
      final panel = tester.getRect(find.byKey(_panel));
      expect(panel.top, greaterThanOrEqualTo(header.bottom), reason: reason);
      expect(panel.bottom, lessThanOrEqualTo(popup.bottom), reason: reason);
      expect(panel.left, greaterThanOrEqualTo(popup.left), reason: reason);
      expect(panel.right, lessThanOrEqualTo(popup.right), reason: reason);
      for (final card in [_character, _series, _general]) {
        expect(find.byKey(card).hitTestable(), findsOneWidget, reason: reason);
      }
    }
  });

  testWidgets('browsing the list puts the cards away', (tester) async {
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    var panelToggles = 0;
    await _pumpPopup(
      tester,
      filter: RelatedCategoryFilter(
        chosen: const {TagCategory.character},
        open: true,
        onTogglePanel: () => panelToggles++,
        onToggleCategory: (_) {},
        onClear: () {},
      ),
      scrollController: scrollController,
    );
    final list = tester.getRect(
      find.byKey(const ValueKey('autocomplete-popup-list')),
    );
    // Left of the cards, where the rows show.
    await tester.dragFrom(
      Offset(list.left + 24, list.bottom - 12),
      const Offset(0, -60),
    );
    await tester.pump();
    expect(scrollController.offset, greaterThan(0));
    expect(panelToggles, 1);
  });

  testWidgets('a popup too short to float the cards lists them in a row', (
    tester,
  ) async {
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    final toggled = <TagCategory>[];
    await _pumpPopup(
      tester,
      filter: RelatedCategoryFilter(
        chosen: const {},
        open: true,
        counts: const {TagCategory.character: 13},
        onTogglePanel: () {},
        onToggleCategory: toggled.add,
        onClear: () {},
      ),
      scrollController: scrollController,
      width: 320,
      maxHeight: 96,
    );
    expect(tester.takeException(), isNull);
    // The header and the cards follow the rows in the same scroll.
    scrollController.jumpTo(scrollController.position.maxScrollExtent);
    await tester.pump();
    await tester.tap(find.byKey(_character));
    expect(toggled, [TagCategory.character]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty category cannot be chosen without online rows', (
    tester,
  ) async {
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    final toggled = <TagCategory>[];
    RelatedCategoryFilter filter({required bool online}) =>
        RelatedCategoryFilter(
          chosen: const {},
          open: true,
          counts: const {
            TagCategory.character: 0,
            TagCategory.copyright: 0,
            TagCategory.general: 133,
          },
          listsOnlineRows: online,
          onTogglePanel: () {},
          onToggleCategory: toggled.add,
          onClear: () {},
        );

    await _pumpPopup(
      tester,
      filter: filter(online: false),
      scrollController: scrollController,
    );
    await tester.tap(find.byKey(_character));
    await tester.tap(find.byKey(_general));
    expect(toggled, [TagCategory.general]);

    // Online related tags may still hold some.
    await _pumpPopup(
      tester,
      filter: filter(online: true),
      scrollController: scrollController,
    );
    await tester.tap(find.byKey(_character));
    expect(toggled, [TagCategory.general, TagCategory.character]);
  });

  testWidgets('a narrowed list that comes back empty offers to clear', (
    tester,
  ) async {
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    var clears = 0;
    RelatedCategoryFilter filter({required bool open}) => RelatedCategoryFilter(
      chosen: const {TagCategory.character},
      open: open,
      onTogglePanel: () {},
      onToggleCategory: (_) {},
      onClear: () => clears++,
    );

    await _pumpPopup(
      tester,
      filter: filter(open: false),
      scrollController: scrollController,
      candidates: const [],
    );
    expect(find.text('没有符合筛选的相关标签'), findsOneWidget);
    await tester.tap(find.byKey(_clear));
    expect(clears, 1);

    // The open cards leave the message and the button in view.
    await _pumpPopup(
      tester,
      filter: filter(open: true),
      scrollController: scrollController,
      candidates: const [],
      maxHeight: 320,
    );
    final panel = tester.getRect(find.byKey(_panel));
    expect(
      tester.getRect(find.text('没有符合筛选的相关标签')).top,
      greaterThanOrEqualTo(panel.bottom),
    );
    expect(find.byKey(_clear).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('typed completion has no funnel', (tester) async {
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    await _pumpPopup(
      tester,
      filter: RelatedCategoryFilter(
        chosen: const {},
        open: true,
        onTogglePanel: () {},
        onToggleCategory: (_) {},
        onClear: () {},
      ),
      scrollController: scrollController,
      query: const CompletionQuery(
        fullText: 'blu',
        cursorPosition: 3,
        token: 'blu',
        replacementRange: TextReplacementRange(start: 0, end: 3),
        existingTags: {},
        limit: 100,
        locale: 'zh-CN',
      ),
      touch: false,
    );
    expect(find.byKey(_funnel), findsNothing);
    expect(find.byKey(_panel), findsNothing);
  });
}
