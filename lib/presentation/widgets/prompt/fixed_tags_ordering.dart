import 'package:collection/collection.dart';

import '../../../core/utils/usage_frecency.dart';
import '../../../data/models/fixed_tag/fixed_tag_entry.dart';
import '../../providers/fixed_tags_sort_provider.dart';
import '../../providers/name_sort_key_provider.dart';

/// [entries] in the order the manager shows them under [prefs].
///
/// Ties keep the prompt order, so tags that were never used stay where the
/// user put them.
List<FixedTagEntry> orderFixedTags(
  List<FixedTagEntry> entries, {
  required FixedTagsSortPrefs prefs,
  Map<String, UsageFrecency> usage = const {},
  NameSortKey? nameSortKey,
  DateTime? now,
}) {
  final ordered = entries.sortedByOrder();
  final at = now ?? DateTime.now();
  final epoch = DateTime.fromMillisecondsSinceEpoch(0);
  final compare = switch (prefs.sort) {
    FixedTagsSort.custom => null,
    FixedTagsSort.frequent =>
      (FixedTagEntry a, FixedTagEntry b) => (usage[b.id]?.scoreAt(at) ?? 0)
          .compareTo(usage[a.id]?.scoreAt(at) ?? 0),
    FixedTagsSort.recent =>
      (FixedTagEntry a, FixedTagEntry b) => (usage[b.id]?.lastUsedAt ?? epoch)
          .compareTo(usage[a.id]?.lastUsedAt ?? epoch),
    FixedTagsSort.name => (FixedTagEntry a, FixedTagEntry b) => compareNames(
      a.displayName,
      b.displayName,
      nameSortKey,
    ),
  };
  if (compare == null) return ordered;
  mergeSort(ordered, compare: compare);
  if (!prefs.enabledFirst) return ordered;
  return [
    ...ordered.where((entry) => entry.enabled),
    ...ordered.where((entry) => !entry.enabled),
  ];
}
