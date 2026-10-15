import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/storage/secure_storage_service.dart';
import 'package:nai_launcher/data/services/chatgpt_codex/chatgpt_codex_credentials.dart';
import 'package:nai_launcher/data/services/chatgpt_codex/chatgpt_codex_oauth_client.dart';
import 'package:nai_launcher/presentation/prompt_assistant/providers/chatgpt_codex_account_provider.dart';

import '../../../helpers/chatgpt_codex_fakes.dart';

class _MemorySecureStorage extends SecureStorageService {
  final values = <String, String>{};

  @override
  Future<String?> getChatGptCodexCredentials(String providerId) async =>
      values[providerId];

  @override
  Future<void> saveChatGptCodexCredentials(
    String providerId,
    String json,
  ) async => values[providerId] = json;

  @override
  Future<void> deleteChatGptCodexCredentials(String providerId) async =>
      values.remove(providerId);
}

void main() {
  final start = DateTime.utc(2026, 10, 15, 8);

  ({ProviderContainer container, _MemorySecureStorage storage, RoutedHttpAdapter http})
  setUp({
    required DateTime Function() clock,
    required FakeHandler token,
    DateTime? expiresAt,
  }) {
    final storage = _MemorySecureStorage();
    storage.values['codex'] = jsonEncode(
      ChatGptCodexCredentials(
        access: fakeChatGptToken(tag: 'old'),
        refresh: 'refresh-old',
        expiresAt: expiresAt ?? start.add(const Duration(hours: 1)),
        accountId: 'acc_1',
        email: 'me@example.com',
      ).toJson(),
    );
    final http = RoutedHttpAdapter({'/oauth/token': token});
    final container = ProviderContainer(
      overrides: [
        secureStorageServiceProvider.overrideWithValue(storage),
        chatGptCodexOAuthClientProvider.overrideWithValue(
          ChatGptCodexOAuthClient(
            Dio()..httpClientAdapter = http,
            clock: clock,
          ),
        ),
        chatGptCodexAccountProvider.overrideWith(
          (ref) => ChatGptCodexAccountNotifier(ref, clock: clock),
        ),
      ],
    );
    addTearDown(container.dispose);
    return (container: container, storage: storage, http: http);
  }

  ResponseBody fresh(FakeRequest _) => jsonBody({
    'access_token': fakeChatGptToken(tag: 'new'),
    'refresh_token': 'refresh-new',
    'expires_in': 3600,
  });

  test('a fresh token is used as stored', () async {
    final (:container, storage: _, :http) = setUp(
      clock: () => start,
      token: fresh,
    );
    final notifier = container.read(chatGptCodexAccountProvider.notifier);
    expect(await notifier.accessToken('codex'), fakeChatGptToken(tag: 'old'));
    expect(http.requests, isEmpty);
    expect(
      container.read(chatGptCodexAccountProvider)['codex']!.email,
      'me@example.com',
    );
  });

  test('near expiry, concurrent callers share one refresh', () async {
    final (:container, :storage, :http) = setUp(
      clock: () => start.add(const Duration(minutes: 56)),
      token: fresh,
    );
    final notifier = container.read(chatGptCodexAccountProvider.notifier);
    final tokens = await Future.wait([
      notifier.accessToken('codex'),
      notifier.accessToken('codex'),
    ]);
    expect(tokens, everyElement(fakeChatGptToken(tag: 'new')));
    expect(http.requests, hasLength(1));
    final saved = ChatGptCodexCredentials.fromJson(
      jsonDecode(storage.values['codex']!),
    )!;
    expect(saved.refresh, 'refresh-new');
  });

  test('a rejected refresh after expiry asks for a new login', () async {
    final (:container, storage: _, http: _) = setUp(
      clock: () => start.add(const Duration(hours: 2)),
      token: (_) => jsonBody({'error': 'invalid_grant'}, status: 401),
    );
    final notifier = container.read(chatGptCodexAccountProvider.notifier);
    expect(await notifier.accessToken('codex'), isNull);
    expect(
      container.read(chatGptCodexAccountProvider)['codex']!.needsLogin,
      isTrue,
    );
  });

  test('a rejected refresh before expiry keeps the working token', () async {
    final (:container, storage: _, http: _) = setUp(
      clock: () => start.add(const Duration(minutes: 58)),
      token: (_) => jsonBody({'error': 'server'}, status: 500),
    );
    final notifier = container.read(chatGptCodexAccountProvider.notifier);
    expect(await notifier.accessToken('codex'), fakeChatGptToken(tag: 'old'));
  });

  test('logout forgets the stored login', () async {
    final (:container, :storage, http: _) = setUp(
      clock: () => start,
      token: fresh,
    );
    final notifier = container.read(chatGptCodexAccountProvider.notifier);
    await notifier.load('codex');
    await notifier.logout('codex');
    expect(storage.values, isEmpty);
    expect(container.read(chatGptCodexAccountProvider), isEmpty);
    expect(await notifier.accessToken('codex'), isNull);
  });
}
