import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/autocomplete/autocomplete_settings.dart';
import 'package:nai_launcher/core/autocomplete/completion_models.dart';
import 'package:nai_launcher/core/autocomplete/completion_ranker.dart';
import 'package:nai_launcher/core/autocomplete/lexical/completion_ranking_signals.dart';
import 'package:nai_launcher/core/autocomplete/lexical/lexical_enhancement_source.dart';
import 'package:nai_launcher/core/autocomplete/lexical/lexical_index_builder.dart';
import 'package:nai_launcher/core/autocomplete/lexical/lexical_search_index.dart';
import 'package:nai_launcher/core/autocomplete/lexical/search_lexicon.dart';
import 'package:nai_launcher/core/autocomplete/lexical/tag_usage_history.dart';
import 'package:nai_launcher/core/autocomplete/tag_catalog_repository.dart';
import 'package:nai_launcher/core/storage/local_storage_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _tags = <(String, int)>[
  ('shirt', 900000),
  ('white_shirt', 400000),
  ('shirt_tucked_in', 20000),
  ('city', 50000),
  ('hair_flip', 30000),
  ('chair', 200000),
  ('sitting', 1000000),
  ('sitting_on_chair', 50000),
  ('sitting_on_office_chair', 3000),
  ('twintails', 20),
  ('pince-nez', 4),
  ('seated_rest', 15),
  ('holding_hairbrush', 3),
];

// AME rows: tag, category, posts, label, aliases.
const _ame = <List<Object>>[
  ['shirt', 0, 900000, '衬衫', <String>[]],
  ['white_shirt', 0, 400000, '白衬衫', <String>[]],
  ['shirt_tucked_in', 0, 20000, '衬衫塞进裤腰', <String>[]],
  ['city', 0, 50000, '城市', <String>[]],
  [
    'hair_flip',
    0,
    30000,
    '拨头发',
    <String>['撩头发'],
  ],
  ['chair', 0, 200000, '椅子', <String>[]],
  ['twintails', 0, 20, '双马尾', <String>[]],
];

CompletionQuery _query(String token, {TagCategory? category}) =>
    CompletionQuery(
      fullText: token,
      cursorPosition: token.length,
      token: token,
      replacementRange: TextReplacementRange(start: 0, end: token.length),
      existingTags: const {},
      limit: 20,
      locale: 'zh',
      categoryFilter: category,
    );

class _MemoryStorage extends Fake implements LocalStorageService {
  final values = <String, Object?>{};

  @override
  T? getSetting<T>(String key, {T? defaultValue}) =>
      (values[key] as T?) ?? defaultValue;

  @override
  Future<void> setSetting<T>(String key, T value) async => values[key] = value;

  @override
  Future<void> deleteSetting(String key) async => values.remove(key);
}

void main() {
  late Directory directory;
  late LexicalSearchIndex index;
  late LexicalIndexSources sources;
  late SearchLexicon lexicon;
  late TagCatalogRepository catalog;
  var settings = const AutocompleteSettings();

  LexicalEnhancementSource source() => LexicalEnhancementSource(
    index: index,
    lexicon: () async => lexicon,
    catalog: catalog,
    settings: () => settings,
  );

  setUpAll(() async {
    sqfliteFfiInit();
    directory = Directory.systemTemp.createTempSync('lexical_index_test');
    final catalogPath = '${directory.path}/catalog.db';
    final db = await databaseFactoryFfi.openDatabase(catalogPath);
    await db.execute(
      'CREATE TABLE tags(id INTEGER PRIMARY KEY, name TEXT, category INTEGER, post_count INTEGER)',
    );
    await db.execute(
      'CREATE TABLE zh_translations(tag TEXT, zh_cn TEXT, mode TEXT)',
    );
    await db.execute('CREATE TABLE aliases(tag_id INTEGER, alias TEXT)');
    await db.execute(
      'CREATE VIRTUAL TABLE tag_search USING fts5('
      'term, search_key, tag_id UNINDEXED, kind UNINDEXED)',
    );
    for (final (name, posts) in _tags) {
      final id = await db.insert('tags', {
        'name': name,
        'category': 0,
        'post_count': posts,
      });
      await db.insert('tag_search', {
        'term': name,
        'search_key': name,
        'tag_id': id,
        'kind': 0,
      });
      if (name == 'seated_rest') {
        await db.insert('tag_search', {
          'term': 'sitting_on_bench',
          'search_key': 'sitting_on_bench',
          'tag_id': id,
          'kind': 1,
        });
      }
    }
    await db.close();

    final pinyinGz = File(
      'assets/search_lexicon/hanzi_pinyin.json.gz',
    ).readAsBytesSync();
    final wordsGz = File(
      'assets/search_lexicon/zh_en_lexicon.json.gz',
    ).readAsBytesSync();
    lexicon = SearchLexicon.decode(pinyinGz: pinyinGz, crossLingualGz: wordsGz);
    final ameGz = Uint8List.fromList(
      gzip.encode(utf8.encode(jsonEncode({'entries': _ame}))),
    );
    sources = LexicalIndexSources(
      indexPath: '${directory.path}/index/lexical_index.db',
      catalogPath: catalogPath,
      catalogVersion: 'fixture',
      ameLexiconGz: ameGz,
      pocketLexiconGz: Uint8List.fromList(
        gzip.encode(
          utf8.encode(
            jsonEncode({
              'entries': [
                ['night_sky', 0, 55380, '夜空', <String>[]],
              ],
            }),
          ),
        ),
      ),
      pinyinGz: pinyinGz,
      crossLingualGz: wordsGz,
    );
    index = LexicalSearchIndex(
      databaseFactory: databaseFactoryFfi,
      build: buildLexicalIndex,
      resolveSources: () async => sources,
    );
    expect(await index.ready(), isNotNull);
    catalog = TagCatalogRepository(
      database: await databaseFactoryFfi.openDatabase(
        catalogPath,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      ),
    );
  });

  tearDownAll(() async {
    await index.dispose();
    await catalog.dispose();
    directory.deleteSync(recursive: true);
  });

  setUp(() {
    settings = const AutocompleteSettings();
  });

  test('本项目补充词库的译名同样建入拼音索引并参与指纹', () async {
    final rows = await source().supplement(_query('yekong'), const []);
    expect(rows.first.canonicalTag, 'night_sky');
    expect(rows.first.matchKind, CompletionMatchKind.pinyin);
    expect(rows.first.matchHint, '夜空');

    final withoutPocket = LexicalIndexSources(
      indexPath: sources.indexPath,
      catalogPath: sources.catalogPath,
      catalogVersion: sources.catalogVersion,
      ameLexiconGz: sources.ameLexiconGz,
      pinyinGz: sources.pinyinGz,
      crossLingualGz: sources.crossLingualGz,
    );
    expect(withoutPocket.fingerprint, isNot(sources.fingerprint));
  });

  test('同音中文命中衬衫，以读音开头的标签排在后面', () async {
    final rows = await source().supplement(_query('陈山'), const []);
    final shirt = rows.firstWhere((row) => row.canonicalTag == 'shirt');
    expect(shirt.matchKind, CompletionMatchKind.homophone);
    expect(shirt.matchHint, '衬衫');
    expect(shirt.matchQuality, 1);
    final tucked = rows.firstWhere(
      (row) => row.canonicalTag == 'shirt_tucked_in',
    );
    expect(tucked.matchQuality, lessThan(shirt.matchQuality));
    // Mid-label homophones are left out.
    expect(rows.map((row) => row.canonicalTag), isNot(contains('white_shirt')));
  });

  test('模糊音只在开启的音对下命中', () async {
    var rows = await source().supplement(_query('城山'), const []);
    expect(
      rows.where((row) => row.matchKind == CompletionMatchKind.fuzzyPinyin),
      contains(
        predicate<CompletionCandidate>((r) => r.canonicalTag == 'shirt'),
      ),
    );
    settings = settings.copyWith(fuzzyPinyinRules: const {});
    rows = await source().supplement(_query('城山'), const []);
    expect(rows.map((row) => row.canonicalTag), isNot(contains('shirt')));
  });

  test('自然码双拼、全拼和首字母都能找到衬衫', () async {
    Future<CompletionCandidate> first(String letters) async =>
        (await source().supplement(_query(letters), const [])).first;

    final shuangpin = await first('ifuj');
    expect(shuangpin.canonicalTag, 'shirt');
    expect(shuangpin.matchKind, CompletionMatchKind.shuangpin);

    final pinyin = await first('chenshan');
    expect(pinyin.canonicalTag, 'shirt');
    expect(pinyin.matchKind, CompletionMatchKind.pinyin);

    final initials = await first('cs');
    expect(initials.canonicalTag, 'shirt');
    expect(initials.matchKind, CompletionMatchKind.pinyinInitials);

    settings = settings.copyWith(pinyinZiranmaEnabled: false);
    final withoutZiranma = await source().supplement(_query('ifuj'), const []);
    expect(withoutZiranma, isEmpty);
  });

  test('多字近似匹配按共同字与顺序打分', () async {
    final rows = await source().supplement(_query('拨起头发'), const []);
    final approximate = rows.firstWhere(
      (row) => row.matchKind == CompletionMatchKind.approximate,
    );
    expect(approximate.canonicalTag, 'hair_flip');
    expect(approximate.matchQuality, greaterThan(.85));
  });

  test('二字漏字、多字、错字和相邻调换能召回低频词', () async {
    for (final text in ['双尾', '双马马尾', '双码尾', '双尾马']) {
      final rows = await source().supplement(_query(text), const []);
      expect(
        rows
            .where((row) => row.matchKind == CompletionMatchKind.approximate)
            .map((row) => row.canonicalTag),
        contains('twintails'),
        reason: text,
      );
    }
    expect(await source().supplement(_query('双'), const []), isEmpty);
  });

  test('拆词匹配英文 tag，多余词越少越靠前', () async {
    final rows = await source().supplement(_query('坐在椅子上'), const []);
    final crossLingual = rows
        .where((row) => row.matchKind == CompletionMatchKind.crossLingual)
        .toList();
    expect(crossLingual.map((row) => row.canonicalTag), [
      'sitting_on_chair',
      'sitting_on_office_chair',
    ]);
    expect(crossLingual.first.matchHint, '坐在·椅子');
    expect(crossLingual.first.translation, isNull);
  });

  test('搜索词从英文别名召回，未知概念不会降格为单词命中', () async {
    final rows = await source().supplement(_query('在长椅上坐着'), const []);
    expect(
      rows
          .where((row) => row.matchKind == CompletionMatchKind.crossLingual)
          .map((row) => row.canonicalTag),
      contains('seated_rest'),
    );
    final unknown = await source().supplement(_query('龘椅子'), const []);
    expect(
      unknown.where((row) => row.matchKind == CompletionMatchKind.crossLingual),
      isEmpty,
    );
  });

  test('英文合成词可以通过多个中文概念查到', () async {
    final rows = await source().supplement(_query('手持 头发 刷子'), const []);
    final row = rows.firstWhere(
      (item) => item.canonicalTag == 'holding_hairbrush',
    );
    expect(row.matchKind, CompletionMatchKind.crossLingual);
    expect(row.matchHint, '手持·头发·刷子');
    expect(row.translation, isNull);
  });

  test('能读成拼音的字母不当作英文拼写错误', () async {
    final rows = await source().supplement(_query('chenshan'), const []);
    expect(
      rows.where((row) => row.matchKind == CompletionMatchKind.spellCorrected),
      isEmpty,
    );
  });

  test('没有字面结果时纠正英文拼写', () async {
    final rows = await source().supplement(_query('shrit'), const []);
    final corrected = rows.firstWhere(
      (row) => row.matchKind == CompletionMatchKind.spellCorrected,
    );
    expect(corrected.canonicalTag, 'shirt');
    expect(corrected.matchHint, 'shirt');

    settings = settings.copyWith(spellCorrectionEnabled: false);
    expect(
      (await source().supplement(
        _query('shrit'),
        const [],
      )).where((row) => row.matchKind == CompletionMatchKind.spellCorrected),
      isEmpty,
    );
  });

  test('按完整词组检查候选，低频含连字符标签可以纠错', () async {
    final rows = await source().supplement(_query('pinze-nez'), const []);
    expect(
      rows
          .where((row) => row.matchKind == CompletionMatchKind.spellCorrected)
          .map((row) => row.canonicalTag),
      contains('pince-nez'),
    );
  });

  test('分类筛选与开关生效', () async {
    expect(
      await source().supplement(
        _query('陈山', category: TagCategory.character),
        const [],
      ),
      isEmpty,
    );
    settings = settings.copyWith(
      pinyinSearchEnabled: false,
      approximateMatchEnabled: false,
      crossLingualEnabled: false,
    );
    expect(await source().supplement(_query('陈山'), const []), isEmpty);
  });

  group('排序', () {
    CompletionCandidate row(
      String tag,
      CompletionMatchKind kind, {
      int posts = 100,
      double quality = 0,
    }) => CompletionCandidate(
      canonicalTag: tag,
      category: TagCategory.general,
      postCount: posts,
      matchKind: kind,
      sources: const {CompletionSourceKind.base},
      matchQuality: quality,
    );

    test('保护可靠前缀，使用记录参与同类结果重排', () {
      final sorted = CompletionRanker.mergeAndSort(
        [
          row(
            'homophone_popular',
            CompletionMatchKind.homophone,
            posts: 9000000,
            quality: .8,
          ),
          row('literal', CompletionMatchKind.chinesePrefix),
          row(
            'homophone_used',
            CompletionMatchKind.homophone,
            posts: 10,
            quality: .8,
          ),
          row('initials', CompletionMatchKind.pinyinInitials, quality: 1),
        ],
        query: _query('陈山'),
        boosts: const {'homophone_used': 6000, 'initials': 6000},
      );
      expect(sorted.map((row) => row.canonicalTag), [
        'literal',
        'homophone_used',
        'homophone_popular',
        'initials',
      ]);
    });

    test('高相关语义结果能超过低置信拼音与拆词结果', () {
      final sorted = CompletionRanker.mergeAndSort([
        const CompletionCandidate(
          canonicalTag: 'semantic',
          category: TagCategory.general,
          postCount: 9000000,
          matchKind: CompletionMatchKind.fullText,
          sources: {CompletionSourceKind.base},
          semanticScore: 0.99,
        ),
        row('initials', CompletionMatchKind.pinyinInitials),
        row('split', CompletionMatchKind.crossLingual),
      ], query: _query('坐在椅子上'));
      expect(sorted.map((row) => row.canonicalTag), [
        'semantic',
        'initials',
        'split',
      ]);
    });

    test('同一 tag 合并时保留更好的匹配方式和说明', () {
      final sorted = CompletionRanker.mergeAndSort([
        row('shirt', CompletionMatchKind.approximate, quality: 0.9),
        row('shirt', CompletionMatchKind.homophone, quality: 0.6),
      ], query: _query('陈山'));
      expect(sorted.single.matchKind, CompletionMatchKind.approximate);
      expect(sorted.single.matchQuality, 0.9);
    });
  });

  test('使用记录随次数增长、随时间衰减，可清除', () async {
    var now = DateTime.utc(2026, 10, 1);
    final storage = _MemoryStorage();
    final history = TagUsageHistory(storage, now: () => now);
    await history.record('shirt');
    await history.record('Shirt');
    await history.record('socks');
    expect(history.score('shirt'), greaterThan(history.score('socks')));
    final fresh = history.score('shirt');
    now = now.add(const Duration(days: 45));
    expect(
      TagUsageHistory(storage, now: () => now).score('shirt'),
      closeTo(fresh / 2, 0.001),
    );

    final signals = DefaultCompletionRankingSignals(
      history: history,
      settings: () => const AutocompleteSettings(),
    );
    final boosts = await signals.boosts(_query('s'));
    expect(boosts['shirt'], greaterThan(boosts['socks']!));
    expect(boosts['shirt'], lessThanOrEqualTo(3000));

    await history.clear();
    expect(history.isEmpty, isTrue);
    expect(storage.values, isEmpty);
  });

  test('索引构建失败后同一输入不立即重试', () async {
    var builds = 0;
    final failing = LexicalSearchIndex(
      databaseFactory: databaseFactoryFfi,
      build: (_) async {
        builds++;
        throw StateError('no space');
      },
      resolveSources: () async => LexicalIndexSources(
        indexPath: '${directory.path}/failing/lexical_index.db',
        catalogPath: '${directory.path}/missing.db',
        catalogVersion: 'fixture',
        ameLexiconGz: Uint8List(0),
        pinyinGz: Uint8List(0),
        crossLingualGz: Uint8List(0),
      ),
    );
    expect(await failing.ready(), isNull);
    expect(await failing.ready(), isNull);
    expect(await failing.pinyinMatches('py : (^chen)'), isEmpty);
    expect(builds, 1);
    await failing.dispose();
  });

  test('首次索引构建期间的并发查询共用一次构建', () async {
    final release = Completer<void>();
    var builds = 0;
    final concurrent = LexicalSearchIndex(
      databaseFactory: databaseFactoryFfi,
      build: (_) async {
        builds++;
        await release.future;
        return const {};
      },
      resolveSources: () async => LexicalIndexSources(
        indexPath: '${directory.path}/concurrent/lexical_index.db',
        catalogPath: sources.catalogPath,
        catalogVersion: sources.catalogVersion,
        ameLexiconGz: sources.ameLexiconGz,
        pinyinGz: sources.pinyinGz,
        crossLingualGz: sources.crossLingualGz,
      ),
    );
    addTearDown(() async {
      release.complete();
      await concurrent.dispose();
    });
    await Future.wait([for (var i = 0; i < 5; i++) concurrent.database()]);
    expect(builds, 1);
  });

  test('上下文取光标前最近的 tag', () {
    const query = CompletionQuery(
      fullText: 'shirt, socks, smile, ',
      cursorPosition: 14,
      token: '',
      replacementRange: TextReplacementRange(start: 0, end: 0),
      existingTags: {'shirt', 'socks', 'smile'},
      limit: 20,
      locale: 'zh',
    );
    expect(DefaultCompletionRankingSignals.nearbyTags(query), [
      'socks',
      'shirt',
    ]);
  });
}
