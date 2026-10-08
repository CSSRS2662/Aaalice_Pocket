import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/autocomplete/lexical/tag_pair_history.dart';
import 'package:nai_launcher/core/constants/storage_keys.dart';

import '../../../helpers/memory_local_storage.dart';

void main() {
  test('pairs an accepted tag with the ones just before it', () async {
    final storage = MemoryLocalStorage();
    final history = TagPairHistory(storage);

    await history.record(['bikini', 'beach', 'ocean', 'sky'], 'Sunset');
    expect(history.length, TagPairHistory.pairedNeighbours);

    final nearest = history.scores(['bikini']);
    expect(nearest.keys, ['sunset']);
    // A pairing with the nearest written tag counts more than a farther one.
    expect(
      history.scores(['other', 'bikini'])['sunset']!,
      lessThan(history.scores(['bikini', 'other'])['sunset']!),
    );
    expect(history.scores(['sky']), isEmpty);

    // Stored on the device and read back by a new instance.
    expect(storage.values[StorageKeys.autocompleteTagPairHistory], isNotNull);
    expect(TagPairHistory(storage).scores(['bikini']), nearest);
  });

  test('uses build up and fade with time', () async {
    var now = DateTime.utc(2026, 10, 1);
    final history = TagPairHistory(MemoryLocalStorage(), now: () => now);
    await history.record(['beach'], 'sunset');
    final once = history.scores(['beach'])['sunset']!;
    for (var use = 0; use < TagPairHistory.fullStrengthUses; use++) {
      await history.record(['beach'], 'sunset');
    }
    expect(history.scores(['beach'])['sunset'], 1.0);
    expect(once, lessThan(1.0));

    now = now.add(const Duration(days: 60));
    expect(history.scores(['beach'])['sunset'], closeTo(0.5, 0.001));
  });

  test('clearing forgets everything', () async {
    final storage = MemoryLocalStorage();
    final history = TagPairHistory(storage);
    await history.record(['beach'], 'sunset');
    await history.clear();
    expect(history.isEmpty, isTrue);
    expect(
      storage.values.containsKey(StorageKeys.autocompleteTagPairHistory),
      isFalse,
    );
  });
}
