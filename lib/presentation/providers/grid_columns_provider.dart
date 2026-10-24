import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/storage_keys.dart';
import '../../core/storage/local_storage_service.dart';
import '../../core/utils/app_logger.dart';
import '../widgets/common/grid_column_count.dart';

/// Screens whose image waterfalls remember their own column count, 2–4.
///
/// Column density depends on the device's screen, so the values stay local and
/// are not registered with cloud sync.
enum GridColumnsSurface {
  localGallery(StorageKeys.localGalleryMasonryColumns),
  generationHistory(StorageKeys.historyMasonryColumns),
  onlineGallery(StorageKeys.onlineGalleryMasonryColumns),
  vibeLibrary(StorageKeys.vibeLibraryMasonryColumns),
  preciseRefLibrary(StorageKeys.preciseRefLibraryMasonryColumns);

  const GridColumnsSurface(this.storageKey);

  final String storageKey;

  int get fallback => MasonryColumnCount.fallback;

  int clamp(int columns) => MasonryColumnCount.clamp(columns);

  int next(int columns) => MasonryColumnCount.next(columns);
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
