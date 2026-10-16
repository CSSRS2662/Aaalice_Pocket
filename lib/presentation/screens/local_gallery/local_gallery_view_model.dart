import 'package:flutter/foundation.dart';

import '../../providers/bulk_operation_provider.dart';
import '../../providers/gallery_category_provider.dart';
import '../../providers/local_gallery_provider.dart';
import '../../widgets/common/grid_column_count.dart';

/// Immutable snapshot consumed by the local gallery screen shell.
///
/// Gallery files, filters, paging, selection, and categories remain owned by
/// their Riverpod providers; this object only derives presentation geometry.
@immutable
class LocalGalleryViewModel {
  const LocalGalleryViewModel({
    required this.gallery,
    required this.bulkOperation,
    required this.categories,
    required this.isSelectionMode,
    required this.showCategoryPanel,
    required this.isPackingImages,
    required this.usePersistentCategories,
    required this.showPersistentCategories,
    required this.contentWidth,
    required this.columns,
    required this.itemWidth,
  });

  factory LocalGalleryViewModel.fromStates({
    required LocalGalleryState gallery,
    required BulkOperationState bulkOperation,
    required GalleryCategoryState categories,
    required bool isSelectionMode,
    required bool categoryPanelRequested,
    required bool isPackingImages,
    required double maxWidth,
    int preferredColumns = MasonryColumnCount.fallback,
  }) {
    final usePersistentCategories = maxWidth >= 1000;
    final showPersistentCategories =
        categoryPanelRequested && usePersistentCategories;
    final contentWidth = maxWidth - (showPersistentCategories ? 250 : 0);
    const horizontalPadding = 24.0;
    const spacing = 12.0;
    final availableGridWidth = (contentWidth - horizontalPadding).clamp(
      0.0,
      double.infinity,
    );
    // 手机上严格使用所选列数；更宽的布局保持同样的卡片大小增加列数。
    final columns = MasonryColumnCount.resolve(
      width: availableGridWidth,
      preferred: preferredColumns,
      spacing: spacing,
    );
    final itemWidth = (availableGridWidth - spacing * (columns - 1)) / columns;

    return LocalGalleryViewModel(
      gallery: gallery,
      bulkOperation: bulkOperation,
      categories: categories,
      isSelectionMode: isSelectionMode,
      showCategoryPanel: categoryPanelRequested,
      isPackingImages: isPackingImages,
      usePersistentCategories: usePersistentCategories,
      showPersistentCategories: showPersistentCategories,
      contentWidth: contentWidth,
      columns: columns,
      itemWidth: itemWidth,
    );
  }

  final LocalGalleryState gallery;
  final BulkOperationState bulkOperation;
  final GalleryCategoryState categories;
  final bool isSelectionMode;
  final bool showCategoryPanel;
  final bool isPackingImages;
  final bool usePersistentCategories;
  final bool showPersistentCategories;
  final double contentWidth;
  final int columns;
  final double itemWidth;
}
