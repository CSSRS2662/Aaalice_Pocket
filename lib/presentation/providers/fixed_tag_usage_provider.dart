import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/storage_keys.dart';
import '../../core/storage/local_storage_service.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/usage_frecency.dart';

/// How much each fixed tag has been used lately, keyed by tag id, for the
/// "frequently used" order of the fixed tags manager.
///
/// Every generated image adds one use to each tag it was sent with. The
/// scores describe this device's habits, like learned tag pairs, so they stay
/// local and are not synced.
final fixedTagUsageProvider =
    NotifierProvider<FixedTagUsageNotifier, Map<String, UsageFrecency>>(
      FixedTagUsageNotifier.new,
    );

class FixedTagUsageNotifier extends Notifier<Map<String, UsageFrecency>> {
  /// Enough for any real collection of fixed tags; the least used go first.
  static const maxTags = 500;

  @override
  Map<String, UsageFrecency> build() {
    final raw = ref
        .watch(localStorageServiceProvider)
        .getSetting<String>(StorageKeys.fixedTagUsageScores);
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      final scores = <String, UsageFrecency>{};
      decoded.forEach((key, value) {
        final usage = UsageFrecency.fromJson(value);
        if (key is String && usage != null) scores[key] = usage;
      });
      return Map.unmodifiable(scores);
    } on FormatException {
      return const {};
    }
  }

  /// Records that [tagIds] were sent with [images] generated images.
  void record(Iterable<String> tagIds, {int images = 1, DateTime? at}) {
    final ids = tagIds.toSet();
    if (ids.isEmpty || images <= 0) return;
    final now = at ?? DateTime.now();
    final next = {...state};
    for (final id in ids) {
      next[id] = (next[id] ?? UsageFrecency.empty).record(now, uses: images);
    }
    if (next.length > maxTags) {
      final ranked = next.entries.toList()
        ..sort((a, b) => b.value.scoreAt(now).compareTo(a.value.scoreAt(now)));
      next
        ..clear()
        ..addEntries(ranked.take(maxTags));
    }
    state = Map.unmodifiable(next);
    _persist();
  }

  void _persist() {
    final value = jsonEncode({
      for (final MapEntry(:key, :value) in state.entries) key: value.toJson(),
    });
    // Losing a write only makes the order slightly stale.
    unawaited(
      ref
          .read(localStorageServiceProvider)
          .setSetting(StorageKeys.fixedTagUsageScores, value)
          .catchError(
            (Object error) => AppLogger.w(
              'Failed to save fixed tag usage: $error',
              'FixedTagUsage',
            ),
          ),
    );
  }
}
