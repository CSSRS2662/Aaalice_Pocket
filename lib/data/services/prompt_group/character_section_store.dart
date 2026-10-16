import 'dart:async';
import 'dart:convert';

import '../../../core/constants/storage_keys.dart';
import '../../../core/storage/local_storage_service.dart';

/// 角色提示词分区的本机存储：角色 ID → 该角色保存的分区。
///
/// 与主提示词分区一样只在本机整理提示词，不参与请求，也不进 PNG。
abstract final class CharacterSectionStore {
  static Map<String, Object?> readAll(LocalStorageService storage) {
    final raw = storage.getSetting<String>(
      StorageKeys.characterPromptGroupState,
    );
    if (raw == null || raw.isEmpty) return {};
    try {
      final value = jsonDecode(raw);
      return value is Map ? Map<String, Object?>.from(value) : {};
    } on FormatException {
      return {};
    }
  }

  static void writeAll(
    LocalStorageService storage,
    Map<String, Object?> entries,
  ) {
    unawaited(
      storage.setSetting(
        StorageKeys.characterPromptGroupState,
        jsonEncode(entries),
      ),
    );
  }

  /// [ids] 各自保存的分区，供生成时随结果图一起记录。
  static Map<String, Object?> entriesFor(
    LocalStorageService storage,
    Iterable<String> ids,
  ) {
    final all = readAll(storage);
    return {
      for (final id in ids)
        if (all[id] case final Map<Object?, Object?> entry) id: entry,
    };
  }

  /// 放回 [entries]，其他角色的分区保持不变。
  static void restore(
    LocalStorageService storage,
    Map<String, Object?> entries,
  ) {
    if (entries.isEmpty) return;
    writeAll(storage, readAll(storage)..addAll(entries));
  }
}
