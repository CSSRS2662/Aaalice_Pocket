import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/storage_keys.dart';
import '../../core/storage/local_storage_service.dart';
import '../../core/utils/app_logger.dart';
import '../widgets/common/grid_column_count.dart';

/// Screens whose grids remember their own column count: title grids pick
/// 1–3 columns, image waterfalls 2–4.
///
/// Column density depends on the device's screen, so the values stay local and
/// are not registered with cloud sync.
enum GridColumnsSurface {
  fixedTags(StorageKeys.fixedTagsGridColumns),
  tagLibrary(StorageKeys.tagLibraryGridColumns),
  localGallery(StorageKeys.localGalleryMasonryColumns, masonry: true),
  generationHistory(StorageKeys.historyMasonryColumns, masonry: true),
  onlineGallery(StorageKeys.onlineGalleryMasonryColumns, masonry: true),
  vibeLibrary(StorageKeys.vibeLibraryMasonryColumns, masonry: true),
  preciseRefLibrary(StorageKeys.preciseRefLibraryMasonryColumns, masonry: true);

  const GridColumnsSurface(this.storageKey, {this.masonry = false});

  final String storageKey;
  final bool masonry;

  int get fallback =>
      masonry ? MasonryColumnCount.fallback : GridColumnCount.fallback;

  int clamp(int columns) => masonry
      ? MasonryColumnCount.clamp(columns)
      : GridColumnCount.clamp(columns);

  int next(int columns) => masonry
      ? MasonryColumnCount.next(columns)
      : GridColumnCount.next(columns);
}

final gridColumnsProvider =
    NotifierProvider.family<GridColumnsNotifier, int, GridColumnsSurface>(
      GridColumnsNotifier.new,
    );

class GridColumnsNotifier extends FamilyNotifier<int, GridColumnsSurface> {
  @override
  int build(GridColumnsSurface surface) {
    final stored = ref
        .watch(localStorageServiceProvider)
        .getSetting<Object>(surface.storageKey);
    return surface.clamp(stored is int ? stored : surface.fallback);
  }

  void cycle() => set(arg.next(state));

  void set(int columns) {
    final next = arg.clamp(columns);
    if (next == state) return;
    state = next;
    // Losing the preference only resets the layout on the next launch.
    unawaited(
      ref
          .read(localStorageServiceProvider)
          .setSetting(arg.storageKey, next)
          .catchError(
            (Object error) => AppLogger.w(
              'Failed to save ${arg.storageKey}: $error',
              'GridColumns',
            ),
          ),
    );
  }
}
