import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/storage_keys.dart';
import '../../core/storage/local_storage_service.dart';
import '../../core/utils/app_logger.dart';
import '../../data/models/character/character_library_entry.dart';

/// The character library, newest first as stored.
///
/// Kept as one setting so it syncs with the fixed tags its characters refer
/// to, under "prompts and tags".
final characterLibraryProvider =
    NotifierProvider<CharacterLibraryNotifier, List<CharacterLibraryEntry>>(
      CharacterLibraryNotifier.new,
    );

class CharacterLibraryNotifier extends Notifier<List<CharacterLibraryEntry>> {
  @override
  List<CharacterLibraryEntry> build() {
    final raw = ref
        .watch(localStorageServiceProvider)
        .getSetting<String>(StorageKeys.characterLibraryData);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final value = jsonDecode(raw);
      if (value is! List) return const [];
      return [
        for (final item in value)
          if (CharacterLibraryEntry.fromJson(item) case final entry?) entry,
      ];
    } on FormatException catch (error) {
      AppLogger.w('Unreadable character library: $error', 'CharacterLibrary');
      return const [];
    }
  }

  CharacterLibraryEntry? byId(String id) {
    for (final entry in state) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  /// Categories in use, in the order they first appear.
  List<String> get categories => {
    for (final entry in state)
      if (entry.category.isNotEmpty) entry.category,
  }.toList();

  void add(CharacterLibraryEntry entry) => _set([entry, ...state]);

  /// Replaces the entry with the same id, stamping it as changed now.
  void update(CharacterLibraryEntry entry) => _set([
    for (final item in state)
      if (item.id == entry.id)
        entry.copyWith(updatedAt: DateTime.now())
      else
        item,
  ]);

  void remove(String id) => _set([
    for (final item in state)
      if (item.id != id) item,
  ]);

  void toggleFavorite(String id) {
    final entry = byId(id);
    if (entry != null) update(entry.copyWith(favorite: !entry.favorite));
  }

  /// Puts a copy named [name] right after the entry and returns it.
  CharacterLibraryEntry? duplicate(String id, {required String name}) {
    final entry = byId(id);
    if (entry == null) return null;
    final now = DateTime.now();
    final copy = CharacterLibraryEntry.create(
      name: name,
      gender: entry.gender,
      positiveSections: entry.positiveSections,
      negativeSections: entry.negativeSections,
      category: entry.category,
    ).copyWith(createdAt: now, updatedAt: now);
    final index = state.indexWhere((item) => item.id == id);
    _set([...state]..insert(index + 1, copy));
    return copy;
  }

  /// Counts one more use of each of [ids] and marks them used now.
  void recordUse(Iterable<String> ids) {
    final used = ids.toSet();
    if (used.isEmpty) return;
    final now = DateTime.now();
    _set([
      for (final item in state)
        if (used.contains(item.id))
          item.copyWith(useCount: item.useCount + 1, lastUsedAt: now)
        else
          item,
    ]);
  }

  void _set(List<CharacterLibraryEntry> next) {
    state = next;
    // Losing a write keeps the change only until the app restarts.
    unawaited(
      ref
          .read(localStorageServiceProvider)
          .setSetting(
            StorageKeys.characterLibraryData,
            jsonEncode([for (final entry in next) entry.toJson()]),
          )
          .catchError(
            (Object error) => AppLogger.w(
              'Failed to save the character library: $error',
              'CharacterLibrary',
            ),
          ),
    );
  }
}
