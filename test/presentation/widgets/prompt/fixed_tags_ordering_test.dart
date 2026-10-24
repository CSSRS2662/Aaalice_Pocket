import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/utils/usage_frecency.dart';
import 'package:nai_launcher/data/models/fixed_tag/fixed_tag_entry.dart';
import 'package:nai_launcher/presentation/providers/fixed_tags_sort_provider.dart';
import 'package:nai_launcher/presentation/providers/name_sort_key_provider.dart';
import 'package:nai_launcher/presentation/widgets/prompt/fixed_tags_ordering.dart';

FixedTagEntry _tag(String id, String name, int order, {bool enabled = false}) =>
    FixedTagEntry.create(
      name: name,
      content: name,
      enabled: enabled,
      sortOrder: order,
    ).copyWith(id: id);

void main() {
  final now = DateTime(2026, 10, 24);
  final tags = [
    _tag('a', 'Bravo', 0),
    _tag('b', 'alpha', 1, enabled: true),
    _tag('c', '草', 2),
    _tag('d', 'charlie', 3),
  ];
  final usage = {
    'c': UsageFrecency.empty.record(
      now.subtract(const Duration(days: 1)),
      uses: 10,
    ),
    'd': UsageFrecency.empty.record(
      now.subtract(const Duration(days: 40)),
      uses: 30,
    ),
  };

  List<String> ids(List<FixedTagEntry> entries) =>
      entries.map((entry) => entry.id).toList();

  test('custom keeps the prompt order and ignores enabled-first', () {
    expect(
      ids(
        orderFixedTags(
          tags.reversed.toList(),
          prefs: const FixedTagsSortPrefs(sort: FixedTagsSort.custom),
          usage: usage,
          now: now,
        ),
      ),
      ['a', 'b', 'c', 'd'],
    );
  });

  test('frequent ranks recent use first; unused tags keep their order', () {
    expect(
      ids(
        orderFixedTags(
          tags,
          prefs: const FixedTagsSortPrefs(enabledFirst: false),
          usage: usage,
          now: now,
        ),
      ),
      ['c', 'd', 'a', 'b'],
    );
  });

  test('recent sorts by the last use', () {
    expect(
      ids(
        orderFixedTags(
          tags,
          prefs: const FixedTagsSortPrefs(
            sort: FixedTagsSort.recent,
            enabledFirst: false,
          ),
          usage: usage,
          now: now,
        ),
      ),
      ['c', 'd', 'a', 'b'],
    );
  });

  test('enabled-first moves enabled tags ahead of the ranking', () {
    expect(
      ids(
        orderFixedTags(
          tags,
          prefs: const FixedTagsSortPrefs(),
          usage: usage,
          now: now,
        ),
      ),
      ['b', 'c', 'd', 'a'],
    );
  });

  test('name sorts case-insensitively, with pinyin keys for hanzi', () {
    String? readings(int rune) => rune == '草'.runes.first ? 'cao' : null;
    String key(String name) => pinyinSortKey(name, (rune) {
      final reading = readings(rune);
      return reading == null ? null : [reading];
    });

    expect(
      ids(
        orderFixedTags(
          tags,
          prefs: const FixedTagsSortPrefs(
            sort: FixedTagsSort.name,
            enabledFirst: false,
          ),
          nameSortKey: key,
          now: now,
        ),
      ),
      ['b', 'a', 'c', 'd'],
    );
  });

  test('pinyin keys spell hanzi and keep other characters', () {
    expect(
      pinyinSortKey('白 Bg', (rune) => rune == '白'.runes.first ? ['bai'] : null),
      'bai  bg',
    );
    expect(compareNames('b', 'A', null), greaterThan(0));
  });
}
