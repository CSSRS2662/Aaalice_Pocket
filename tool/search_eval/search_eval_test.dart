// Evaluates the bundled catalog, lexical index and optional E5 worker.
//
//   flutter test tool/search_eval/search_eval_test.dart
//
// The first run builds the lexical index into tool/.tmp/search-eval/ (later
// runs reuse it); the report is written next to it. This is a development
// tool on the full data set, hence its own time limit.
@Timeout(Duration(minutes: 6))
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/autocomplete/ame_zh_lexicon.dart';
import 'package:nai_launcher/core/autocomplete/autocomplete_settings.dart';
import 'package:nai_launcher/core/autocomplete/completion_models.dart';
import 'package:nai_launcher/core/autocomplete/completion_ranker.dart';
import 'package:nai_launcher/core/autocomplete/e5_search_worker.dart';
import 'package:nai_launcher/core/autocomplete/lexical/lexical_enhancement_source.dart';
import 'package:nai_launcher/core/autocomplete/lexical/lexical_index_builder.dart';
import 'package:nai_launcher/core/autocomplete/lexical/lexical_search_index.dart';
import 'package:nai_launcher/core/autocomplete/lexical/search_lexicon.dart';
import 'package:nai_launcher/core/autocomplete/tag_catalog_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _catalogPath = 'assets/databases/tag_catalog.db';
const _outputDirectory = 'tool/.tmp/search-eval';
const _window = 20;

CompletionQuery _query(String token) => CompletionQuery(
  fullText: token,
  cursorPosition: token.length,
  token: token,
  replacementRange: TextReplacementRange(start: 0, end: token.length),
  existingTags: const {},
  limit: 20,
  locale: 'zh',
);

int? _rank(List<CompletionCandidate> rows, List<String> expected) {
  for (var i = 0; i < rows.length; i++) {
    if (expected.contains(rows[i].canonicalTag)) return i + 1;
  }
  return null;
}

void main() {
  test('真实目录检索评测', () async {
    sqfliteFfiInit();
    final catalogFile = File(_catalogPath);
    final header = catalogFile.openSync()..setPositionSync(0);
    final magic = utf8.decode(header.readSync(15), allowMalformed: true);
    header.closeSync();
    expect(magic, 'SQLite format 3', reason: 'run git lfs pull first');

    final pinyinGz = File(
      'assets/search_lexicon/hanzi_pinyin.json.gz',
    ).readAsBytesSync();
    final wordsGz = File(
      'assets/search_lexicon/zh_en_lexicon.json.gz',
    ).readAsBytesSync();
    final ameGz = File(AmeZhLexicon.assetKey).readAsBytesSync();
    final pocketGz = File(AmeZhLexicon.pocketAssetKey).readAsBytesSync();
    final lexicon = SearchLexicon.decode(
      pinyinGz: pinyinGz,
      crossLingualGz: wordsGz,
    );

    // sqflite resolves relative paths against its own directory.
    final catalogPath = catalogFile.absolute.path;
    final outputDirectory = Directory(_outputDirectory).absolute.path;
    final indexName =
        Platform.environment['POCKET_SEARCH_EVAL_INDEX'] ?? 'lexical_index';
    final indexPath = '$outputDirectory/$indexName.db';
    final catalogDb = await databaseFactoryFfi.openDatabase(
      catalogPath,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
    final catalog = TagCatalogRepository(database: catalogDb);
    final ame = AmeZhLexicon(
      loadBytes: () async => Uint8List.fromList(ameGz),
      decode: (bytes) async => AmeZhLexiconIndex.decodeAll([bytes, pocketGz]),
    );
    final stopwatch = Stopwatch()..start();
    final index = LexicalSearchIndex(
      databaseFactory: databaseFactoryFfi,
      build: buildLexicalIndex,
      resolveSources: () async => LexicalIndexSources(
        indexPath: indexPath,
        catalogPath: catalogPath,
        catalogVersion: catalogFile.lengthSync().toString(),
        ameLexiconGz: ameGz,
        pocketLexiconGz: pocketGz,
        pinyinGz: pinyinGz,
        crossLingualGz: wordsGz,
      ),
    );
    expect(await index.ready(), isNotNull);
    final indexMs = stopwatch.elapsedMilliseconds;
    final lexicalRss = ProcessInfo.currentRss;
    final useE5 = Platform.environment['POCKET_SEARCH_EVAL_E5'] == '1';
    final semantic = useE5 ? await _startE5() : null;
    if (semantic != null) addTearDown(() => semantic.send(null));
    final enhancements = LexicalEnhancementSource(
      index: index,
      lexicon: () async => lexicon,
      catalog: catalog,
      settings: () => const AutocompleteSettings(),
    );

    final hard = Platform.environment['POCKET_SEARCH_EVAL_DATASET'] == 'hard';
    final legacyLimits =
        Platform.environment['POCKET_SEARCH_EVAL_LEGACY'] == '1';
    final golden = _loadQueries(hard: hard);
    final results = <Map<String, Object?>>[];
    for (final item in golden) {
      final token = item['query'] as String;
      final expected = (item['expect'] as List).cast<String>();
      final query = _query(token);
      final poolQuery = legacyLimits ? query : query.copyWith(limit: 60);
      final timer = Stopwatch()..start();
      final primary = CompletionRanker.mergeAndSort([
        ...await catalog.search(poolQuery),
        ...await catalog.searchTranslations(poolQuery),
        ...await ame.search(poolQuery),
      ], query: poolQuery);
      final supplement = await enhancements.supplement(query, primary);
      final lexical = CompletionRanker.mergeAndSort([
        ...primary,
        ...supplement,
      ], query: query);
      final lexicalUs = timer.elapsedMicroseconds;
      final strong = primary
          .where(
            (row) =>
                row.matchKind == CompletionMatchKind.chineseExact ||
                row.matchKind == CompletionMatchKind.chinesePrefix,
          )
          .take(8)
          .length;
      final meaning =
          semantic != null &&
              query.isChinese &&
              query.token.trim().length >= 2 &&
              (legacyLimits || strong < 8)
          ? await _searchE5(
              semantic,
              legacyLimits ? query : query.copyWith(limit: 50),
            )
          : const <CompletionCandidate>[];
      final merged = CompletionRanker.mergeAndSort([
        if (legacyLimits) ...lexical else ...[...primary, ...supplement],
        ...meaning,
      ], query: query);
      final pool = [...primary, ...supplement, ...meaning];
      final excluded = ((item['exclude'] as List?) ?? []).cast<String>();
      final semanticRank = _rank(meaning, expected);
      results.add({
        'query': token,
        'expect': expected,
        'via': item['via'],
        'literalRank': _rank(primary.take(query.limit).toList(), expected),
        'lexicalRank': _rank(lexical, expected),
        'rank': _rank(merged, expected),
        'recalled': _rank(pool, expected) != null,
        'e5Rank': semanticRank,
        'e5Best': meaning.isEmpty ? null : meaning.first.semanticScore,
        'e5Expected': semanticRank == null
            ? null
            : meaning[semanticRank - 1].semanticScore,
        'conflictRank': _rank(merged, excluded),
        'e5ConflictRank': _rank(meaning, excluded),
        'top5': merged.take(5).map((row) => row.canonicalTag).toList(),
        'evidence': [
          for (final row in pool.where(
            (row) => expected.contains(row.canonicalTag),
          ))
            {
              'kind': row.matchKind.name,
              'quality': row.matchQuality,
              'hint': row.matchHint,
            },
        ],
        'lexicalUs': lexicalUs,
        'totalUs': timer.elapsedMicroseconds,
      });
    }
    final summary = {
      'cases': results.length,
      'dataset': hard ? 'hard' : 'golden',
      'e5': useE5,
      'legacyLimits': legacyLimits,
      'indexReadyMs': indexMs,
      'indexBytes': File(indexPath).lengthSync(),
      'rssBeforeE5': lexicalRss,
      'rssAfterQueries': ProcessInfo.currentRss,
      'peakRss': ProcessInfo.maxRss,
      'lexicalP50Us': _percentile(results, 'lexicalUs', .5),
      'lexicalP95Us': _percentile(results, 'lexicalUs', .95),
      'totalP50Us': _percentile(results, 'totalUs', .5),
      'totalP95Us': _percentile(results, 'totalUs', .95),
      'recall20':
          results.where((row) => _within(row['rank'], _window)).length /
          results.length,
      'top5':
          results.where((row) => _within(row['rank'], 5)).length /
          results.length,
      'mrr10':
          results.fold<double>(0, (sum, row) {
            final rank = row['rank'] as int?;
            return sum + (rank != null && rank <= 10 ? 1 / rank : 0);
          }) /
          results.length,
    };
    Directory(_outputDirectory).createSync(recursive: true);
    final run = Platform.environment['POCKET_SEARCH_EVAL_RUN'] ?? 'report';
    File('$_outputDirectory/$run.json').writeAsStringSync(
      const JsonEncoder.withIndent(
        '  ',
      ).convert({'summary': summary, 'results': results}),
    );
    // ignore: avoid_print
    print(jsonEncode(summary));

    await index.dispose();
    await catalogDb.close();
  });
}

List<Map> _loadQueries({required bool hard}) {
  if (!hard) {
    final golden =
        jsonDecode(
              File('tool/search_eval/golden_queries.json').readAsStringSync(),
            )
            as Map;
    return (golden['queries'] as List).cast<Map>();
  }
  final scenarios =
      jsonDecode(
            File(
              'tool/semantic_search/semantic_paraphrase_hard_cases.json',
            ).readAsStringSync(),
          )
          as List;
  return [
    for (final scenario in scenarios.cast<Map>())
      for (final query in (scenario['queries'] as List).cast<String>())
        {
          'query': query,
          'expect': [scenario['target']],
          'exclude': [scenario['conflict']],
          'via': scenario['type'],
        },
  ];
}

bool _within(Object? rank, int limit) => rank is int && rank <= limit;

int _percentile(List<Map<String, Object?>> rows, String key, double fraction) {
  final values = rows.map((row) => row[key] as int).toList()..sort();
  return values[(values.length * fraction).ceil() - 1];
}

Future<SendPort> _startE5() async {
  final runtime = Platform.environment['POCKET_SEARCH_EVAL_ORT'];
  if (runtime != null) DynamicLibrary.open(runtime).lookup('OrtGetApiBase');
  final ready = ReceivePort();
  final isolate = await Isolate.spawn(e5SearchWorker, (
    ready.sendPort,
    Directory('assets/semantic_search').absolute.path,
  ));
  addTearDown(isolate.kill);
  try {
    final message = await ready.first.timeout(const Duration(seconds: 90));
    if (message is SendPort) return message;
    throw StateError('E5 benchmark initialization failed: $message');
  } finally {
    ready.close();
  }
}

Future<List<CompletionCandidate>> _searchE5(
  SendPort port,
  CompletionQuery query,
) async {
  final reply = ReceivePort();
  try {
    port.send([reply.sendPort, query.token, query.limit]);
    final message = await reply.first.timeout(const Duration(seconds: 30));
    if (message is! List) {
      throw StateError('E5 benchmark query failed: $message');
    }
    return [
      for (final row in message.cast<List>())
        CompletionCandidate(
          canonicalTag: row[0] as String,
          category: TagCategory.general,
          postCount: row[1] as int,
          matchKind: CompletionMatchKind.fullText,
          sources: const {CompletionSourceKind.base},
          semanticScore: row[3] as double,
        ),
    ];
  } finally {
    reply.close();
  }
}
