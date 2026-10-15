import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/services/chatgpt_codex/chatgpt_codex_credentials.dart';
import 'package:nai_launcher/data/services/chatgpt_codex/chatgpt_codex_oauth_client.dart';

import '../../../helpers/chatgpt_codex_fakes.dart';

void main() {
  final now = DateTime.utc(2026, 10, 15, 8);

  ({ChatGptCodexOAuthClient client, RoutedHttpAdapter http, List<Duration> waits})
  build(Map<String, FakeHandler> routes, {DateTime Function()? clock}) {
    final http = RoutedHttpAdapter(routes);
    final waits = <Duration>[];
    var current = now;
    final client = ChatGptCodexOAuthClient(
      Dio()..httpClientAdapter = http,
      clock: clock ?? () => current,
      sleep: (duration, cancelToken) async {
        waits.add(duration);
        current = current.add(duration);
      },
    );
    return (client: client, http: http, waits: waits);
  }

  ResponseBody tokens({String tag = 'a'}) => jsonBody({
    'access_token': fakeChatGptToken(tag: tag),
    'refresh_token': 'refresh-$tag',
    'expires_in': 3600,
  });

  group('device code login', () {
    test('polls until approved, then exchanges the code', () async {
      var polls = 0;
      final (:client, :http, :waits) = build({
        '/api/accounts/deviceauth/usercode': (_) =>
            jsonBody({'device_auth_id': 'dev', 'user_code': 'ABCD-1234', 'interval': '2'}),
        '/api/accounts/deviceauth/token': (_) {
          polls++;
          return switch (polls) {
            1 => jsonBody({}, status: 403),
            2 => jsonBody({
              'error': {'code': 'slow_down'},
            }, status: 400),
            _ => jsonBody({'authorization_code': 'code-1', 'code_verifier': 'ver-1'}),
          };
        },
        '/oauth/token': (_) => tokens(),
      });

      final device = await client.startDeviceCode();
      expect(device.userCode, 'ABCD-1234');
      expect(device.interval, const Duration(seconds: 2));
      final credentials = await client.completeDeviceCode(
        device,
        cancelToken: CancelToken(),
      );

      expect(credentials.accountId, 'acc_1');
      expect(credentials.email, 'me@example.com');
      expect(credentials.planType, 'plus');
      expect(credentials.expiresAt, now.add(const Duration(seconds: 3600 + 9)));
      // pending waits the interval, slow_down adds five seconds.
      expect(waits, [const Duration(seconds: 2), const Duration(seconds: 7)]);
      final exchange = http.requests.last;
      expect(exchange.path, '/oauth/token');
      final form = Uri.splitQueryString(exchange.data! as String);
      expect(form['grant_type'], 'authorization_code');
      expect(form['code'], 'code-1');
      expect(form['code_verifier'], 'ver-1');
      expect(form['redirect_uri'], ChatGptCodexAuth.deviceRedirectUri);
      expect(form['client_id'], ChatGptCodexAuth.clientId);
    });

    test('reports an account without device login', () async {
      final (:client, http: _, waits: _) = build({});
      await expectLater(
        client.startDeviceCode(),
        throwsA(
          isA<ChatGptCodexAuthException>().having(
            (error) => error.kind,
            'kind',
            ChatGptCodexAuthFailure.deviceCodeUnavailable,
          ),
        ),
      );
    });

    test('gives up after fifteen minutes', () async {
      final (:client, http: _, :waits) = build({
        '/api/accounts/deviceauth/token': (_) => jsonBody({}, status: 403),
      });
      await expectLater(
        client.completeDeviceCode(
          const ChatGptCodexDeviceCode(
            deviceAuthId: 'dev',
            userCode: 'CODE',
            interval: Duration(minutes: 1),
          ),
          cancelToken: CancelToken(),
        ),
        throwsA(
          isA<ChatGptCodexAuthException>().having(
            (error) => error.kind,
            'kind',
            ChatGptCodexAuthFailure.timedOut,
          ),
        ),
      );
      expect(waits, hasLength(15));
    });

    test('stops when cancelled', () async {
      final (:client, http: _, waits: _) = build({
        '/api/accounts/deviceauth/token': (_) => jsonBody({}, status: 403),
      });
      final cancel = CancelToken()..cancel();
      await expectLater(
        client.completeDeviceCode(
          const ChatGptCodexDeviceCode(
            deviceAuthId: 'dev',
            userCode: 'CODE',
            interval: Duration(seconds: 5),
          ),
          cancelToken: cancel,
        ),
        throwsA(
          isA<ChatGptCodexAuthException>().having(
            (error) => error.kind,
            'kind',
            ChatGptCodexAuthFailure.cancelled,
          ),
        ),
      );
    });
  });

  test('browser authorization carries the Codex client parameters', () {
    final (:client, http: _, waits: _) = build({});
    final authorization = client.createBrowserAuthorization();
    final query = authorization.url.queryParameters;
    expect(authorization.url.origin, 'https://auth.openai.com');
    expect(query['client_id'], ChatGptCodexAuth.clientId);
    expect(query['redirect_uri'], 'http://localhost:1455/auth/callback');
    expect(query['scope'], 'openid profile email offline_access');
    expect(query['code_challenge_method'], 'S256');
    expect(query['state'], authorization.state);
    expect(query['codex_cli_simplified_flow'], 'true');
    expect(query['originator'], ChatGptCodexAuth.originator);
  });

  test('refresh replaces both tokens and rejects bad responses', () async {
    final (:client, :http, waits: _) = build({'/oauth/token': (_) => tokens(tag: 'b')});
    final refreshed = await client.refresh('refresh-a');
    expect(refreshed.refresh, 'refresh-b');
    final form = Uri.splitQueryString(http.requests.single.data! as String);
    expect(form['grant_type'], 'refresh_token');
    expect(form['refresh_token'], 'refresh-a');

    final (client: rejecting, http: _, waits: _) = build({
      '/oauth/token': (_) => jsonBody({'error': 'invalid_grant'}, status: 400),
    });
    await expectLater(
      rejecting.refresh('refresh-a'),
      throwsA(isA<ChatGptCodexAuthException>()),
    );
  });

  test('pasted redirects accept a URL, code#state or a bare code', () {
    expect(
      ChatGptCodexOAuthClient.parseAuthorizationInput(
        'http://localhost:1455/auth/callback?code=c1&state=s1',
      ),
      (code: 'c1', state: 's1'),
    );
    expect(ChatGptCodexOAuthClient.parseAuthorizationInput('c2#s2'), (
      code: 'c2',
      state: 's2',
    ));
    expect(ChatGptCodexOAuthClient.parseAuthorizationInput('code=c3&state=s3'), (
      code: 'c3',
      state: 's3',
    ));
    expect(ChatGptCodexOAuthClient.parseAuthorizationInput(' c4 '), (
      code: 'c4',
      state: null,
    ));
  });

  group('credentials', () {
    test('round-trip and refresh margin', () {
      final credentials = ChatGptCodexCredentials.fromTokens(
        access: fakeChatGptToken(),
        refresh: 'r',
        expiresInSeconds: 3600,
        now: now,
      );
      final restored = ChatGptCodexCredentials.fromJson(credentials.toJson())!;
      expect(restored.accountId, 'acc_1');
      expect(restored.expiresAt, credentials.expiresAt);
      expect(restored.needsRefresh(now.add(const Duration(minutes: 54))), isFalse);
      expect(restored.needsRefresh(now.add(const Duration(minutes: 55))), isTrue);
    });

    test('a token without a ChatGPT account is refused', () {
      expect(ChatGptCodexClaims.parse('not-a-jwt'), isNull);
      expect(
        () => ChatGptCodexCredentials.fromTokens(
          access: 'a.b.c',
          refresh: 'r',
          expiresInSeconds: 1,
          now: now,
        ),
        throwsFormatException,
      );
    });

    test('backend base trims a configured Codex path', () {
      expect(ChatGptCodexAuth.backendBase(''), 'https://chatgpt.com/backend-api');
      expect(
        ChatGptCodexAuth.backendBase('https://chatgpt.com/backend-api/codex/'),
        'https://chatgpt.com/backend-api',
      );
    });
  });
}
