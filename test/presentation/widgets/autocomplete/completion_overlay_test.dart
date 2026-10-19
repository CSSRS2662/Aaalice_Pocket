import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/autocomplete/autocomplete_settings.dart';
import 'package:nai_launcher/core/autocomplete/completion_models.dart';
import 'package:nai_launcher/core/autocomplete/zh_dictionary_service.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/adaptive/interaction_policy.dart';
import 'package:nai_launcher/presentation/widgets/autocomplete/completion_candidate_rows.dart';
import 'package:nai_launcher/presentation/widgets/autocomplete/completion_category_filter.dart';
import 'package:nai_launcher/presentation/widgets/autocomplete/completion_overlay.dart';
import 'package:nai_launcher/presentation/widgets/autocomplete/completion_tile.dart';
import 'package:nai_launcher/presentation/widgets/autocomplete/completion_tile_layout.dart';

const _typedQuery = CompletionQuery(
  fullText: 'blue_',
  cursorPosition: 5,
  token: 'blue_',
  replacementRange: TextReplacementRange(start: 0, end: 5),
  existingTags: {},
  limit: 20,
  locale: 'zh-CN',
);

CompletionCandidate _candidate(
  String tag, {
  TagCategory category = TagCategory.general,
  int postCount = 1200,
  String? translation,
  CompletionMatchKind matchKind = CompletionMatchKind.englishPrefix,
  Set<CompletionSourceKind> sources = const {CompletionSourceKind.base},
  bool isExisting = false,
  bool isTranslating = false,
  double? relatedScore,
  int? cooccurrenceCount,
  String? matchedAlias,
}) => CompletionCandidate(
  canonicalTag: tag,
  category: category,
  postCount: postCount,
  translation: translation,
  matchKind: matchKind,
  sources: sources,
  isExisting: isExisting,
  isTranslating: isTranslating,
  relatedScore: relatedScore,
  cooccurrenceCount: cooccurrenceCount,
  matchedAlias: matchedAlias,
);

Future<CompletionListGeometry> _pumpOverlay(
  WidgetTester tester, {
  required CompletionState state,
  required ScrollController scrollController,
  double width = 760,
  double maxHeight = 360,
  Locale locale = const Locale('zh'),
  InteractionPolicy? policy,
  double textScale = 1,
  AutocompleteSettings settings = const AutocompleteSettings(),
  ZhDictionaryState dictionaryState = const ZhDictionaryState(
    isInstalled: true,
    tagCount: 200000,
  ),
  Map<String, List<int>> tagSections = const {},
  CompletionCategoryFilter? categoryFilter,
  ValueChanged<int>? onSelected,
  VoidCallback? onClose,
  VoidCallback? onOpenSettings,
  bool isRelatedPinned = false,
  VoidCallback? onToggleRelatedPin,
}) async {
  final geometry = CompletionListGeometry();
  final Widget overlay = CompletionOverlay(
    state: state,
    selectedIndex: 0,
    maxHeight: maxHeight,
    scrollController: scrollController,
    settings: settings,
    dictionaryState: dictionaryState,
    showAliases: true,
    showTranslations: true,
    showCategory: true,
    showCount: true,
    onSelected: onSelected ?? (_) {},
    onClose: onClose ?? () {},
    onOpenSettings: onOpenSettings ?? () {},
    measurer: CompletionTileMeasurer(),
    geometry: geometry,
    tagSections: tagSections,
    categoryFilter: categoryFilter,
    isRelatedPinned: isRelatedPinned,
    onToggleRelatedPin: onToggleRelatedPin,
  );
  Widget home = Scaffold(
    body: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: width, child: overlay),
        ),
      ),
    ),
  );
  if (policy != null) {
    home = InteractionPolicyScope(initialPolicy: policy, child: home);
  }
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    ),
  );
  return geometry;
}

Finder _tile(String tag) => find.byKey(ValueKey('autocomplete-candidate-$tag'));

void main() {
  testWidgets('tiles keep every piece of candidate information', (
    tester,
  ) async {
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    var closeCount = 0;
    var settingsCount = 0;

    await _pumpOverlay(
      tester,
      scrollController: scrollController,
      onClose: () => closeCount++,
      onOpenSettings: () => settingsCount++,
      tagSections: const {
        'blue_sky': [2],
      },
      categoryFilter: CompletionCategoryFilter(
        categories: CompletionCategoryFilter.typedCategories,
        chosen: const {},
        onToggleCategory: (_) {},
        onClear: () {},
      ),
      state: CompletionState(
        query: _typedQuery,
        candidates: [
          _candidate(
            'blue_eyes',
            postCount: 125000,
            translation: '蓝色眼睛',
            matchedAlias: 'aqua_eyes',
            sources: const {
              CompletionSourceKind.base,
              CompletionSourceKind.zhDictionary,
            },
          ),
          _candidate(
            'blue_hair_(character)',
            category: TagCategory.character,
            postCount: 50000,
            translation: '蓝发角色',
            sources: const {CompletionSourceKind.danbooruApi},
          ),
          _candidate(
            'bluesy',
            translation: '布鲁斯',
            matchKind: CompletionMatchKind.approximate,
          ),
          _candidate('blue_sky', translation: '蓝天', isExisting: true),
        ],
      ),
    );

    // The header holds the category buttons, not the query being typed.
    expect(
      find.byKey(const ValueKey('autocomplete-popup-categories')),
      findsOne,
    );
    for (final category in CompletionCategoryFilter.typedCategories) {
      expect(
        find.byKey(ValueKey('autocomplete-popup-category-${category.name}')),
        findsOne,
        reason: category.name,
      );
    }
    expect(find.text('blue_'), findsNothing);
    expect(find.text('4'), findsOne);
    expect(find.text('Enter/Tab'), findsOne);

    // Tag over its translation, the count raised after the tag.
    expect(
      tester.getTopLeft(find.text('blue_eyes')).dy,
      lessThan(tester.getTopLeft(find.text('蓝色眼睛')).dy),
    );
    expect(
      find.descendant(of: _tile('blue_eyes'), matching: find.text('125.0K')),
      findsOne,
    );
    expect(find.text('别名：aqua_eyes'), findsNothing);

    // Only uncommon categories carry an icon.
    expect(
      find.byKey(const ValueKey('autocomplete-category-character')),
      findsOne,
    );
    expect(
      find.byKey(const ValueKey('autocomplete-category-general')),
      findsNothing,
    );

    // One dot per source instead of text codes.
    expect(find.text('BASE'), findsNothing);
    for (final source in ['base', 'zhDictionary', 'danbooruApi']) {
      expect(
        find.byKey(ValueKey('autocomplete-source-dot-$source')),
        findsWidgets,
        reason: source,
      );
    }

    // Non-literal match seal and the section badge of a written tag.
    expect(
      find.descendant(of: _tile('bluesy'), matching: find.text('似')),
      findsOne,
    );
    expect(
      find.descendant(
        of: _tile('blue_sky'),
        matching: find.byKey(const ValueKey('autocomplete-candidate-sections')),
      ),
      findsOne,
    );

    // The footer statuses repeat the dot colours as the legend.
    for (final status in ['base', 'dictionary', 'online', 'ai']) {
      expect(
        find.byKey(ValueKey('autocomplete-status-$status-dot')),
        findsOne,
        reason: status,
      );
    }

    await tester.tap(
      find.byKey(const ValueKey('autocomplete-popup-close')),
      warnIfMissed: false,
    );
    await tester.tap(
      find.byKey(const ValueKey('autocomplete-popup-settings')),
      warnIfMissed: false,
    );
    expect(closeCount, 1);
    expect(settingsCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rows wrap in match order and share the spare width', (
    tester,
  ) async {
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    final tags = [
      'seaside',
      'seaside_sukeban_(smg)_(blue_archive)',
      'seaside_town',
      'sky',
      'seashell',
      'sea',
    ];
    final geometry = await _pumpOverlay(
      tester,
      width: 344,
      scrollController: scrollController,
      state: CompletionState(
        query: _typedQuery,
        candidates: [
          for (final tag in tags) _candidate(tag, translation: '翻译'),
        ],
      ),
    );

    final rects = [for (final tag in tags) tester.getRect(_tile(tag))];
    for (var index = 1; index < rects.length; index++) {
      final previous = rects[index - 1];
      final current = rects[index];
      final sameRow = (current.top - previous.top).abs() < 0.5;
      expect(
        sameRow ? current.left > previous.left : current.top > previous.top,
        isTrue,
        reason: tags[index],
      );
    }
    final layout = geometry.layout;
    expect(layout.rows.length, greaterThan(1));
    final list = tester.getRect(
      find.byKey(const ValueKey('autocomplete-popup-list')),
    );
    for (final row in layout.rows.take(layout.rows.length - 1)) {
      final lastTile = tester.getRect(_tile(tags[row.end - 1]));
      // Desktop pointer: the list keeps 12dp clear for its scrollbar.
      expect(lastTile.right, moreOrLessEquals(list.right - 12, epsilon: 1));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('touch keeps 48dp tiles, header buttons and actions at 320px', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    await _pumpOverlay(
      tester,
      width: 320,
      maxHeight: 320,
      scrollController: scrollController,
      policy: const InteractionPolicy(
        modality: InteractionModality.touch,
        touchAvailable: true,
        precisePointerAvailable: true,
      ),
      categoryFilter: CompletionCategoryFilter(
        categories: CompletionCategoryFilter.typedCategories,
        chosen: const {},
        onToggleCategory: (_) {},
        onClear: () {},
      ),
      state: CompletionState(
        query: _typedQuery,
        candidates: [
          _candidate(
            'extremely_long_character_name',
            category: TagCategory.character,
            postCount: 125000,
            translation: '很长的角色中文翻译',
            sources: const {
              CompletionSourceKind.base,
              CompletionSourceKind.zhDictionary,
              CompletionSourceKind.danbooruApi,
            },
          ),
        ],
      ),
    );

    expect(
      tester.getSize(_tile('extremely_long_character_name')).height,
      greaterThanOrEqualTo(48),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('autocomplete-popup-close'))),
      const Size(48, 48),
    );
    final button = tester.getSize(
      find.byKey(const ValueKey('autocomplete-popup-category-general')),
    );
    expect(button.width, greaterThanOrEqualTo(44));
    expect(button.height, greaterThanOrEqualTo(44));
    final surface = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('autocomplete-popup-surface')),
    );
    expect((surface.decoration as BoxDecoration).border, isNotNull);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('mixed input leaves a 600px popup in non-compact layout', (
    tester,
  ) async {
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    await _pumpOverlay(
      tester,
      width: 600,
      maxHeight: 240,
      locale: const Locale('en'),
      scrollController: scrollController,
      policy: const InteractionPolicy(
        modality: InteractionModality.touch,
        touchAvailable: true,
        precisePointerAvailable: true,
      ),
      dictionaryState: const ZhDictionaryState(),
      state: const CompletionState(),
    );

    final surface = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('autocomplete-popup-surface')),
    );
    expect((surface.decoration as BoxDecoration).border, isNull);
    expect(
      tester.getSize(find.byKey(const ValueKey('autocomplete-popup-close'))),
      const Size(48, 48),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a precise pointer drops the touch minimum of tiles', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    late double minHeight;
    await tester.pumpWidget(
      MaterialApp(
        home: InteractionPolicyScope(
          initialPolicy: const InteractionPolicy(
            modality: InteractionModality.pointer,
            touchAvailable: false,
            precisePointerAvailable: true,
          ),
          child: Builder(
            builder: (context) {
              minHeight = CompletionTileMetrics.of(context).minHeight;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    expect(minHeight, 0);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('related mode shows the share, the pin and three categories', (
    tester,
  ) async {
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    var pinCount = 0;
    await _pumpOverlay(
      tester,
      width: 700,
      locale: const Locale('en'),
      scrollController: scrollController,
      dictionaryState: const ZhDictionaryState(),
      isRelatedPinned: true,
      onToggleRelatedPin: () => pinCount++,
      categoryFilter: CompletionCategoryFilter(
        categories: CompletionCategoryFilter.relatedCategories,
        chosen: const {},
        onToggleCategory: (_) {},
        onClear: () {},
      ),
      state: CompletionState(
        query: const CompletionQuery(
          fullText: 'blue_archive, ',
          cursorPosition: 14,
          token: '',
          replacementRange: TextReplacementRange(start: 14, end: 14),
          existingTags: {'blue_archive'},
          limit: 100,
          locale: 'en',
          relatedTag: 'blue_archive',
        ),
        candidates: [
          _candidate(
            'halo',
            postCount: 265497,
            matchKind: CompletionMatchKind.related,
            sources: const {
              CompletionSourceKind.cooccurrence,
              CompletionSourceKind.danbooruApi,
            },
            relatedScore: 0.769,
            cooccurrenceCount: 221957,
          ),
        ],
      ),
    );

    expect(find.text('77%'), findsOneWidget);
    expect(find.text('Related tags'), findsNothing);
    expect(
      find.byKey(const ValueKey('autocomplete-popup-category-character')),
      findsOne,
    );
    expect(
      find.byKey(const ValueKey('autocomplete-popup-category-artist')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('autocomplete-source-dot-cooccurrence')),
      findsOne,
    );
    expect(find.byKey(const ValueKey('autocomplete-status-related')), findsOne);
    final pin = find.byKey(const ValueKey('autocomplete-popup-related-pin'));
    expect(find.byIcon(Icons.push_pin_rounded), findsOneWidget);
    await tester.tap(pin);
    expect(pinCount, 1);
  });

  testWidgets('category buttons count, toggle and clear an empty list', (
    tester,
  ) async {
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    final toggled = <TagCategory>[];
    var cleared = 0;
    CompletionCategoryFilter filter(Set<TagCategory> chosen) =>
        CompletionCategoryFilter(
          categories: CompletionCategoryFilter.typedCategories,
          chosen: chosen,
          counts: const {
            TagCategory.general: 12,
            TagCategory.character: 3,
            TagCategory.artist: 1234,
          },
          onToggleCategory: toggled.add,
          onClear: () => cleared++,
        );

    await _pumpOverlay(
      tester,
      scrollController: scrollController,
      categoryFilter: filter(const {}),
      state: CompletionState(
        query: _typedQuery,
        candidates: [_candidate('blue_eyes', translation: '蓝色眼睛')],
      ),
    );
    final general = find.byKey(
      const ValueKey('autocomplete-popup-category-general'),
    );
    expect(find.descendant(of: general, matching: find.text('12')), findsOne);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('autocomplete-popup-category-artist')),
        matching: find.text('1.2K'),
      ),
      findsOne,
    );
    await tester.tap(
      find.byKey(const ValueKey('autocomplete-popup-category-character')),
    );
    // Nothing to list: copyright cannot be chosen.
    await tester.tap(
      find.byKey(const ValueKey('autocomplete-popup-category-copyright')),
      warnIfMissed: false,
    );
    expect(toggled, [TagCategory.character]);

    await _pumpOverlay(
      tester,
      scrollController: scrollController,
      categoryFilter: filter(const {TagCategory.character}),
      state: const CompletionState(query: _typedQuery),
    );
    expect(find.text('没有符合筛选的标签'), findsOne);
    await tester.tap(
      find.byKey(const ValueKey('autocomplete-related-filter-clear')),
    );
    expect(cleared, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('virtualizes exhaustive result sets while scrolling', (
    tester,
  ) async {
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    final candidates = List.generate(
      1000,
      (index) => _candidate(
        'blue_archive_${index.toString().padLeft(4, '0')}',
        postCount: 1000 - index,
        matchKind: CompletionMatchKind.fullText,
      ),
    );

    await _pumpOverlay(
      tester,
      width: 700,
      locale: const Locale('en'),
      scrollController: scrollController,
      dictionaryState: const ZhDictionaryState(),
      state: CompletionState(candidates: candidates),
    );

    expect(find.text('blue_archive_0000'), findsOneWidget);
    expect(find.text('blue_archive_0999'), findsNothing);
    expect(find.text('Not translated'), findsWidgets);
    expect(
      find.byKey(const ValueKey('autocomplete-popup-result-count')),
      findsOneWidget,
    );

    scrollController.jumpTo(1);
    await tester.pump();
    scrollController.jumpTo(0);
    await tester.pump(const Duration(milliseconds: 200));
    final scrollbar = find.byKey(
      const ValueKey('autocomplete-popup-scrollbar'),
    );
    final rawScrollbar = find.descendant(
      of: scrollbar,
      matching: find.byWidgetPredicate((widget) => widget is RawScrollbar),
    );
    expect(rawScrollbar, findsOneWidget);
    // Tiles stay clear of the desktop scrollbar.
    final listRect = tester.getRect(
      find.byKey(const ValueKey('autocomplete-popup-list')),
    );
    final tiles = find.byType(CompletionTile);
    expect(tiles, findsWidgets);
    for (final element in tiles.evaluate()) {
      final box = element.renderObject! as RenderBox;
      final right = box.localToGlobal(Offset(box.size.width, 0)).dx;
      expect(right, lessThanOrEqualTo(listRect.right - 11.5));
    }

    final scrollbarState = tester.state(rawScrollbar);
    final dynamic painter = (scrollbarState as dynamic).scrollbarPainter;
    final scrollbarSize = tester.getSize(rawScrollbar);
    Offset? localThumbPoint;
    for (var y = 1.0; y < scrollbarSize.height; y++) {
      for (var x = scrollbarSize.width - 1; x >= 0; x--) {
        final point = Offset(x, y);
        if (painter.hitTestOnlyThumbInteractive(point, PointerDeviceKind.mouse)
            as bool) {
          localThumbPoint = point;
          break;
        }
      }
      if (localThumbPoint != null) break;
    }
    expect(localThumbPoint, isNotNull);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    final thumbStart = tester.getTopLeft(rawScrollbar) + localThumbPoint!;
    await mouse.moveTo(thumbStart);
    await mouse.down(thumbStart);
    await tester.pump();
    await mouse.moveTo(thumbStart + const Offset(0, 120));
    await tester.pump();
    await mouse.up();
    await tester.pump();
    expect(scrollController.offset, greaterThan(0));

    scrollController.jumpTo(scrollController.position.maxScrollExtent);
    await tester.pump();
    expect(find.text('blue_archive_0000'), findsNothing);
    expect(find.text('blue_archive_0999'), findsOneWidget);
  });

  for (final (width, scale) in [(300.0, 2.0), (320.0, 3.0), (600.0, 3.0)]) {
    testWidgets('fits ${width.toInt()}px at ${scale}x text without overflow', (
      tester,
    ) async {
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);
      final tags = [
        'extremely_long_completion_candidate_name_(with_a_long_series)',
        'solo',
        'blue_eyes',
      ];
      await _pumpOverlay(
        tester,
        width: width,
        textScale: scale,
        scrollController: scrollController,
        policy: const InteractionPolicy(
          modality: InteractionModality.touch,
          touchAvailable: true,
          precisePointerAvailable: false,
        ),
        categoryFilter: CompletionCategoryFilter(
          categories: CompletionCategoryFilter.typedCategories,
          chosen: const {},
          onToggleCategory: (_) {},
          onClear: () {},
        ),
        state: CompletionState(
          query: _typedQuery,
          candidates: [
            for (final tag in tags)
              _candidate(
                tag,
                postCount: 125000,
                translation: '很长的候选标签翻译文本',
                matchKind: CompletionMatchKind.pinyin,
                sources: const {
                  CompletionSourceKind.base,
                  CompletionSourceKind.zhDictionary,
                },
              ),
          ],
        ),
      );

      final surface = tester.getRect(
        find.byKey(const ValueKey('autocomplete-popup-surface')),
      );
      expect(surface.width, lessThanOrEqualTo(width));
      final list = find.descendant(
        of: find.byKey(const ValueKey('autocomplete-popup-list')),
        matching: find.byType(Scrollable),
      );
      for (final tag in tags) {
        await tester.scrollUntilVisible(
          find.text(tag),
          300,
          scrollable: list,
          maxScrolls: 200,
        );
        await tester.pump();
        final rect = tester.getRect(_tile(tag));
        expect(rect.left, greaterThanOrEqualTo(surface.left - 0.5));
        expect(rect.right, lessThanOrEqualTo(surface.right + 0.5));
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('shows live loading and failure states without hiding results', (
    tester,
  ) async {
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    await _pumpOverlay(
      tester,
      width: 620,
      locale: const Locale('en'),
      scrollController: scrollController,
      settings: const AutocompleteSettings(llmTranslationEnabled: true),
      dictionaryState: const ZhDictionaryState(isBusy: true, progress: 0.42),
      state: CompletionState(
        candidates: [
          _candidate(
            'solo',
            postCount: 100,
            matchKind: CompletionMatchKind.englishExact,
            isTranslating: true,
          ),
        ],
        isRemoteLoading: true,
      ),
    );

    expect(
      find.textContaining('Downloading 42%', findRichText: true),
      findsOne,
    );
    expect(find.textContaining('Searching', findRichText: true), findsOne);
    expect(
      find.textContaining('Translating', findRichText: true),
      findsWidgets,
    );
    expect(find.text('solo'), findsOne);
  });
}
