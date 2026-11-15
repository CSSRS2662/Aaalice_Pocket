import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/autocomplete/autocomplete_cache_database.dart';
import 'package:nai_launcher/core/autocomplete/completion_models.dart';
import 'package:nai_launcher/core/autocomplete/danbooru_completion_source.dart';

void main() {
  testWidgets('online sources keep separate typed and related cache entries', (
    tester,
  ) async {
    final cache = _Cache();
    final adapter = _Adapter();
    final dio = Dio()..httpClientAdapter = adapter;
    addTearDown(dio.close);
    for (final (provider, tag) in [
      (OnlineTagProvider.danbooru, 'danbooru_tag'),
      (OnlineTagProvider.aibooru, 'aibooru_tag'),
    ]) {
      final source = DanbooruCompletionSource(
        provider: provider,
        dio: dio,
        cache: cache,
      );
      addTearDown(source.dispose);
      final typed = source.search(_query('skirt'));
      await _flush(tester);
      adapter.requests.last.complete(_tags(tag));
      await _flush(tester);
      expect((await typed).single.canonicalTag, tag);

      final related = source.relatedTags('skirt');
      await tester.pump(const Duration(milliseconds: 251));
      await _flush(tester);
      adapter.requests.last.complete(
        ResponseBody.fromString(
          jsonEncode({
            'related_tags': [
              {
                'tag': {'name': tag, 'category': 0, 'post_count': 100},
                'jaccard_similarity': 0.2,
                'frequency': 0.8,
              },
            ],
          }),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        ),
      );
      await _flush(tester);
      final row = (await related).single;
      expect(row.canonicalTag, tag);
      expect(row.relatedScore, 0.2);
    }
    expect(adapter.requests, hasLength(4));
    expect(
      cache.values.keys,
      unorderedEquals([
        'tags:skirt:all:20',
        'related:v3:skirt:20',
        'aibooru:tags:skirt:all:20',
        'aibooru:related:v3:skirt:20',
      ]),
    );
  });

  testWidgets('a late cache lookup cannot cancel the newer input', (
    tester,
  ) async {
    final cache = _Cache()..deferReads = true;
    final adapter = _Adapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final source = DanbooruCompletionSource(dio: dio, cache: cache);
    addTearDown(source.dispose);
    addTearDown(dio.close);

    final old = source.search(_query('blue'));
    final current = source.search(_query('skirt'));
    cache.reads[1].complete(null);
    await _flush(tester);
    expect(
      adapter.requests.single.options.queryParameters['search[name_matches]'],
      '*skirt*',
    );

    cache.reads[0].complete(null);
    await _flush(tester);
    expect(adapter.requests.single.cancelled, isFalse);
    adapter.requests.single.complete(_tags('skirt'));
    await _flush(tester);
    expect((await current).single.canonicalTag, 'skirt');
    expect(await old, isEmpty);
    await tester.pump(const Duration(seconds: 1));
    expect(adapter.requests, hasLength(1));
  });

  testWidgets('replacing input cancels its pending cache lookup', (
    tester,
  ) async {
    final cache = _Cache()..deferReads = true;
    final adapter = _Adapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final source = DanbooruCompletionSource(dio: dio, cache: cache);
    addTearDown(source.dispose);
    addTearDown(dio.close);

    var finished = false;
    final pending = source.search(_query('blue')).then((rows) {
      finished = true;
      return rows;
    });
    source.cancelPending();
    cache.reads.single.complete(null);
    await _flush(tester);
    expect(adapter.requests, isEmpty);
    expect(finished, isTrue);
    expect(await pending, isEmpty);
  });

  for (final status in [429, 503]) {
    testWidgets('$status respects a thirty-second Retry-After across queries', (
      tester,
    ) async {
      final adapter = _Adapter();
      final dio = Dio()..httpClientAdapter = adapter;
      final source = DanbooruCompletionSource(dio: dio, cache: _Cache());
      addTearDown(source.dispose);
      addTearDown(dio.close);

      var finished = false;
      final pending = source.search(_query('skirt')).then((rows) {
        finished = true;
        return rows;
      });
      await _flush(tester);
      adapter.requests.single.complete(
        ResponseBody.fromString(
          'maintenance',
          status,
          headers: {
            'retry-after': ['30'],
          },
        ),
      );
      await _flush(tester);
      await tester.pump(const Duration(seconds: 6));
      expect(adapter.requests, hasLength(1));
      expect(finished, isTrue);
      expect(await pending, isEmpty);
      expect(source.lastError?.kind, CompletionRemoteErrorKind.http);
      expect(source.lastError?.statusCode, status);
      expect(source.lastError?.waitSeconds, 30);

      final other = source.relatedTags('blue_eyes');
      await _flush(tester);
      expect(await other, isEmpty);
      expect(adapter.requests, hasLength(1));
      expect(source.lastError?.kind, CompletionRemoteErrorKind.cooldown);
      expect(source.lastError?.waitSeconds, greaterThan(0));
    });
  }

  testWidgets('related lookup ignores a cache read cancelled by typed input', (
    tester,
  ) async {
    final cache = _Cache()..deferReads = true;
    final adapter = _Adapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final source = DanbooruCompletionSource(dio: dio, cache: cache);
    addTearDown(source.dispose);
    addTearDown(dio.close);

    final old = source.relatedTags('blue_eyes');
    final current = source.search(_query('skirt'));
    cache.reads[1].complete(null);
    await _flush(tester);
    cache.reads[0].complete(null);
    await _flush(tester);
    expect(adapter.requests.single.cancelled, isFalse);
    adapter.requests.single.complete(_tags('skirt'));
    await _flush(tester);
    expect((await current).single.canonicalTag, 'skirt');
    expect(await old, isEmpty);
    expect(adapter.requests, hasLength(1));
  });

  testWidgets('HTTP-date Retry-After pauses both related and typed requests', (
    tester,
  ) async {
    final adapter = _Adapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final source = DanbooruCompletionSource(dio: dio, cache: _Cache());
    addTearDown(source.dispose);
    addTearDown(dio.close);

    final pending = source.relatedTags('skirt');
    await _flush(tester);
    adapter.requests.single.complete(
      ResponseBody.fromString(
        'maintenance',
        503,
        headers: {
          'retry-after': [
            HttpDate.format(DateTime.now().add(const Duration(minutes: 1))),
          ],
        },
      ),
    );
    await _flush(tester);
    expect(await pending, isEmpty);
    expect(source.circuitOpen, isTrue);
    final next = source.search(_query('blue'));
    await _flush(tester);
    expect(await next, isEmpty);
    expect(adapter.requests, hasLength(1));
  });

  testWidgets('a transient 503 without Retry-After retries once and recovers', (
    tester,
  ) async {
    final adapter = _Adapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final source = DanbooruCompletionSource(dio: dio, cache: _Cache());
    addTearDown(source.dispose);
    addTearDown(dio.close);

    final pending = source.search(_query('skirt'));
    await _flush(tester);
    adapter.requests.single.complete(ResponseBody.fromString('failed', 503));
    await _flush(tester);
    await tester.pump(const Duration(milliseconds: 999));
    await _flush(tester);
    expect(adapter.requests, hasLength(2));
    adapter.requests.last.complete(_tags('skirt'));
    await _flush(tester);
    expect((await pending).single.canonicalTag, 'skirt');
    expect(source.lastError, isNull);
    expect(source.circuitOpen, isFalse);
  });

  testWidgets('cancelling during a retry does not send another request', (
    tester,
  ) async {
    final adapter = _Adapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final source = DanbooruCompletionSource(dio: dio, cache: _Cache());
    addTearDown(source.dispose);
    addTearDown(dio.close);

    final pending = source.search(_query('skirt'));
    await _flush(tester);
    adapter.requests.single.complete(ResponseBody.fromString('failed', 503));
    await _flush(tester);
    source.cancelPending();
    await tester.pump(const Duration(seconds: 2));
    await _flush(tester);
    expect(await pending, isEmpty);
    expect(adapter.requests, hasLength(1));
    expect(source.lastError, isNull);
    expect(source.circuitOpen, isFalse);
  });

  testWidgets('a cancelled failure does not leak into a successful query', (
    tester,
  ) async {
    final adapter = _Adapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final source = DanbooruCompletionSource(dio: dio, cache: _Cache());
    addTearDown(source.dispose);
    addTearDown(dio.close);

    final old = source.search(_query('blue'));
    await _flush(tester);
    final current = source.search(_query('skirt'));
    await tester.pump(const Duration(milliseconds: 251));
    await _flush(tester);
    adapter.requests.last.complete(_tags('skirt'));
    await _flush(tester);
    expect((await current).single.canonicalTag, 'skirt');
    adapter.requests.first.complete(ResponseBody.fromString('failed', 500));
    await _flush(tester);
    expect(await old, isEmpty);
    expect(source.lastError, isNull);
    expect(source.circuitOpen, isFalse);
  });

  testWidgets(
    'a timeout recovers on the next query without losing local cache',
    (tester) async {
      final adapter = _Adapter();
      final cache = _Cache();
      final dio = Dio()..httpClientAdapter = adapter;
      final source = DanbooruCompletionSource(dio: dio, cache: cache);
      addTearDown(source.dispose);
      addTearDown(dio.close);

      final failed = source.search(_query('blue'));
      await _flush(tester);
      adapter.requests.single.response.completeError(
        DioException(
          requestOptions: adapter.requests.single.options,
          type: DioExceptionType.receiveTimeout,
          message: 'timeout',
        ),
      );
      await _flush(tester);
      expect(await failed, isEmpty);
      expect(source.lastError?.kind, CompletionRemoteErrorKind.timeout);

      final recovered = source.search(_query('skirt'));
      await tester.pump(const Duration(milliseconds: 251));
      await _flush(tester);
      adapter.requests.last.complete(_tags('skirt'));
      await _flush(tester);
      expect((await recovered).single.canonicalTag, 'skirt');
      expect(source.lastError, isNull);
      expect(
        (await source.search(_query('skirt'))).single.canonicalTag,
        'skirt',
      );
      expect(adapter.requests, hasLength(2));
    },
  );

  for (final (cause, kind) in [
    (
      const SocketException('Failed host lookup: danbooru.donmai.us'),
      CompletionRemoteErrorKind.dns,
    ),
    (
      const HandshakeException('Handshake failed'),
      CompletionRemoteErrorKind.tls,
    ),
    (
      const SocketException('Connection reset'),
      CompletionRemoteErrorKind.connection,
    ),
  ]) {
    testWidgets('related requests distinguish ${kind.name} errors', (
      tester,
    ) async {
      final adapter = _Adapter();
      final dio = Dio()..httpClientAdapter = adapter;
      final source = DanbooruCompletionSource(dio: dio, cache: _Cache());
      addTearDown(source.dispose);
      addTearDown(dio.close);

      final pending = source.relatedTags('blood_sucking');
      await _flush(tester);
      adapter.requests.single.response.completeError(
        DioException(
          requestOptions: adapter.requests.single.options,
          type: DioExceptionType.connectionError,
          error: cause,
        ),
      );
      await _flush(tester);
      expect(await pending, isEmpty);
      expect(source.lastError?.kind, kind);
    });
  }

  testWidgets('a non-JSON success is not cached as empty related tags', (
    tester,
  ) async {
    final adapter = _Adapter();
    final cache = _Cache();
    final dio = Dio()..httpClientAdapter = adapter;
    final source = DanbooruCompletionSource(dio: dio, cache: cache);
    addTearDown(source.dispose);
    addTearDown(dio.close);

    final pending = source.relatedTags('blood_sucking');
    await _flush(tester);
    adapter.requests.single.complete(
      ResponseBody.fromString('<html>Maintenance</html>', 200),
    );
    await _flush(tester);
    expect(await pending, isEmpty);
    expect(source.lastError?.kind, CompletionRemoteErrorKind.invalidResponse);
    expect(cache.values, isEmpty);
  });
}

Future<void> _flush(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

CompletionQuery _query(String token) => CompletionQuery(
  fullText: token,
  cursorPosition: token.length,
  token: token,
  replacementRange: TextReplacementRange(start: 0, end: token.length),
  existingTags: const {},
  limit: 20,
  locale: 'zh-CN',
);

ResponseBody _tags(String tag) => ResponseBody.fromString(
  jsonEncode([
    {'name': tag, 'category': 0, 'post_count': 100},
  ]),
  200,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

class _Cache extends AutocompleteCacheDatabase {
  bool deferReads = false;
  final reads = <Completer<CachedAutocompletePayload?>>[];
  final values = <String, CachedAutocompletePayload>{};

  @override
  Future<CachedAutocompletePayload?> getRemote(String key) {
    if (!deferReads) return Future.value(values[key]);
    final read = Completer<CachedAutocompletePayload?>();
    reads.add(read);
    return read.future;
  }

  @override
  Future<void> putRemote(String key, List<Map<String, dynamic>> payload) async {
    values[key] = CachedAutocompletePayload(
      payload: payload,
      fetchedAt: DateTime.now().toUtc(),
    );
  }
}

class _Request {
  _Request(this.options, Future<void>? cancellation) {
    cancellation?.then((_) => cancelled = true);
  }

  final RequestOptions options;
  final response = Completer<ResponseBody>();
  bool cancelled = false;

  void complete(ResponseBody body) => response.complete(body);
}

class _Adapter implements HttpClientAdapter {
  final requests = <_Request>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    final request = _Request(options, cancelFuture);
    requests.add(request);
    return request.response.future;
  }

  @override
  void close({bool force = false}) {}
}
