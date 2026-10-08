import 'dart:math' as math;

import '../../constants/storage_keys.dart';
import '../../storage/local_storage_service.dart';

/// Tags this device put next to each other when accepting suggestions: after
/// `beach`, picking `sunset` remembers that pair. Related suggestions for a
/// context then favour what this person usually adds next. Like
/// [TagUsageHistory] the record stays on the device and is never synced.
class TagPairHistory {
  TagPairHistory(this._storage, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final LocalStorageService _storage;
  final DateTime Function() _now;
  Map<String, _PairUse>? _cache;

  static const int maxEntries = 3000;

  /// Half-life of a past pairing, in days.
  static const double halfLifeDays = 60;

  /// How many tags before an accepted one it is paired with.
  static const int pairedNeighbours = 3;

  /// Uses after which a pairing counts fully.
  static const int fullStrengthUses = 5;

  static const String _separator = '\t';

  Map<String, _PairUse> get _entries => _cache ??= _load();

  Map<String, _PairUse> _load() {
    final stored = _storage.getSetting<dynamic>(
      StorageKeys.autocompleteTagPairHistory,
    );
    if (stored is! Map) return {};
    final result = <String, _PairUse>{};
    for (final entry in stored.entries) {
      final value = entry.value;
      if (entry.key is! String || value is! List || value.length < 2) continue;
      final count = value[0];
      final day = value[1];
      if (count is int && day is int) {
        result[entry.key as String] = _PairUse(count, day);
      }
    }
    return result;
  }

  int get _today => _now().toUtc().millisecondsSinceEpoch ~/ 86400000;

  int get length => _entries.length;

  bool get isEmpty => _entries.isEmpty;

  /// Pairs [accepted] with the tags written just before it, nearest first.
  Future<void> record(List<String> previousTags, String accepted) async {
    final next = _normalize(accepted);
    if (next.isEmpty) return;
    final entries = _entries;
    final today = _today;
    var changed = false;
    for (final previous in previousTags.take(pairedNeighbours)) {
      final tag = _normalize(previous);
      if (tag.isEmpty || tag == next) continue;
      final key = '$tag$_separator$next';
      entries[key] = _PairUse((entries[key]?.count ?? 0) + 1, today);
      changed = true;
    }
    if (!changed) return;
    if (entries.length > maxEntries) {
      final weakest = entries.keys.toList()
        ..sort(
          (a, b) => _strength(entries[a]!).compareTo(_strength(entries[b]!)),
        );
      for (final key in weakest.take(entries.length - maxEntries)) {
        entries.remove(key);
      }
    }
    await _storage.setSetting<Map<String, Object>>(
      StorageKeys.autocompleteTagPairHistory,
      {
        for (final entry in entries.entries)
          entry.key: [entry.value.count, entry.value.day],
      },
    );
  }

  /// How strongly this person follows [contextTags] (nearest first) with
  /// each remembered tag, from 0 to 1.
  Map<String, double> scores(List<String> contextTags) {
    final entries = _entries;
    if (entries.isEmpty || contextTags.isEmpty) return const {};
    final weights = <String, double>{};
    var totalWeight = 0.0;
    for (final (index, raw) in contextTags.take(6).indexed) {
      final tag = _normalize(raw);
      if (tag.isEmpty || weights.containsKey(tag)) continue;
      final weight = math.pow(0.85, index).toDouble();
      weights[tag] = weight;
      totalWeight += weight;
    }
    if (totalWeight <= 0) return const {};
    final result = <String, double>{};
    for (final MapEntry(:key, :value) in entries.entries) {
      final split = key.indexOf(_separator);
      if (split <= 0) continue;
      final weight = weights[key.substring(0, split)];
      if (weight == null) continue;
      final candidate = key.substring(split + 1);
      if (weights.containsKey(candidate)) continue;
      result[candidate] = (result[candidate] ?? 0) + weight * _strength(value);
    }
    return {
      for (final entry in result.entries)
        entry.key: (entry.value / totalWeight).clamp(0.0, 1.0),
    };
  }

  Future<void> clear() async {
    _cache = {};
    await _storage.deleteSetting(StorageKeys.autocompleteTagPairHistory);
  }

  /// 0 to 1: grows with uses and fades with time since the last.
  double _strength(_PairUse use) {
    final age = math.max(0, _today - use.day);
    final decay = math.pow(0.5, age / halfLifeDays).toDouble();
    final uses = math.log(1 + use.count) / math.log(1 + fullStrengthUses);
    return math.min(1.0, uses) * decay;
  }

  static String _normalize(String tag) =>
      tag.trim().toLowerCase().replaceAll(' ', '_');
}

class _PairUse {
  const _PairUse(this.count, this.day);

  final int count;

  /// Days since the epoch (UTC) of the last use.
  final int day;
}
