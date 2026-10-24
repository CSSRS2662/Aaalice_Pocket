import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/platform/platform_capabilities.dart';
import 'package:nai_launcher/core/storage/local_storage_service.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/adaptive/interaction_policy.dart';
import 'package:nai_launcher/presentation/providers/tag_library_page_provider.dart';
import 'package:nai_launcher/presentation/screens/tag_library_page/widgets/tag_library_toolbar.dart';
import 'package:nai_launcher/presentation/widgets/gallery/gallery_library_toolbar.dart';

import '../../../../helpers/light_theme_contrast.dart';

class _FakeTagLibraryPageNotifier extends TagLibraryPageNotifier {
  @override
  TagLibraryPageState build() =>
      const TagLibraryPageState(sortBy: TagLibrarySortBy.frequent);
}

void main() {
  tearDown(() => PlatformCapabilities.debugOverride = null);

  for (final width in [320.0, 600.0, 840.0, 1180.0, 1600.0]) {
    testWidgets('宽屏词库顶栏保留全部能力 ${width.toInt()}px', (tester) async {
      PlatformCapabilities.debugOverride = PlatformCapabilities.forPlatform(
        TargetPlatform.windows,
      );
      await _pumpToolbar(tester, width: width);

      expect(find.byType(GalleryLibraryToolbar), findsOneWidget);
      expect(find.byType(GalleryLibrarySearchField), findsOneWidget);
      // The sort button names the current order.
      expect(find.text('常用'), findsOneWidget);
      for (final label in ['分组', '管理分组', '多选', '导入', '导出', '文件夹', '添加条目']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('排序、分组管理、分组栏与文件夹按钮转发顶栏操作', (tester) async {
    final calls = <String>[];
    await _pumpToolbar(
      tester,
      width: 1180,
      onShowCategories: () => calls.add('categories'),
      onOpenFolder: () => calls.add('folder'),
      onSort: () => calls.add('sort'),
      onManageGroups: () => calls.add('groups'),
    );

    await tester.tap(find.byKey(const Key('tag-library-categories-button')));
    await tester.tap(find.byKey(const Key('tag-library-folder-button')));
    await tester.tap(find.byKey(const Key('tag-library-sort-button')));
    await tester.tap(find.byKey(const Key('tag-library-manage-groups-button')));

    expect(calls, ['categories', 'folder', 'sort', 'groups']);
  });

  testWidgets('3x 文本保留完整可横向滚动操作区', (tester) async {
    PlatformCapabilities.debugOverride = PlatformCapabilities.forPlatform(
      TargetPlatform.windows,
    );
    await _pumpToolbar(tester, width: 320, textScale: 3);

    expect(
      find.byKey(const ValueKey('gallery-library-toolbar-compact')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('gallery-library-toolbar-actions')),
      findsOneWidget,
    );
    for (final label in ['分组', '管理分组', '多选', '导入', '导出', '文件夹', '添加条目']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpToolbar(
  WidgetTester tester, {
  required double width,
  double textScale = 1,
  VoidCallback? onShowCategories,
  VoidCallback? onOpenFolder,
  VoidCallback? onSort,
  VoidCallback? onManageGroups,
  InteractionPolicy? interactionPolicy,
  LocalStorageService? storage,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageServiceProvider.overrideWith(
          (ref) => storage ?? InMemoryLocalStorageService(),
        ),
        tagLibraryPageNotifierProvider.overrideWith(
          _FakeTagLibraryPageNotifier.new,
        ),
      ],
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: InteractionPolicyScope(
              initialPolicy: interactionPolicy,
              child: Scaffold(
                body: TagLibraryToolbar(
                  onShowCategories: onShowCategories ?? () {},
                  onOpenFolder: onOpenFolder ?? () {},
                  onEnterSelectionMode: () {},
                  onImport: () {},
                  onExport: () {},
                  onAddEntry: () {},
                  onSort: onSort ?? () {},
                  onManageGroups: onManageGroups ?? () {},
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
