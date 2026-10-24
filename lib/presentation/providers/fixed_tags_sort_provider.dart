import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/storage_keys.dart';
import '../../core/storage/local_storage_service.dart';
import '../../core/utils/app_logger.dart';

/// How the fixed tags manager orders tags. Stored by name.
enum FixedTagsSort {
  /// Most used lately first; a use counts half as much after two weeks.
  frequent,

  /// Sent with an image most recently first.
  recent,

  /// The prompt order, grouped by library groups.
  custom,

  /// By name, Chinese by pinyin.
  name,
}

@immutable
class FixedTagsSortPrefs {
  const FixedTagsSortPrefs({
    this.sort = FixedTagsSort.frequent,
    this.enabledFirst = true,
  });

  final FixedTagsSort sort;

  /// Enabled tags before the rest; not used by [FixedTagsSort.custom], which
  /// keeps the prompt order.
  final bool enabledFirst;

  bool get groupsByCategory => sort == FixedTagsSort.custom;

  @override
  bool operator ==(Object other) =>
      other is FixedTagsSortPrefs &&
      other.sort == sort &&
      other.enabledFirst == enabledFirst;

  @override
  int get hashCode => Object.hash(sort, enabledFirst);
}

/// The fixed tags manager's sort, kept across sessions and synced with the
/// other display settings.
final fixedTagsSortProvider =
    NotifierProvider<FixedTagsSortNotifier, FixedTagsSortPrefs>(
      FixedTagsSortNotifier.new,
    );

class FixedTagsSortNotifier extends Notifier<FixedTagsSortPrefs> {
  @override
  FixedTagsSortPrefs build() {
    final storage = ref.watch(localStorageServiceProvider);
    final sortName = storage.getSetting<String>(StorageKeys.fixedTagsSort);
    return FixedTagsSortPrefs(
      sort:
          FixedTagsSort.values.asNameMap()[sortName] ?? FixedTagsSort.frequent,
      enabledFirst:
          storage.getSetting<bool>(StorageKeys.fixedTagsEnabledFirst) ?? true,
    );
  }

  void setSort(FixedTagsSort sort) {
    if (sort == state.sort) return;
    state = FixedTagsSortPrefs(sort: sort, enabledFirst: state.enabledFirst);
    _save(StorageKeys.fixedTagsSort, sort.name);
  }

  void setEnabledFirst(bool value) {
    if (value == state.enabledFirst) return;
    state = FixedTagsSortPrefs(sort: state.sort, enabledFirst: value);
    _save(StorageKeys.fixedTagsEnabledFirst, value);
  }

  void _save(String key, Object value) {
    unawaited(
      ref
          .read(localStorageServiceProvider)
          .setSetting(key, value)
          .catchError(
            (Object error) => AppLogger.w(
              'Failed to save fixed tags sort: $error',
              'FixedTagsSort',
            ),
          ),
    );
  }
}
