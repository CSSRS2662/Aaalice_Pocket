import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/autocomplete/cooccurrence_completion_source.dart';
import 'package:nai_launcher/core/autocomplete/completion_models.dart';
import 'package:nai_launcher/core/autocomplete/tag_catalog_repository.dart';
import 'package:nai_launcher/core/database/datasources/cooccurrence_data_source.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test(
    'ranks by fit with the related tag, leaving out what is written',
    () async {
      final dataSource = _FakeCooccurrenceDataSource({
        'classroom': const [
          RelatedTag(tag: 'school_uniform', count: 12000),
          RelatedTag(tag: 'solo', count: 3000),
          RelatedTag(tag: 'desk', count: 2000),
          RelatedTag(tag: 'smile', count: 1500),
          RelatedTag(tag: 'highres', count: 2500),
        ],
      });
      final source = CooccurrenceCompletionSource(
        dataSource,
        catalog: _FakeCatalog({
          'classroom': _record('classroom', 60000),
          'school_uniform': _record('school_uniform', 900000),
          'solo': _record('solo', 5000000),
          'desk': _record('desk', 80000),
          'smile': _record('smile', 2000000),
          'highres': _record('highres', 5000000, TagCategory.meta),
        }),
      );

      final results = await source.search(
        _query(relatedTag: 'classroom', existingTags: const {'smile'}),
      );

      // solo shows up less often than chance; meta tags are never offered.
      expect(results.map((candidate) => candidate.canonicalTag), [
        'school_uniform',
        'desk',
      ]);
      expect(results.first.relatedScore, 1.0);
      expect(results.first.cooccurrenceCount, 12000);
      expect(results.first.sources, {CompletionSourceKind.cooccurrence});
      expect(
        dataSource.requestedLimits['classroom'],
        CooccurrenceCompletionSource.rowsPerContextTag,
      );
    },
  );

  test('written context lifts what fits it and drops what conflicts', () async {
    final dataSource = _FakeCooccurrenceDataSource({
      'outdoors': const [
        RelatedTag(tag: 'day', count: 400000),
        RelatedTag(tag: 'tree', count: 200000),
        RelatedTag(tag: 'night_sky', count: 60000),
      ],
      'night': const [
        RelatedTag(tag: 'night_sky', count: 150000),
        RelatedTag(tag: 'tree', count: 40000),
        RelatedTag(tag: 'day', count: 2000),
      ],
    });
    final catalog = _FakeCatalog({
      'outdoors': _record('outdoors', 1000000),
      'night': _record('night', 500000),
      'day': _record('day', 1500000),
      'tree': _record('tree', 800000),
      'night_sky': _record('night_sky', 200000),
    });
    final source = CooccurrenceCompletionSource(dataSource, catalog: catalog);

    final alone = await source.search(_query(relatedTag: 'outdoors'));
    expect(alone.first.canonicalTag, 'day');

    final withNight = await source.search(
      _query(relatedTag: 'outdoors', contextTags: const ['night']),
    );
    final order = withNight.map((candidate) => candidate.canonicalTag).toList();
    expect(order.first, 'night_sky');
    expect(order.indexOf('day'), greaterThan(order.indexOf('tree')));
  });

  test('habits lift a tag and add ones the pack does not know', () async {
    final dataSource = _FakeCooccurrenceDataSource({
      'outdoors': const [
        RelatedTag(tag: 'day', count: 400000),
        RelatedTag(tag: 'tree', count: 200000),
      ],
    });
    final catalog = _FakeCatalog({
      'outdoors': _record('outdoors', 1000000),
      'day': _record('day', 1500000),
      'tree': _record('tree', 800000),
    });
    List<String>? askedContext;
    final withHabits = CooccurrenceCompletionSource(
      dataSource,
      catalog: catalog,
      personalPairs: (context) {
        askedContext = context;
        return const {'tree': 1.0, '淡绿色t恤': 1.0};
      },
    );
    final plain = CooccurrenceCompletionSource(dataSource, catalog: catalog);
    double? scoreOf(List<CompletionCandidate> results, String tag) => results
        .where((candidate) => candidate.canonicalTag == tag)
        .firstOrNull
        ?.relatedScore;

    final query = _query(relatedTag: 'outdoors', contextTags: const ['beach']);
    final before = await plain.search(query);
    final after = await withHabits.search(query);

    expect(askedContext, ['outdoors', 'beach']);
    expect(scoreOf(after, 'tree'), greaterThan(scoreOf(before, 'tree')!));
    final custom = after.singleWhere(
      (candidate) => candidate.canonicalTag == '淡绿色t恤',
    );
    expect(custom.category, TagCategory.general);
    expect(custom.postCount, 0);
    expect(scoreOf(before, '淡绿色t恤'), isNull);
  });

  test('compact database returns stable bidirectional relations', () async {
    sqfliteFfiInit();
    final directory = await Directory.systemTemp.createTemp(
      'cooccurrence_data_source_test_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = File('${directory.path}/cooccurrence-v2.db').path;
    final writer = await databaseFactoryFfi.openDatabase(path);
    await writer.execute('''
        CREATE TABLE metadata(key TEXT PRIMARY KEY, value TEXT NOT NULL);
        CREATE TABLE tags(
          id INTEGER PRIMARY KEY,
          name TEXT NOT NULL COLLATE NOCASE UNIQUE
        );
        CREATE TABLE edges(
          source_tag_id INTEGER NOT NULL,
          target_tag_id INTEGER NOT NULL,
          count INTEGER NOT NULL CHECK(count > 0),
          PRIMARY KEY(source_tag_id, count DESC, target_tag_id)
        ) WITHOUT ROWID;
        INSERT INTO metadata VALUES ('source_pair_count', '2');
        INSERT INTO tags VALUES (1, 'alpha'), (2, 'beta'), (3, 'gamma');
        INSERT INTO edges VALUES
          (1, 2, 50), (2, 1, 50), (1, 3, 10), (3, 1, 10);
      ''');
    await writer.close();
    final database = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
    final dataSource = CooccurrenceDataSource(database: database);
    addTearDown(dataSource.dispose);

    final alpha = await dataSource.getRelatedTags('ALPHA', limit: 10);
    expect(alpha.map((relation) => relation.tag), ['beta', 'gamma']);
    expect(alpha.map((relation) => relation.count), [50, 10]);
    expect(
      (await dataSource.getRelatedTags('beta', limit: 10)).single.tag,
      'alpha',
    );
    expect(await dataSource.getRelatedTagCount('alpha'), 2);
    expect(await dataSource.getCount(), 2);
    expect(
      await dataSource.calculateCooccurrenceScore('alpha', 'beta'),
      closeTo(50 / 60, 0.0001),
    );
  });

  test(
    'awaits the managed datasource instead of dropping related tags during startup',
    () async {
      final completer = Future<CooccurrenceDataSource>.delayed(
        const Duration(milliseconds: 1),
        () => _FakeCooccurrenceDataSource({
          '1girl': const [RelatedTag(tag: 'smile', count: 400)],
        }),
      );
      final source = CooccurrenceCompletionSource.withLoader(
        () => completer,
        catalog: _FakeCatalog({
          '1girl': const TagCatalogRecord(
            canonicalTag: '1girl',
            category: TagCategory.general,
            postCount: 1000,
          ),
          'smile': const TagCatalogRecord(
            canonicalTag: 'smile',
            category: TagCategory.general,
            postCount: 500,
          ),
        }),
      );

      final results = await source.search(
        _query(relatedTag: '1girl', limit: 20),
      );

      expect(results.single.canonicalTag, 'smile');
      expect(results.single.relatedScore, 1.0);
    },
  );
}

TagCatalogRecord _record(
  String tag,
  int postCount, [
  TagCategory category = TagCategory.general,
]) => TagCatalogRecord(
  canonicalTag: tag,
  category: category,
  postCount: postCount,
);

CompletionQuery _query({
  String relatedTag = 'blue_archive',
  List<String> contextTags = const [],
  int limit = CompletionResultLimits.all,
  Set<String> existingTags = const {},
}) => CompletionQuery(
  fullText: '$relatedTag, ',
  cursorPosition: relatedTag.length + 2,
  token: '',
  replacementRange: TextReplacementRange(
    start: relatedTag.length + 2,
    end: relatedTag.length + 2,
  ),
  existingTags: existingTags,
  limit: limit,
  locale: 'en',
  relatedTag: relatedTag,
  contextTags: contextTags,
);

class _FakeCooccurrenceDataSource extends CooccurrenceDataSource {
  _FakeCooccurrenceDataSource(this.rows);

  final Map<String, List<RelatedTag>> rows;
  final Map<String, int> requestedLimits = {};

  @override
  Future<List<RelatedTag>> getRelatedTags(
    String tag, {
    int limit = 20,
    int minCount = 1,
  }) async {
    requestedLimits[tag] = limit;
    return (rows[tag] ?? const []).take(limit).toList(growable: false);
  }
}

class _FakeCatalog extends TagCatalogRepository {
  _FakeCatalog(this.records);

  final Map<String, TagCatalogRecord> records;

  @override
  Future<Map<String, TagCatalogRecord>> recordsByCanonicalTag(
    Iterable<String> canonicalTags,
  ) async => {
    for (final tag in canonicalTags)
      if (records[tag] case final record?) tag: record,
  };
}
