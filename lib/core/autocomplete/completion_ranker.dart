import 'dart:math' as math;

import 'completion_intent.dart';
import 'completion_models.dart';

class CompletionRanker {
  const CompletionRanker._();

  /// Merges independent lexical and semantic evidence before applying
  /// context, habit and explicit query constraints.
  static List<CompletionCandidate> mergeAndSort(
    Iterable<CompletionCandidate> candidates, {
    required CompletionQuery query,
    int? limit,
    Map<String, double> boosts = const {},
  }) {
    final merged = <String, CompletionCandidate>{};
    for (final incoming in candidates) {
      final key = incoming.stableId;
      final existing = merged[key];
      if (existing == null) {
        merged[key] = incoming.copyWith(
          isExisting: query.existingTags.contains(key),
        );
        continue;
      }

      final baseOwnsRecord = existing.sources.contains(
        CompletionSourceKind.base,
      );
      final aliases = <String>{
        ...existing.aliases,
        ...incoming.aliases,
      }.toList()..sort();
      final sources = <CompletionSourceKind>{
        ...existing.sources,
        ...incoming.sources,
      };
      final evidence = _lexicalStrength(incoming) > _lexicalStrength(existing)
          ? incoming
          : existing;
      final translation = existing.translation?.trim().isNotEmpty == true
          ? existing.translation
          : incoming.translation;
      final mergedCandidate = CompletionCandidate(
        canonicalTag: existing.canonicalTag,
        category: baseOwnsRecord ? existing.category : incoming.category,
        postCount: baseOwnsRecord ? existing.postCount : incoming.postCount,
        aliases: aliases,
        translation: translation,
        matchedAlias: evidence.matchedAlias,
        matchKind: evidence.matchKind,
        sources: sources,
        isExisting: query.existingTags.contains(key),
        isTranslating: existing.isTranslating || incoming.isTranslating,
        relatedScore: _greaterNullable(
          existing.relatedScore,
          incoming.relatedScore,
        ),
        cooccurrenceCount: _greaterNullable(
          existing.cooccurrenceCount,
          incoming.cooccurrenceCount,
        ),
        semanticScore: _greaterNullable(
          existing.semanticScore,
          incoming.semanticScore,
        ),
        matchHint: evidence.matchHint,
        matchQuality: evidence.matchQuality,
      );
      merged[key] = mergedCandidate;
    }

    final intent = query.isChinese && query.relatedTag == null
        ? CompletionIntent(query.token)
        : null;
    final results =
        [for (final row in merged.values) _score(row, intent, boosts)]
          ..sort((a, b) {
            final band = _band(a, query).compareTo(_band(b, query));
            if (band != 0) return band;
            final aLiteral = _literalStrength(a.matchKind) != null;
            final bLiteral = _literalStrength(b.matchKind) != null;
            if (aLiteral != bLiteral) return aLiteral ? -1 : 1;
            if (query.relatedTag != null) {
              final relatedScore = (b.relatedScore ?? 0).compareTo(
                a.relatedScore ?? 0,
              );
              if (relatedScore != 0) return relatedScore;
              final occurrences = (b.cooccurrenceCount ?? 0).compareTo(
                a.cooccurrenceCount ?? 0,
              );
              if (occurrences != 0) return occurrences;
            }
            final score = b.score.compareTo(a.score);
            if (score != 0) return score;
            final count = b.postCount.compareTo(a.postCount);
            if (count != 0) return count;
            return a.canonicalTag.compareTo(b.canonicalTag);
          });
    return results.take(limit ?? query.limit).toList(growable: false);
  }

  /// A typed tag the prompt already holds leads the list when it matches the
  /// input literally, so the duplicate is seen before it is written again.
  /// Looser matches (pinyin, typo fixes, meaning) arrive later and keep
  /// their place among the others, so rows on screen never jump. Related
  /// suggestions put written tags last; they are dropped from them anyway.
  static int _band(CompletionCandidate candidate, CompletionQuery query) {
    if (!candidate.isExisting) return 1;
    if (query.relatedTag != null) return 2;
    return _isLiteralMatch(candidate.matchKind) ? 0 : 1;
  }

  /// Whether [kind] matched the typed text itself rather than a reading,
  /// a correction or a meaning of it.
  static bool _isLiteralMatch(CompletionMatchKind kind) =>
      _literalStrength(kind) != null ||
      kind == CompletionMatchKind.chineseContains;

  static CompletionCandidate _score(
    CompletionCandidate candidate,
    CompletionIntent? intent,
    Map<String, double> boosts,
  ) {
    final popularity = math.log(1 + math.max(0, candidate.postCount)) * .002;
    final context =
        (boosts[candidate.stableId] ?? 0).clamp(0.0, 6000.0) * .00001;
    final literal = _literalStrength(candidate.matchKind);
    if (literal != null) {
      return candidate.copyWith(
        score: literal + candidate.matchQuality * .04 + popularity + context,
      );
    }
    final lexical = _lexicalStrength(candidate);
    final cosine = candidate.semanticScore;
    final semantic = cosine == null
        ? 0.0
        : ((cosine - .78) * 2.6 + .36).clamp(0.0, 1.0);
    final corroboration = math.min(lexical, semantic) * .07;
    final constraints = intent?.adjustment(candidate.canonicalTag) ?? 0;
    return candidate.copyWith(
      score:
          math.max(lexical, semantic) +
          corroboration +
          context +
          popularity +
          constraints,
    );
  }

  static double? _literalStrength(CompletionMatchKind kind) => switch (kind) {
    CompletionMatchKind.englishExact => 2.2,
    CompletionMatchKind.englishPrefix => 2.0,
    CompletionMatchKind.aliasExact => 1.8,
    CompletionMatchKind.aliasPrefix => 1.6,
    CompletionMatchKind.chineseExact => 1.4,
    CompletionMatchKind.chinesePrefix => 1.25,
    _ => null,
  };

  static double _lexicalStrength(CompletionCandidate row) {
    final literal = _literalStrength(row.matchKind);
    final quality = row.matchQuality.clamp(0.0, 1.0);
    if (literal != null) return literal + quality * .04;
    return switch (row.matchKind) {
      CompletionMatchKind.chineseContains => .53 + .22 * quality,
      CompletionMatchKind.homophone => .37 + .45 * quality,
      CompletionMatchKind.spellCorrected => .37 + .55 * quality,
      CompletionMatchKind.englishVariant => .47 + .37 * quality,
      CompletionMatchKind.pinyin => .44 + .45 * quality,
      CompletionMatchKind.shuangpin => .38 + .48 * quality,
      CompletionMatchKind.crossLingual => .24 + .68 * quality,
      CompletionMatchKind.approximate => .20 + .67 * quality,
      CompletionMatchKind.fuzzyPinyin => .32 + .43 * quality,
      CompletionMatchKind.pinyinInitials => .24 + .41 * quality,
      CompletionMatchKind.fullText => row.semanticScore == null ? .38 : 0,
      _ => 0,
    };
  }

  static T? _greaterNullable<T extends num>(T? left, T? right) {
    if (left == null) return right;
    if (right == null) return left;
    return left >= right ? left : right;
  }
}
