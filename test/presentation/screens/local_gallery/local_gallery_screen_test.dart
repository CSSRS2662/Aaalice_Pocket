import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/presentation/providers/bulk_operation_provider.dart';
import 'package:nai_launcher/presentation/providers/gallery_category_provider.dart';
import 'package:nai_launcher/presentation/providers/local_gallery_provider.dart';
import 'package:nai_launcher/presentation/screens/local_gallery/local_gallery_view_model.dart';

void main() {
  LocalGalleryViewModel buildViewModel(
    double width, {
    bool categoryPanelRequested = true,
    int preferredColumns = 2,
  }) {
    return LocalGalleryViewModel.fromStates(
      preferredColumns: preferredColumns,
      gallery: const LocalGalleryState(),
      bulkOperation: const BulkOperationState(),
      categories: const GalleryCategoryState(),
      isSelectionMode: false,
      categoryPanelRequested: categoryPanelRequested,
      isPackingImages: false,
      maxWidth: width,
    );
  }

  test('999px keeps categories in the adaptive sheet', () {
    final viewModel = buildViewModel(999);

    expect(viewModel.usePersistentCategories, isFalse);
    expect(viewModel.showPersistentCategories, isFalse);
    expect(viewModel.contentWidth, 999);
  });

  test('1000px shows the persistent category panel', () {
    final viewModel = buildViewModel(1000);

    expect(viewModel.usePersistentCategories, isTrue);
    expect(viewModel.showPersistentCategories, isTrue);
    expect(viewModel.contentWidth, 750);
  });

  test('本地画廊默认两列：手机严格两列，更宽时保持卡片大小增加列数', () {
    const cases =
        <
          ({
            double width,
            int openedColumns,
            double openedItemWidth,
            int closedColumns,
            double closedItemWidth,
          })
        >[
          (
            width: 320,
            openedColumns: 2,
            openedItemWidth: 142,
            closedColumns: 2,
            closedItemWidth: 142,
          ),
          (
            width: 360,
            openedColumns: 2,
            openedItemWidth: 162,
            closedColumns: 2,
            closedItemWidth: 162,
          ),
          (
            width: 412,
            openedColumns: 2,
            openedItemWidth: 188,
            closedColumns: 2,
            closedItemWidth: 188,
          ),
          (
            width: 600,
            openedColumns: 3,
            openedItemWidth: 184,
            closedColumns: 3,
            closedItemWidth: 184,
          ),
          (
            width: 840,
            openedColumns: 4,
            openedItemWidth: 195,
            closedColumns: 4,
            closedItemWidth: 195,
          ),
          (
            width: 1000,
            openedColumns: 3,
            openedItemWidth: 234,
            closedColumns: 4,
            closedItemWidth: 235,
          ),
          (
            width: 1180,
            openedColumns: 4,
            openedItemWidth: 217.5,
            closedColumns: 5,
            closedItemWidth: 221.6,
          ),
          (
            width: 1600,
            openedColumns: 6,
            openedItemWidth: 211,
            closedColumns: 7,
            closedItemWidth: 214.85714285714286,
          ),
        ];

    for (final testCase in cases) {
      final opened = buildViewModel(testCase.width);
      final closed = buildViewModel(
        testCase.width,
        categoryPanelRequested: false,
      );
      final openedContentWidth =
          testCase.width - (testCase.width >= 1000 ? 250 : 0);

      expect(opened.contentWidth, openedContentWidth);
      expect(closed.contentWidth, testCase.width);
      expect(
        opened.columns,
        testCase.openedColumns,
        reason: '${testCase.width}px 分类面板展开列数',
      );
      expect(
        opened.itemWidth,
        closeTo(testCase.openedItemWidth, 0.000001),
        reason: '${testCase.width}px 分类面板展开 itemWidth',
      );
      expect(
        closed.columns,
        testCase.closedColumns,
        reason: '${testCase.width}px 分类面板关闭列数',
      );
      expect(
        closed.itemWidth,
        closeTo(testCase.closedItemWidth, 0.000001),
        reason: '${testCase.width}px 分类面板关闭 itemWidth',
      );
      expect(
        opened.itemWidth * opened.columns + 12 * (opened.columns - 1),
        closeTo(openedContentWidth - 24, 0.000001),
        reason: '${testCase.width}px 分类面板展开可用宽度',
      );
      expect(
        closed.itemWidth * closed.columns + 12 * (closed.columns - 1),
        closeTo(testCase.width - 24, 0.000001),
        reason: '${testCase.width}px 分类面板关闭可用宽度',
      );
    }
  });

  test('手机宽度严格使用所选的 2 到 4 列', () {
    for (final width in [320.0, 360.0, 412.0]) {
      expect(
        [
          for (final n in [2, 3, 4])
            buildViewModel(width, preferredColumns: n).columns,
        ],
        [2, 3, 4],
        reason: '${width}px',
      );
    }
    expect(buildViewModel(1600, preferredColumns: 4).itemWidth, lessThan(121));
  });
}
