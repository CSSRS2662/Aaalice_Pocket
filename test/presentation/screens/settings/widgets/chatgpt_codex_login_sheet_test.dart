import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/storage/secure_storage_service.dart';
import 'package:nai_launcher/data/models/prompt_assistant/prompt_assistant_models.dart';
import 'package:nai_launcher/data/services/chatgpt_codex/chatgpt_codex_oauth_client.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/prompt_assistant/providers/chatgpt_codex_account_provider.dart';
import 'package:nai_launcher/presentation/screens/settings/widgets/chatgpt_codex_login_sheet.dart';

import '../../../../helpers/chatgpt_codex_fakes.dart';

final _provider = ProviderPreset.chatgptCodex.createConfig();

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
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  Map<String, FakeHandler> routes,
) async {
  // The default poll delay is a cancellable timer, driven here by pumps.
  final client = ChatGptCodexOAuthClient(
    Dio()..httpClientAdapter = RoutedHttpAdapter(routes),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        secureStorageServiceProvider.overrideWithValue(_MemorySecureStorage()),
        chatGptCodexOAuthClientProvider.overrideWithValue(client),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showChatGptCodexLoginSheet(context, _provider),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.text('open')));
}

/// The fake HTTP round trip takes a few event-loop turns.
Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 20 && finder.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('device code login shows the code, then signs in', (
    tester,
  ) async {
    var approved = false;
    final container = await _pump(tester, {
      '/api/accounts/deviceauth/usercode': (_) => jsonBody({
        'device_auth_id': 'dev',
        'user_code': 'ABCD-1234',
        'interval': 5,
      }),
      '/api/accounts/deviceauth/token': (_) => approved
          ? jsonBody({'authorization_code': 'code', 'code_verifier': 'ver'})
          : jsonBody({}, status: 403),
      '/oauth/token': (_) => jsonBody({
        'access_token': fakeChatGptToken(),
        'refresh_token': 'refresh',
        'expires_in': 3600,
      }),
    });

    await tester.tap(find.byKey(const ValueKey('chatgpt-codex-login-device')));
    await _pumpUntil(tester, find.text('ABCD-1234'));
    expect(find.text('ABCD-1234'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('chatgpt-codex-login-open-verification')),
      findsOneWidget,
    );

    approved = true;
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('chatgpt-codex-login')), findsNothing);
    final account = container.read(chatGptCodexAccountProvider)[_provider.id]!;
    expect(account.email, 'me@example.com');
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancel returns to the method choice', (tester) async {
    await _pump(tester, {
      '/api/accounts/deviceauth/usercode': (_) => jsonBody({
        'device_auth_id': 'dev',
        'user_code': 'WXYZ-0000',
        'interval': 5,
      }),
      '/api/accounts/deviceauth/token': (_) => jsonBody({}, status: 403),
    });
    await tester.tap(find.byKey(const ValueKey('chatgpt-codex-login-device')));
    await _pumpUntil(tester, find.text('WXYZ-0000'));
    await tester.tap(find.byKey(const ValueKey('chatgpt-codex-login-cancel')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('chatgpt-codex-login-browser')),
      findsOneWidget,
    );
  });

  testWidgets('an account without device login says how to proceed', (
    tester,
  ) async {
    await _pump(tester, {});
    await tester.tap(find.byKey(const ValueKey('chatgpt-codex-login-device')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Device code sign-in is not enabled'),
      findsOneWidget,
    );
  });
}
