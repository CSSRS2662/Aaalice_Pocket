import 'dart:math' as math;

import '../database/datasources/cooccurrence_data_source.dart';
import 'completion_models.dart';
import 'related_tag_scorer.dart';
import 'tag_catalog_repository.dart';

typedef CooccurrenceDataSourceLoader =
    Future<CooccurrenceDataSource> Function();

/// How strongly this person follows the given context tags (nearest first)
/// with each tag, from 0 to 1.
typedef PersonalPairScores =
    Map<String, double> Function(List<String> contextTags);

/// Offline related-tag source backed by the optional compact data pack.
///
/// Suggestions fit the related tag together with the tags written around
/// the caret (see [RelatedTagScorer]), plus what this person usually writes
/// next when [personalPairs] is given. The pack stores shared post counts;
/// catalog post counts are joined at query time instead of duplicating the
/// complete tag catalog in another database.
class CooccurrenceCompletionSource implements CompletionSource {
  CooccurrenceCompletionSource(
    CooccurrenceDataSource dataSource, {
    required TagCatalogRepository catalog,
    PersonalPairScores? personalPairs,
  }) : this.withLoader(
         () async => dataSource,
         catalog: catalog,
         personalPairs: personalPairs,
       );

  CooccurrenceCompletionSource.withLoader(
    this._loadDataSource, {
    required TagCatalogRepository catalog,
    PersonalPairScores? personalPairs,
  }) : _catalog = catalog,
       _personalPairs = personalPairs;

  final CooccurrenceDataSourceLoader _loadDataSource;
  final TagCatalogRepository _catalog;
  final PersonalPairScores? _personalPairs;

  /// Context tags read, the related tag first; more add little.
  static const int maxContextTags = 6;

  /// Rows read per context tag, most frequent first. Rarer pairs barely move
  /// a score; the last row still bounds the ones left out.
  static const int rowsPerContextTag = 1000;

  /// Most suggestions returned.
  static const int maxResults = 300;

  /// How far a remembered habit lifts a suggestion on the 0 to 1 scale.
  static const double personalWeight = 0.35;

  static const int _maxRememberedRecords = 20000;
  final Map<String, TagCatalogRecord?> _records = {};

  @override
  Future<List<CompletionCandidate>> search(CompletionQuery query) async {
    final relatedTag = _normalize(query.relatedTag ?? '');
    if (relatedTag.isEmpty || query.token.isNotEmpty) return const [];

    final contextNames = <String>[relatedTag];
    for (final raw in query.contextTags) {
      if (contextNames.length >= maxContextTags) break;
      final tag = _normalize(raw);
      if (tag.isNotEmpty && !contextNames.contains(tag)) contextNames.add(tag);
    }

    final dataSource = await _loadDataSource();
    final contextRecords = await _recordsFor(contextNames);
    // The related tag decides whether names take part: after a general (or
    // unknown) tag, character, series and other names stay out entirely.
    final namesTakePart = switch (contextRecords[relatedTag]) {
      final record? => !RelatedTagScorer.isGeneral(record.category),
      null => false,
    };
    bool takesPart(TagCatalogRecord? record) =>
        namesTakePart ||
        record == null ||
        RelatedTagScorer.isGeneral(record.category);

    final usable = <(TagCatalogRecord, List<RelatedTag>)>[];
    for (final name in contextNames) {
      final record = contextRecords[name];
      if (record == null || record.postCount <= 0 || !takesPart(record)) {
        continue;
      }
      final rows = await dataSource.getRelatedTags(
        name,
        limit: rowsPerContextTag,
      );
      if (rows.isNotEmpty) usable.add((record, rows));
    }
    // The nearest tag with data leads when the related tag itself has none.
    final shares = RelatedTagScorer.shares([
      for (final (record, _) in usable.skip(1)) record.postCount,
    ]);
    final context = [
      for (final (index, (record, rows)) in usable.indexed)
        RelatedContextTag(
          record: record,
          weight: shares[index],
          related: {for (final row in rows) _normalize(row.tag): row.count},
          complete: rows.length < rowsPerContextTag,
        ),
    ];

    final personal =
        _personalPairs?.call([
          for (final name in contextNames)
            if (takesPart(contextRecords[name])) name,
        ]) ??
        const {};
    final excluded = {...query.existingTags, ...contextNames};
    final pool = <String>{
      for (final tag in context) ...tag.related.keys,
      ...personal.keys,
    }..removeWhere((tag) => tag.isEmpty || excluded.contains(tag));
    if (pool.isEmpty) return const [];

    final records = await _recordsFor(pool);
    final related = RelatedTagScorer.score(
      context: context,
      candidates: {
        for (final name in pool)
          if (records[name] case final record?) name: record,
      },
    );
    final combined = <String, double>{};
    for (final name in pool) {
      // Habits follow the same rule: no names after a general tag.
      if (!takesPart(records[name])) continue;
      final score =
          (related[name] ?? 0) + personalWeight * (personal[name] ?? 0);
      if (score > 0) combined[name] = score;
    }
    if (combined.isEmpty) return const [];
    final best = combined.values.reduce(math.max);

    final candidates = [
      for (final MapEntry(key: name, value: score) in combined.entries)
        CompletionCandidate(
          canonicalTag: name,
          category: records[name]?.category ?? TagCategory.general,
          postCount: records[name]?.postCount ?? 0,
          matchKind: CompletionMatchKind.related,
          sources: const {CompletionSourceKind.cooccurrence},
          relatedScore: score / best,
          cooccurrenceCount: _sharedPosts(context, name),
        ),
    ];
    candidates.sort((left, right) {
      final relevance = (right.relatedScore ?? 0).compareTo(
        left.relatedScore ?? 0,
      );
      if (relevance != 0) return relevance;
      final popularity = right.postCount.compareTo(left.postCount);
      if (popularity != 0) return popularity;
      return left.canonicalTag.compareTo(right.canonicalTag);
    });
    final limit = CompletionResultLimits.isAll(query.limit)
        ? maxResults
        : query.limit.clamp(1, maxResults);
    return candidates.take(limit).toList(growable: false);
  }

  /// Posts shared with the related tag, or with the closest context tag
  /// that has the candidate.
  static int? _sharedPosts(List<RelatedContextTag> context, String name) {
    for (final tag in context) {
      if (tag.related[name] case final count?) return count;
    }
    return null;
  }

  Future<Map<String, TagCatalogRecord>> _recordsFor(
    Iterable<String> names,
  ) async {
    if (_records.length > _maxRememberedRecords) _records.clear();
    final missing = names.where((name) => !_records.containsKey(name)).toList();
    if (missing.isNotEmpty) {
      final found = await _catalog.recordsByCanonicalTag(missing);
      for (final name in missing) {
        _records[name] = found[name];
      }
    }
    return {
      for (final name in names)
        if (_records[name] case final record?) name: record,
    };
  }

  static String _normalize(String tag) =>
      tag.trim().toLowerCase().replaceAll(' ', '_');
}
