import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/services/chatgpt_codex/chatgpt_codex_callback_server.dart';
import 'package:nai_launcher/data/services/chatgpt_codex/chatgpt_codex_usage.dart';
import 'package:nai_launcher/data/services/chatgpt_codex/chatgpt_codex_usage_interceptor.dart';

import '../../../helpers/chatgpt_codex_fakes.dart';

void main() {
  final now = DateTime.utc(2026, 10, 15, 8);

  test('reads both windows from response headers', () {
    final usage = ChatGptCodexUsage.fromHeaders({
      'x-codex-primary-used-percent': ['7.0'],
      'x-codex-primary-window-minutes': ['300'],
      'x-codex-primary-reset-at': ['1791917027'],
      'x-codex-secondary-used-percent': ['1'],
      'x-codex-secondary-window-minutes': ['10080'],
      'x-codex-secondary-reset-after-seconds': ['120'],
    }, now)!;
    expect(usage.primary!.remainingPercent, 93);
    expect(usage.primary!.length, const Duration(hours: 5));
    expect(
      usage.primary!.resetsAt,
      DateTime.fromMillisecondsSinceEpoch(1791917027000, isUtc: true),
    );
    expect(usage.secondary!.length, const Duration(days: 7));
    expect(usage.secondary!.resetsAt, now.add(const Duration(minutes: 2)));
    expect(ChatGptCodexUsage.fromHeaders({}, now), isNull);
  });

  test('reads the usage endpoint and keeps its details on header updates', () {
    final full = ChatGptCodexUsage.fromJson({
      'plan_type': 'plus',
      'rate_limit': {
        'limit_reached': false,
        'primary_window': {
          'used_percent': 40,
          'limit_window_seconds': 18000,
          'reset_after_seconds': 600,
        },
        'secondary_window': {
          'used_percent': 120,
          'limit_window_seconds': 604800,
          'reset_at': 1792503827,
        },
      },
      'additional_rate_limits': [
        {
          'limit_name': 'GPT-5.3-Codex-Spark',
          'rate_limit': {
            'primary_window': {'used_percent': 10, 'limit_window_seconds': 18000},
          },
        },
      ],
    }, now)!;
    expect(full.planType, 'plus');
    expect(full.primary!.resetsAt, now.add(const Duration(minutes: 10)));
    // Over-use never shows a negative share.
    expect(full.secondary!.remainingPercent, 0);
    expect(full.additional.single.name, 'GPT-5.3-Codex-Spark');

    final fromHeaders = ChatGptCodexUsage.fromHeaders({
      'x-codex-primary-used-percent': ['50'],
    }, now)!.withDetailsFrom(full);
    expect(fromHeaders.primary!.usedPercent, 50);
    expect(fromHeaders.secondary, same(full.secondary));
    expect(fromHeaders.planType, 'plus');
    expect(fromHeaders.additional, same(full.additional));
  });

  test('the interceptor records Codex responses only, errors included', () async {
    final recorded = <String, ChatGptCodexUsage>{};
    const headers = {
      'x-codex-primary-used-percent': ['20'],
    };
    final dio = Dio()
      ..httpClientAdapter = RoutedHttpAdapter({
        '/backend-api/codex/responses': (request) =>
            request.options.headers['chatgpt-account-id'] == 'acc_3'
            ? jsonBody({}, status: 429, headers: headers)
            : sseBody(const [], headers: headers),
        '/backend-api/codex/limited': (_) => jsonBody({}, headers: headers),
      })
      ..interceptors.add(
        ChatGptCodexUsageInterceptor(
          (account, usage) => recorded[account] = usage,
          clock: () => now,
        ),
      );
    Options account(String id) =>
        Options(headers: {'chatgpt-account-id': id});

    await dio.post<dynamic>(
      'https://chatgpt.com/backend-api/codex/responses',
      options: account('acc_1'),
    );
    await dio.post<dynamic>(
      'https://chatgpt.com/backend-api/codex/limited',
      options: account('acc_2'),
    );
    await expectLater(
      dio.post<dynamic>(
        'https://chatgpt.com/backend-api/codex/responses',
        options: account('acc_3'),
      ),
      throwsA(isA<DioException>()),
    );
    expect(recorded.keys, ['acc_1', 'acc_3']);
    expect(recorded['acc_1']!.primary!.usedPercent, 20);
  });

  group('callback server', () {
    Future<HttpClientResponse> get(int port, String query) async {
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:$port/auth/callback?$query'),
      );
      final response = await request.close();
      await response.drain<void>();
      return response;
    }

    test('accepts the redirect only with its own state', () async {
      final server = (await ChatGptCodexCallbackServer.start(
        state: 'expected',
        port: 0,
      ))!;
      addTearDown(server.close);
      final port = server.port;

      final wrong = await get(port, 'state=other&code=c');
      expect(wrong.statusCode, HttpStatus.badRequest);
      final right = await get(port, 'state=expected&code=c1');
      expect(right.statusCode, HttpStatus.ok);
      expect(await server.code, 'c1');
    });

    test('cancel completes without a code', () async {
      final server = (await ChatGptCodexCallbackServer.start(
        state: 's',
        port: 0,
      ))!;
      addTearDown(server.close);
      server.cancel();
      expect(await server.code, isNull);
    });
  });
}
