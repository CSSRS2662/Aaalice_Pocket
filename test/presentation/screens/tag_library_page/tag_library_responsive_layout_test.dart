import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/platform/platform_capabilities.dart';
import 'package:nai_launcher/core/shortcuts/shortcut_config.dart';
import 'package:nai_launcher/core/storage/local_storage_service.dart';
import 'package:nai_launcher/data/models/tag_library/tag_library_category.dart';
import 'package:nai_launcher/data/models/tag_library/tag_library_entry.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/adaptive/interaction_policy.dart';
import 'package:nai_launcher/presentation/providers/shortcuts_provider.dart';
import 'package:nai_launcher/presentation/providers/tag_library_page_provider.dart';
import 'package:nai_launcher/presentation/providers/tag_library_selection_provider.dart';
import 'package:nai_launcher/presentation/screens/tag_library_page/tag_library_page_screen.dart';
import 'package:nai_launcher/presentation/screens/tag_library_page/widgets/tag_library_grid_layout.dart';
import 'package:nai_launcher/presentation/widgets/common/input_surface_container.dart';
import 'package:nai_launcher/presentation/widgets/gallery/gallery_sidebar.dart';

import '../../../helpers/light_theme_contrast.dart';

void main() {
  setUp(() {
    PlatformCapabilities.debugOverride = PlatformCapabilities.forPlatform(
      TargetPlatform.android,
    );
  });
  tearDown(() => PlatformCapabilities.debugOverride = null);

  test('phones get two columns, wide panes more, 3x text one', () {
    final phone = computeTagLibraryGridLayout(411, 1, cardExtent: 62);
    final large = computeTagLibraryGridLayout(320, 3, cardExtent: 120);
    final wide = computeTagLibraryGridLayout(1180, 1, cardExtent: 62);

    expect(phone.columns, 2);
    expect(large.columns, 1);
    expect(wide.columns, greaterThan(2));
    expect(large.mainAxisExtent, 120);
    expect(phone.padding, 12);
    expect(wide.padding, 16);
  });

  for (final width in [320.0, 600.0, 840.0, 1180.0, 1600.0]) {
    testWidgets(
      'library keeps search, groups and selection reachable at ${width.toInt()}px',
      (tester) async {
        await _setViewport(tester, Size(width, 800));
        await _pumpLibrary(tester);

        expect(find.byKey(const ValueKey('tag-library-sections')), findsOne);
        expect(find.text('目标条目'), findsOneWidget);
        expect(find.byType(TextField), findsOneWidget);
        expect(
          find.byKey(const Key('tag-library-add-entry-button')),
          findsOneWidget,
        );
        if (width < 840) {
          final searchRect = tester.getRect(find.byType(TextField));
          final addRect = tester.getRect(
            find.byKey(const Key('tag-library-add-entry-button')),
          );
          expect(addRect.left, greaterThan(searchRect.left));
          expect(addRect.center.dy, closeTo(searchRect.center.dy, 1));
          expect(find.byKey(const ValueKey('tag-library-chip-all')), findsOne);
          expect(
            find.byKey(const ValueKey('tag-library-chip-scene')),
            findsOne,
          );
        } else {
          expect(
            find.descendant(
              of: find.byKey(const Key('tag-library-toolbar')),
              matching: find.text('词库'),
            ),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('tag-library-category-sidebar')),
            findsOne,
          );
        }
        if (width == 1600) {
          expect(
            tester.getSize(find.byKey(const Key('tag-library-toolbar'))).height,
            GalleryCollectionChrome.toolbarHeight,
          );
          final addRect = tester.getRect(
            find.byKey(const Key('tag-library-add-entry-button')),
          );
          final toolbarRect = tester.getRect(
            find.byKey(const Key('tag-library-toolbar')),
          );
          expect(toolbarRect.right - addRect.right, 16);
        }

        await tester.enterText(find.byType(TextField), '目标');
        await tester.pump();
        expect(find.text('目标条目'), findsOneWidget);
        expect(find.text('其他条目'), findsNothing);
        await tester.enterText(find.byType(TextField), '');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();

        await tester.longPress(
          find.byKey(const ValueKey('tag-library-entry-target-entry')),
        );
        await tester.pump();
        final container = ProviderScope.containerOf(
          tester.element(find.byType(TagLibraryPageScreen)),
        );
        expect(
          container.read(tagLibrarySelectionNotifierProvider).selectedIds,
          contains('target-entry'),
        );
        if (width < 840) {
          expect(
            find.byKey(const ValueKey('tag-library-selection-bar')),
            findsOne,
          );
          expect(
            find.byKey(const ValueKey('tag-library-selection-header')),
            findsOne,
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('choosing a group chip shows its sections only', (tester) async {
    await _setViewport(tester, const Size(390, 800));
    await _pumpLibrary(tester);

    final chip = find.byKey(const ValueKey('tag-library-chip-scene'));
    await tester.ensureVisible(chip);
    await tester.pump();
    await tester.tap(chip);
    await tester.pump();

    expect(find.text('其他条目'), findsOneWidget);
    expect(find.text('目标条目'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'mixed touch and precise-pointer policy keeps touch-sized search',
    (tester) async {
      PlatformCapabilities.debugOverride = PlatformCapabilities.forPlatform(
        TargetPlatform.windows,
      );
      await _setViewport(tester, const Size(840, 800));
      await _pumpLibrary(
        tester,
        interactionPolicy: const InteractionPolicy(
          modality: InteractionModality.pointer,
          touchAvailable: true,
          precisePointerAvailable: true,
        ),
      );

      expect(
        tester.getSize(find.byType(InputSurfaceContainer).first).height,
        48,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '320px 3x text with SafeArea and IME preserves search input and groups',
    (tester) async {
      await _setViewport(
        tester,
        const Size(320, 720),
        padding: const FakeViewPadding(top: 24, bottom: 24),
        viewInsets: const FakeViewPadding(bottom: 240),
      );
      await _pumpLibrary(tester, textScale: 3);

      final search = find.byType(TextField);
      expect(search, findsOneWidget);
      await tester.tap(search);
      await tester.enterText(search, '目标');
      await tester.pump();

      expect(find.byKey(const ValueKey('tag-library-chip-all')), findsOne);
      expect(find.byKey(const ValueKey('tag-library-sort-button')), findsOne);
      expect(find.text('目标条目'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _setViewport(
  WidgetTester tester,
  Size size, {
  FakeViewPadding? padding,
  FakeViewPadding? viewInsets,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = padding ?? const FakeViewPadding();
  tester.view.viewInsets = viewInsets ?? const FakeViewPadding();
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPadding();
    tester.view.resetViewInsets();
  });
}

Future<void> _pumpLibrary(
  WidgetTester tester, {
  double textScale = 1,
  InteractionPolicy? interactionPolicy,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageServiceProvider.overrideWith(
          (ref) => InMemoryLocalStorageService(),
        ),
        tagLibraryPageNotifierProvider.overrideWith(
          _PopulatedTagLibraryNotifier.new,
        ),
        shortcutConfigNotifierProvider.overrideWith(
          _ShortcutConfigNotifier.new,
        ),
      ],
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: InteractionPolicyScope(
          initialPolicy:
              interactionPolicy ??
              const InteractionPolicy(
                modality: InteractionModality.touch,
                touchAvailable: true,
                precisePointerAvailable: false,
              ),
          child: const TagLibraryPageScreen(),
        ),
      ),
    ),
  );
  await tester.pump();
}

class _PopulatedTagLibraryNotifier extends TagLibraryPageNotifier {
  @override
  TagLibraryPageState build() => TagLibraryPageState(
    categories: [
      TagLibraryCategory(id: 'person', name: '人物', createdAt: DateTime(2026)),
      TagLibraryCategory(
        id: 'scene',
        name: '场景',
        sortOrder: 1,
        createdAt: DateTime(2026),
      ),
    ],
    entries: [
      TagLibraryEntry(
        id: 'target-entry',
        name: '目标条目',
        content: 'target tag, detailed prompt',
        categoryId: 'person',
        isFavorite: true,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
      TagLibraryEntry(
        id: 'other-entry',
        name: '其他条目',
        content: 'landscape, sunset',
        categoryId: 'scene',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    ],
  );
}

class _ShortcutConfigNotifier extends ShortcutConfigNotifier {
  @override
  Future<ShortcutConfig> build() async => ShortcutConfig.createDefault();
}
