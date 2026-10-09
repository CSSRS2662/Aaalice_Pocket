import 'dart:math' as math;

import 'completion_models.dart';
import 'tag_catalog_repository.dart';

/// A tag already written, its co-occurrence rows and its share of the vote.
class RelatedContextTag {
  const RelatedContextTag({
    required this.record,
    required this.weight,
    required this.related,
    required this.complete,
  });

  final TagCatalogRecord record;

  /// Share of the vote; the shares of one query add up to 1.
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

/// Ranks tags that fit what is already written, led by the last tag.
///
/// The last tag (the anchor) holds [anchorShare] of the vote; the others
/// split the rest by how specific they are and how near the caret. Each
/// tag first ranks candidates on its own — how often they appear together
/// times the log of how much more often than chance (lift) — scaled so its
/// best candidate counts 1, so a rare tag cannot outvote the anchor by the
/// size of its numbers. A candidate seen with a context tag less often than
/// chance conflicts with it (night and day) and is pushed down.
///
/// Character, series and other non-general tags only take part when the
/// anchor is one: after a general tag the context and the suggestions are
/// general tags alone.
abstract final class RelatedTagScorer {
  /// Roughly the number of Danbooru posts the counts come from; lift only
  /// needs its order of magnitude.
  static const double corpusPosts = 9000000;

  /// The data pack keeps only pairs seen together at least this often.
  static const int minimumPairCount = 100;

  /// The last tag's share of the vote when other tags take part.
  static const double anchorShare = 0.6;

  /// How specific a tag is: rare tags say more than `1girl`-like ones.
  static double specificity(int postCount) =>
      math.log(corpusPosts / math.max(1, postCount)).clamp(0.05, 20.0);

  /// Vote shares for the anchor and the [others] (nearest first), given as
  /// post counts. Shares add up to 1.
  static List<double> shares(List<int> others) {
    if (others.isEmpty) return const [1];
    final raw = [
      for (final (distance, postCount) in others.indexed)
        specificity(postCount) * math.pow(0.85, distance),
    ];
    final total = raw.fold<double>(0, (sum, value) => sum + value);
    return [
      anchorShare,
      for (final value in raw) (1 - anchorShare) * value / total,
    ];
  }

  /// Whether [category] is a general tag. The anchor's decides whether
  /// character, series and other names take part at all.
  static bool isGeneral(TagCategory category) =>
      category == TagCategory.general;

  /// Scores between 0 and 1, the best candidate scoring 1. [context] starts
  /// with the anchor. Candidates no context tag supports are left out.
  static Map<String, double> score({
    required List<RelatedContextTag> context,
    required Map<String, TagCatalogRecord> candidates,
  }) {
    if (context.isEmpty) return const {};
    final anchor = context.first.record.category;
    final generalOnly = isGeneral(anchor);
    final characterAnchor = anchor == TagCategory.character;

    final votes = [for (final _ in context) <String, double>{}];
    final damping = <String, double>{};
    for (final MapEntry(key: name, value: record) in candidates.entries) {
      if (record.postCount <= 0) continue;
      if (generalOnly ? !isGeneral(record.category) : !_suggestible(record)) {
        continue;
      }
      var damp = 1.0;
      for (final (index, tag) in context.indexed) {
        final shared = tag.related[name];
        final expected = tag.record.postCount * record.postCount / corpusPosts;
        if (expected <= 0) continue;
        if (shared != null) {
          final lift = shared / expected;
          if (lift > 1) {
            votes[index][name] = shared / tag.record.postCount * math.log(lift);
          } else {
            damp *= _conflict(lift);
          }
        } else {
          final bound = tag.missingPairBound / expected;
          if (bound < 1) damp *= _conflict(bound);
        }
      }
      // A character's own traits help more than their castmates.
      if (characterAnchor && record.category == TagCategory.character) {
        damp *= 0.4;
      }
      damping[name] = damp;
    }

    final raw = <String, double>{};
    for (final (index, tag) in context.indexed) {
      final tagVotes = votes[index];
      if (tagVotes.isEmpty) continue;
      final best = tagVotes.values.reduce(math.max);
      for (final MapEntry(key: name, value: vote) in tagVotes.entries) {
        raw[name] = (raw[name] ?? 0) + tag.weight * vote / best;
      }
    }
    final scored = {
      for (final MapEntry(key: name, value: value) in raw.entries)
        name: value * damping[name]!,
    };
    final best = scored.values.fold<double>(0, math.max);
    if (best <= 0) return const {};
    return {
      for (final entry in scored.entries)
        if (entry.value > 0) entry.key: entry.value / best,
    };
  }

  static double _conflict(double lift) {
    final bounded = lift.clamp(0.1, 1.0);
    return bounded * bounded;
  }

  static bool _suggestible(TagCatalogRecord record) =>
      record.category != TagCategory.artist &&
      record.category != TagCategory.meta;
}
