import 'dart:math' as math;

import 'completion_models.dart';
import 'tag_catalog_repository.dart';

/// A tag already written, its co-occurrence rows and how much it steers the
/// suggestions.
class RelatedContextTag {
  const RelatedContextTag({
    required this.record,
    required this.weight,
    required this.related,
    required this.complete,
  });

  final TagCatalogRecord record;
  final double weight;

  /// Posts shared with other tags, most frequent first.
  final Map<String, int> related;

  /// Whether [related] holds every pair the data keeps for this tag. When it
  /// was cut short, its smallest count bounds the pairs that were left out.
  final bool complete;

  /// The most a pair missing from [related] can have been seen.
  int get missingPairBound => complete || related.isEmpty
      ? RelatedTagScorer.minimumPairCount
      : math.max(RelatedTagScorer.minimumPairCount, related.values.last);
}

/// Ranks tags that fit everything already written, not just the last tag.
///
/// Each context tag votes for a candidate with how often the two appear
/// together times the log of how much more often than chance (lift), so both
/// frequent and distinctive companions rise. Rare, specific tags vote louder
/// than `1girl`-like ones, and tags near the caret louder than far ones. A
/// candidate seen with a context tag less often than chance conflicts with it
/// (night and day) and is pushed down. Character and series names only lead
/// when the context already names one.
abstract final class RelatedTagScorer {
  /// Roughly the number of Danbooru posts the counts come from; lift only
  /// needs its order of magnitude.
  static const double corpusPosts = 9000000;

  /// The data pack keeps only pairs seen together at least this often.
  static const int minimumPairCount = 100;

  /// Weight of a context tag [distance] tags away from the caret.
  static double contextWeight(
    int postCount, {
    required int distance,
    bool anchor = false,
  }) {
    final specificity = math
        .log(corpusPosts / math.max(1, postCount))
        .clamp(0.05, 20.0);
    return specificity * math.pow(0.85, distance) * (anchor ? 1.5 : 1);
  }

  /// Scores between 0 and 1, the best candidate scoring 1. Candidates
  /// without support from any context tag are left out.
  static Map<String, double> score({
    required List<RelatedContextTag> context,
    required Map<String, TagCatalogRecord> candidates,
  }) {
    final totalWeight = context.fold<double>(0, (sum, tag) => sum + tag.weight);
    if (totalWeight <= 0) return const {};
    final namesSomething = context.any((tag) => _isNamed(tag.record.category));
    final namesCharacter = context.any(
      (tag) => tag.record.category == TagCategory.character,
    );

    final raw = <String, double>{};
    for (final MapEntry(key: name, value: record) in candidates.entries) {
      if (record.postCount <= 0 || !_isSuggestible(record.category)) continue;
      var support = 0.0;
      var damping = 1.0;
      for (final tag in context) {
        final shared = tag.related[name];
        final expected = tag.record.postCount * record.postCount / corpusPosts;
        if (expected <= 0) continue;
        if (shared != null) {
          final lift = shared / expected;
          if (lift > 1) {
            support +=
                tag.weight * (shared / tag.record.postCount) * math.log(lift);
          } else {
            damping *= _conflict(lift);
          }
        } else {
          final bound = tag.missingPairBound / expected;
          if (bound < 1) damping *= _conflict(bound);
        }
      }
      if (support <= 0) continue;
      if (_isNamed(record.category) && !namesSomething) support *= 0.3;
      if (record.category == TagCategory.character && namesCharacter) {
        // A character's own traits help more than their castmates.
        support *= 0.4;
      }
      raw[name] = support / totalWeight * damping;
    }
    final best = raw.values.fold<double>(0, math.max);
    if (best <= 0) return const {};
    return {for (final entry in raw.entries) entry.key: entry.value / best};
  }

  static double _conflict(double lift) {
    final bounded = lift.clamp(0.1, 1.0);
    return bounded * bounded;
  }

  static bool _isNamed(TagCategory category) =>
      category == TagCategory.character || category == TagCategory.copyright;

  static bool _isSuggestible(TagCategory category) =>
      category != TagCategory.artist && category != TagCategory.meta;
}
