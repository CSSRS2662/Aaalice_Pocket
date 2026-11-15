import 'package:nai_launcher/presentation/widgets/common/image_card_action.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:nai_launcher/data/models/gallery/local_image_record.dart';
import 'package:nai_launcher/data/services/gallery/gallery_filter_service.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/providers/local_gallery_provider.dart';
import 'package:nai_launcher/presentation/providers/selection_mode_provider.dart';
import 'package:nai_launcher/presentation/widgets/gallery/gallery_sidebar.dart';
import 'package:nai_launcher/presentation/widgets/gallery/gallery_library_toolbar.dart';
import 'package:nai_launcher/presentation/widgets/gallery/local_gallery_toolbar.dart';

void _noop() {}

void main() {
  late Directory hiveDir;

  setUpAll(() {
    hiveDir = Directory.systemTemp.createTempSync('local_toolbar_hive_');
    Hive.init(hiveDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    if (hiveDir.existsSync()) hiveDir.deleteSync(recursive: true);
  });

  testWidgets(
    'selection toolbar separates current page and all result actions',
    (tester) async {
      await _pumpToolbar(tester);

      expect(find.byTooltip('选择本页'), findsOneWidget);
      expect(find.byTooltip('选择全部'), findsOneWidget);
      expect(find.byTooltip('全选'), findsNothing);
    },
  );

  testWidgets('remove-from-album action only appears while browsing an album', (
    tester,
  ) async {
    await _pumpToolbar(tester);
    expect(find.byIcon(Icons.playlist_remove), findsNothing);

    await _pumpToolbar(tester, onRemoveFromAlbum: _noop);

    // 宽度不足时批量动作只显示图标；显隐条件是本用例的验证边界，
    // 点击链路与其他批量按钮共用同一机制
    expect(find.byIcon(Icons.playlist_remove), findsOneWidget);
  });

  testWidgets('select current page only selects visible page paths', (
    tester,
  ) async {
    final container = await _pumpToolbar(tester);

    await tester.tap(find.byTooltip('选择本页'));
    await tester.pump();

    expect(container.read(localGallerySelectionNotifierProvider).selectedIds, {
      r'C:\gallery\page-1.png',
      r'C:\gallery\page-2.png',
    });
    expect(find.byTooltip('取消本页'), findsOneWidget);
    expect(find.byTooltip('选择全部'), findsOneWidget);
  });

  testWidgets('normal toolbar wraps actions without overflow at narrow width', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(700, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpToolbar(tester, selectionActive: false);

    expect(find.byType(LocalGalleryToolbar), findsOneWidget);
    expect(find.byType(GalleryLibraryToolbar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'desktop toolbar keeps the page title in the unified 72px surface',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 500));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _pumpToolbar(tester, selectionActive: false);

      const toolbarKey = Key('local-gallery-toolbar');
      expect(
        tester.getSize(find.byKey(toolbarKey)).height,
        GalleryCollectionChrome.toolbarHeight,
      );
      expect(
        find.descendant(
          of: find.byKey(toolbarKey),
          matching: find.text('本地画廊'),
        ),
        findsOneWidget,
      );
    },
  );

  const scopeKeys = [
    'local-gallery-date-chip',
    'local-gallery-collection-chip',
  ];
  const actionKeys = [
    'local-gallery-filter-action',
    'local-gallery-select-action',
    'local-gallery-more-action',
  ];

  for (final scale in [1.0, 3.0]) {
    for (final width in [320.0, 360.0, 600.0, 840.0, 1180.0, 1600.0]) {
      testWidgets(
        'toolbar keeps count, search, scope and actions at ${width.toInt()}px '
        'and ${scale.toInt()}x text',
        (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 900));
          addTearDown(() => tester.binding.setSurfaceSize(null));

          await _pumpToolbar(
            tester,
            selectionActive: false,
            textScaleFactor: scale,
          );

          final compact = scale > 1.5 || width < 1050;
          expect(
            find.byKey(
              ValueKey(
                compact
                    ? 'gallery-library-toolbar-compact'
                    : 'gallery-library-toolbar-desktop',
              ),
            ),
            findsOneWidget,
          );
          expect(find.text('5'), findsOneWidget);
          // 低频操作收进“更多”菜单，不再排成一条可横向滚动的按钮带。
          expect(
            find.byKey(const ValueKey('gallery-library-toolbar-actions')),
            findsNothing,
          );
          expect(find.text('刷新'), findsNothing);
          for (final label in ['日期', '分类']) {
            final labelFinder = find.text(label);
            expect(labelFinder, findsOneWidget, reason: label);
            expect(
              tester
                  .renderObject<RenderParagraph>(labelFinder)
                  .didExceedMaxLines,
              isFalse,
            );
          }
          for (final key in [...scopeKeys, ...actionKeys]) {
            final finder = find.byKey(ValueKey(key));
            await tester.ensureVisible(finder);
            await tester.pumpAndSettle();
            expect(finder.hitTestable(), findsOneWidget, reason: key);
            expect(
              tester.getSize(finder).height,
              greaterThanOrEqualTo(40),
              reason: key,
            );
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('图库只放收藏：没有全部/收藏切换，分类条件照常显示', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpToolbar(tester, selectionActive: false, collectionLabel: '人物');

    expect(find.byKey(const ValueKey('local-gallery-scope-all')), findsNothing);
    expect(
      find.byKey(const ValueKey('local-gallery-scope-favorites')),
      findsNothing,
    );
    expect(find.text('人物'), findsOneWidget);
    // 计数就是收藏数，不再显示“筛选结果/全部”。
    expect(find.text('5'), findsOneWidget);
    expect(find.text('5/5'), findsNothing);
  });

  testWidgets('日期与分类条件显示当前取值，并可单独清除', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final calls = <String>[];

    final container = await _pumpToolbar(
      tester,
      selectionActive: false,
      criteria: FilterCriteria(
        dateStart: DateTime(2026, 9, 1),
        dateEnd: DateTime(2026, 9, 26),
      ),
      collectionLabel: '人物',
      onClearCollection: () => calls.add('clear-collection'),
    );

    expect(find.text('9/1 ~ 9/26'), findsOneWidget);
    expect(find.text('人物'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey('local-gallery-date-clear')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('local-gallery-date-clear')));
    await tester.pump();
    final criteria = container
        .read(localGalleryNotifierProvider)
        .filterCriteria;
    expect(criteria.dateStart, isNull);
    expect(criteria.dateEnd, isNull);
    expect(find.text('日期'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey('local-gallery-collection-clear')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('local-gallery-collection-clear')),
    );
    expect(calls, ['clear-collection']);
  });

  testWidgets('同词在分类右侧，可以切换进出分组浏览', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = await _pumpToolbar(tester, selectionActive: false);
    final chip = find.byKey(const ValueKey('local-gallery-same-prompt-chip'));
    final category = find.byKey(
      const ValueKey('local-gallery-collection-chip'),
    );

    expect(
      tester.getTopLeft(chip).dx,
      greaterThan(tester.getTopRight(category).dx),
    );
    await tester.tap(chip);
    await tester.pump();
    expect(container.read(localGallerySamePromptViewProvider), isTrue);
    await tester.tap(chip);
    await tester.pump();
    expect(container.read(localGallerySamePromptViewProvider), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('更多菜单收纳日期分组、跳转、撤销重做与刷新', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final calls = <String>[];

    final container = await _pumpToolbar(
      tester,
      selectionActive: false,
      canUndo: true,
      onUndo: () => calls.add('undo'),
      onRefresh: () => calls.add('refresh'),
      onJumpToDate: () => calls.add('jump'),
    );

    Future<void> openMenu() async {
      await tester.tap(find.byKey(const ValueKey('local-gallery-more-action')));
      await tester.pumpAndSettle();
    }

    await openMenu();
    for (final label in ['按日期分组', '跳转到日期', '撤销', '重做', '刷新']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    await tester.tap(find.text('刷新'));
    await tester.pumpAndSettle();
    await openMenu();
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    await openMenu();
    await tester.tap(find.text('跳转到日期'));
    await tester.pumpAndSettle();
    expect(calls, ['refresh', 'undo', 'jump']);

    await openMenu();
    await tester.tap(find.text('按日期分组'));
    await tester.pumpAndSettle();
    expect(container.read(localGalleryNotifierProvider).isGroupedView, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('存在模型等高级筛选时筛选按钮切换为选中态', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpToolbar(tester, selectionActive: false);
    final filter = find.byKey(const ValueKey('local-gallery-filter-action'));
    expect(tester.widget<IconButton>(filter).isSelected, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpToolbar(
      tester,
      selectionActive: false,
      criteria: const FilterCriteria(filterModel: 'nai-diffusion-4-5-full'),
    );
    expect(tester.widget<IconButton>(filter).isSelected, isTrue);
  });

  testWidgets('compact action strip shows a forward scroll hint when clipped', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GalleryLibraryToolbar(
            title: const Text('图库'),
            search: const SizedBox(height: 48),
            actions: [
              for (var index = 0; index < 6; index++)
                GalleryLibraryAction(
                  icon: Icons.tune,
                  label: '较长操作 $index',
                  onPressed: _noop,
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('gallery-library-toolbar-scroll-hint')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 360.0, 600.0, 840.0, 1180.0, 1600.0]) {
    testWidgets(
      'batch toolbar remains operable at 3x text and ${width.toInt()}px',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await _pumpToolbar(tester, textScaleFactor: 3);

        expect(find.byIcon(Icons.close), findsOneWidget);
        if (width < 700) {
          expect(find.byIcon(Icons.library_add_check_outlined), findsOneWidget);
          expect(find.byIcon(Icons.more_vert), findsOneWidget);
        } else {
          expect(find.byIcon(Icons.check_box_outlined), findsWidgets);
          expect(find.byIcon(Icons.done_all), findsOneWidget);
          expect(find.byIcon(Icons.drive_file_move_outline), findsOneWidget);
          expect(find.byIcon(Icons.delete_outline), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('select all replaces selection with all filtered result paths', (
    tester,
  ) async {
    final container = await _pumpToolbar(
      tester,
      initialSelectedIds: {r'C:\gallery\stale.png'},
    );

    await tester.tap(find.byTooltip('选择全部'));
    await tester.pumpAndSettle();

    expect(container.read(localGallerySelectionNotifierProvider).selectedIds, {
      r'C:\gallery\page-1.png',
      r'C:\gallery\page-2.png',
      r'C:\gallery\result-3.png',
      r'C:\gallery\result-4.png',
      r'C:\gallery\result-5.png',
    });
    expect(find.byTooltip('取消全部'), findsOneWidget);
  });
}

Future<ProviderContainer> _pumpToolbar(
  WidgetTester tester, {
  Set<String> initialSelectedIds = const {},
  bool selectionActive = true,
  VoidCallback? onRemoveFromAlbum,
  double textScaleFactor = 1,
  bool showPageTitle = true,
  FilterCriteria criteria = LocalGalleryNotifier.favoritesOnly,
  String? collectionLabel,
  bool canUndo = false,
  VoidCallback? onUndo,
  VoidCallback? onRefresh,
  VoidCallback? onJumpToDate,
  VoidCallback? onClearCollection,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localGalleryNotifierProvider.overrideWith(
          () => _ToolbarGalleryNotifier(
            LocalGalleryState(
              currentImages: [
                _record(r'C:\gallery\page-1.png'),
                _record(r'C:\gallery\page-2.png'),
              ],
              filteredCount: 5,
              totalCount: 5,
              totalPages: 3,
              isInitialized: true,
              filterCriteria: criteria,
            ),
            filteredPaths: const [
              r'C:\gallery\page-1.png',
              r'C:\gallery\page-2.png',
              r'C:\gallery\result-3.png',
              r'C:\gallery\result-4.png',
              r'C:\gallery\result-5.png',
            ],
          ),
        ),
        localGallerySelectionNotifierProvider.overrideWith(
          () => _ActiveSelectionNotifier(
            initialSelectedIds,
            isActive: selectionActive,
          ),
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
            ).copyWith(textScaler: TextScaler.linear(textScaleFactor)),
            child: Scaffold(
              body: LocalGalleryToolbar(
                enableSearchAutocomplete: false,
                showPageTitle: showPageTitle,
                onToggleCategoryPanel: _noop,
                collectionLabel: collectionLabel,
                canUndo: canUndo,
                onUndo: onUndo,
                onRefresh: onRefresh,
                onJumpToDate: onJumpToDate,
                onClearCollection: onClearCollection,
                batchActions: [
                  const ImageCardAction(
                    id: ImageCardActionId.classify,
                    icon: Icons.drive_file_move_outline,
                    label: '移动到分类',
                    supportsBatch: true,
                    invoke: _noop,
                  ),
                  const ImageCardAction(
                    id: ImageCardActionId.delete,
                    icon: Icons.delete_outline,
                    label: '删除',
                    supportsBatch: true,
                    isDanger: true,
                    invoke: _noop,
                  ),
                  if (onRemoveFromAlbum != null)
                    ImageCardAction(
                      id: ImageCardActionId.removeFromAlbum,
                      icon: Icons.playlist_remove,
                      label: '移出相簿',
                      supportsBatch: true,
                      invoke: onRemoveFromAlbum,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  return ProviderScope.containerOf(
    tester.element(find.byType(LocalGalleryToolbar)),
  );
}

LocalImageRecord _record(String path) {
  return LocalImageRecord(path: path, size: 1, modifiedAt: DateTime(2026));
}

class _ToolbarGalleryNotifier extends LocalGalleryNotifier {
  _ToolbarGalleryNotifier(this._initialState, {required this.filteredPaths});

  final LocalGalleryState _initialState;
  final List<String> filteredPaths;

  @override
  LocalGalleryState build() => _initialState;

  @override
  Future<List<String>> getFilteredImagePaths() async => filteredPaths;

  @override
  Future<void> setDateRange(DateTime? start, DateTime? end) async {
    state = state.copyWith(
      filterCriteria: FilterCriteria(
        searchQuery: state.filterCriteria.searchQuery,
        dateStart: start,
        dateEnd: end,
      ),
    );
  }

  @override
  Future<void> setGroupedView(bool value) async {
    state = state.copyWith(isGroupedView: value);
  }
}

class _ActiveSelectionNotifier extends LocalGallerySelectionNotifier {
  _ActiveSelectionNotifier(this._initialSelectedIds, {required this.isActive});

  final Set<String> _initialSelectedIds;
  final bool isActive;

  @override
  SelectionModeState build() {
    return SelectionModeState(
      isActive: isActive,
      selectedIds: _initialSelectedIds,
    );
  }
}
