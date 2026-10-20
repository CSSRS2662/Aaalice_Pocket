import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/autocomplete/completion_models.dart';
import 'package:nai_launcher/core/autocomplete/fast_tag_service.dart';
import 'package:nai_launcher/core/autocomplete/tag_catalog_repository.dart';
import 'package:nai_launcher/core/autocomplete/tag_rename_folder.dart';
import 'package:nai_launcher/core/autocomplete/zh_dictionary_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database database;
  late TagCatalogRepository catalog;
  late TagRenameFolder folder;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await database.execute('''
      CREATE TABLE tags(id INTEGER PRIMARY KEY, name TEXT, category INTEGER, post_count INTEGER);
      CREATE TABLE aliases(id INTEGER PRIMARY KEY, tag_id INTEGER, alias TEXT);
      CREATE VIRTUAL TABLE tag_search USING fts5(term, search_key, tag_id UNINDEXED, kind UNINDEXED);
      CREATE TABLE zh_translations(tag TEXT PRIMARY KEY, zh_cn TEXT NOT NULL, mode INTEGER NOT NULL);
      INSERT INTO tags VALUES (1, 'black_footwear', 0, 287208);
      INSERT INTO tags VALUES (2, 'black_shoes', 7, 4409);
      INSERT INTO tags VALUES (3, 'serafuku', 0, 315787);
      INSERT INTO tags VALUES (4, 'school_uniform', 0, 791599);
      INSERT INTO tags VALUES (5, 'one_eye_closed', 0, 431971);
      INSERT INTO tags VALUES (6, 'breasts', 0, 900);
      INSERT INTO tags VALUES (7, 'breasts_out', 0, 800);
      INSERT INTO tags VALUES (8, 'wolf', 7, 500);
      INSERT INTO tags VALUES (9, 'canine', 7, 900);
      INSERT INTO aliases VALUES (1, 1, 'black_shoes');
      INSERT INTO aliases VALUES (2, 1, 'black_boots');
      INSERT INTO aliases VALUES (3, 3, 'school_uniform');
      INSERT INTO aliases VALUES (4, 5, 'wink');
      INSERT INTO aliases VALUES (5, 6, 'breasts_outside');
      INSERT INTO aliases VALUES (6, 7, 'breasts_outside');
      INSERT INTO aliases VALUES (7, 9, 'wolf');
      INSERT INTO tag_search VALUES ('black_footwear', 'black footwear', 1, 0);
      INSERT INTO tag_search VALUES ('black_shoes', 'black shoes', 2, 0);
      INSERT INTO zh_translations VALUES ('black_shoes', '黑色鞋子', 0);
    ''');
    catalog = TagCatalogRepository(database: database);
    folder = TagRenameFolder(catalog.renamedTags);
    await folder.ready();
  });

  tearDown(() => catalog.dispose());

  test(
    'only names Danbooru no longer has fold, into a single Danbooru tag',
    () async {
      final renamed = await catalog.renamedTags();
      expect(renamed.keys.toSet(), {'black_shoes', 'black_boots', 'wink'});
      expect(renamed['black_shoes']!.canonicalTag, 'black_footwear');
      expect(renamed['black_shoes']!.postCount, 287208);
      expect(renamed['wink']!.canonicalTag, 'one_eye_closed');
      // school_uniform is a live Danbooru tag, breasts_outside points at two
      // tags and wolf → canine is an e621 alias between e621 tags.
      expect(renamed, isNot(contains('school_uniform')));
      expect(renamed, isNot(contains('breasts_outside')));
      expect(renamed, isNot(contains('wolf')));
    },
  );

  test('rows pass through untouched until the rename map has loaded', () async {
    final pending = TagRenameFolder(
      () => Completer<Map<String, TagCatalogRecord>>().future,
    );
    final rows = [_row('black_shoes', CompletionMatchKind.chineseExact)];
    expect(await pending.fold(rows), same(rows));
    expect(await pending.formerNames(['black_footwear']), isEmpty);
  });

  test('a folded row keeps how it matched and names the old tag', () async {
    final rows = await folder.fold([
      _row(
        'black_shoes',
        CompletionMatchKind.chineseExact,
        translation: '黑色鞋子',
      ),
      _row('serafuku', CompletionMatchKind.chinesePrefix),
    ]);

    expect(rows.first.canonicalTag, 'black_footwear');
    expect(rows.first.postCount, 287208);
    expect(rows.first.matchKind, CompletionMatchKind.chineseExact);
    expect(rows.first.matchedAlias, 'black_shoes');
    expect(rows.first.translation, isNull, reason: '新名的译名由统一解析决定');
    expect(rows.last.canonicalTag, 'serafuku');
    expect(await folder.formerNames(['black_footwear', 'serafuku']), {
      'black_footwear': ['black_boots', 'black_shoes'],
    });
  });

  test(
    'search merges the old name into the current tag; a missing label is borrowed',
    () async {
      final service = FastTagService(
        catalog: catalog,
        dictionary: _FakeDictionary(const {}),
        renames: folder,
      );

      final rows = await service.search(_query('black'));
      expect(rows.map((row) => row.canonicalTag), ['black_footwear']);
      final chinese = await service.search(_query('黑色鞋子'));
      expect(chinese.single.canonicalTag, 'black_footwear');
      expect(chinese.single.matchKind, CompletionMatchKind.chineseExact);
      expect(
        await service.resolve(['black_footwear', 'serafuku'], locale: 'zh-CN'),
        {'black_footwear': '黑色鞋子'},
      );
    },
  );
}

CompletionCandidate _row(
  String tag,
  CompletionMatchKind kind, {
  String? translation,
}) => CompletionCandidate(
  canonicalTag: tag,
  category: TagCategory.general,
  postCount: 10,
  matchKind: kind,
  sources: const {CompletionSourceKind.zhDictionary},
  translation: translation,
);

CompletionQuery _query(String token) => CompletionQuery(
  fullText: token,
  cursorPosition: token.length,
  token: token,
  replacementRange: TextReplacementRange(start: 0, end: token.length),
  existingTags: const {},
  limit: 20,
  locale: 'zh-CN',
);

class _FakeDictionary extends ZhDictionaryService {
  _FakeDictionary(this.values);

  final Map<String, String> values;

  @override
  Future<List<CompletionCandidate>> search(CompletionQuery query) async =>
      const [];

  @override
  Future<Map<String, String>> resolve(
    List<String> canonicalTags, {
    required String locale,
  }) async => {
    for (final tag in canonicalTags)
      if (values[tag] case final value?) tag: value,
  };
}
