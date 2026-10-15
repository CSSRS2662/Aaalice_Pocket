import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/models/prompt_assistant/prompt_assistant_models.dart';
import 'package:nai_launcher/data/services/chatgpt_codex/chatgpt_codex_usage.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/agent_chat/widgets/chatgpt_codex_quota_pill.dart';
import 'package:nai_launcher/presentation/prompt_assistant/providers/chatgpt_codex_account_provider.dart';
import 'package:nai_launcher/presentation/prompt_assistant/providers/chatgpt_codex_usage_provider.dart';

final _provider = ProviderPreset.chatgptCodex.createConfig();

class _Accounts extends ChatGptCodexAccountNotifier {
  _Accounts(super.ref) {
    state = {
      _provider.id: ChatGptCodexAccount(
        accountId: 'acc_1',
        expiresAt: DateTime.now().add(const Duration(days: 1)),
        email: 'me@example.com',
        planType: 'plus',
      ),
    };
  }
}

class _Usage extends ChatGptCodexUsageNotifier {
  _Usage(super.ref, ChatGptCodexUsage usage) {
    state = {'acc_1': usage};
  }

  int refreshes = 0;

  @override
  Future<void> refresh(ProviderConfig provider, {bool force = false}) async {
    refreshes++;
  }
}

Future<_Usage> _pump(
  WidgetTester tester, {
  required ChatGptCodexUsage usage,
  ChatGptCodexQuotaDensity density = ChatGptCodexQuotaDensity.full,
  double textScale = 1,
}) async {
  late _Usage notifier;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        chatGptCodexAccountProvider.overrideWith(_Accounts.new),
        chatGptCodexUsageProvider.overrideWith(
          (ref) => notifier = _Usage(ref, usage),
        ),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: Align(
              alignment: Alignment.topRight,
              child: ChatGptCodexQuotaPill(provider: _provider, density: density),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return notifier;
}

ChatGptCodexUsage _usage(DateTime now) => ChatGptCodexUsage(
  observedAt: now,
  planType: 'plus',
  primary: ChatGptCodexUsageWindow(
    usedPercent: 7,
    length: const Duration(hours: 5),
    resetsAt: now.add(const Duration(hours: 2, minutes: 5, seconds: 30)),
  ),
  secondary: ChatGptCodexUsageWindow(
    usedPercent: 92.5,
    length: const Duration(days: 7),
    resetsAt: now.add(const Duration(days: 3, hours: 4, minutes: 30)),
  ),
);

void main() {
  testWidgets('shows the remaining share of both windows', (tester) async {
    final usage = await _pump(tester, usage: _usage(DateTime.now()));
    expect(find.text('5h'), findsOneWidget);
    expect(find.text('93%'), findsOneWidget);
    expect(find.text('7d'), findsOneWidget);
    expect(find.text('7%'), findsOneWidget);
    expect(usage.refreshes, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact shows only the window with the least left', (
    tester,
  ) async {
    await _pump(
      tester,
      usage: _usage(DateTime.now()),
      density: ChatGptCodexQuotaDensity.compact,
    );
    expect(find.text('7d'), findsOneWidget);
    expect(find.text('5h'), findsNothing);
  });

  testWidgets('minimal keeps the numbers in the tooltip only', (tester) async {
    await _pump(
      tester,
      usage: _usage(DateTime.now()),
      density: ChatGptCodexQuotaDensity.minimal,
    );
    expect(find.text('7d'), findsNothing);
    expect(find.byIcon(Icons.data_usage_rounded), findsOneWidget);
    expect(
      tester.widget<Tooltip>(find.byType(Tooltip)).message,
      '5-hour limit 93% left, Weekly limit 7% left',
    );
  });

  testWidgets('3x text does not overflow the pill', (tester) async {
    await _pump(tester, usage: _usage(DateTime.now()), textScale: 3);
    expect(find.text('93%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping opens reset times in local time', (tester) async {
    await _pump(tester, usage: _usage(DateTime.now()));
    await tester.tap(find.byKey(const ValueKey('agent-chat-codex-quota')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('chatgpt-codex-quota-details')), findsOneWidget);
    expect(find.text('5-hour limit'), findsOneWidget);
    expect(find.text('Weekly limit'), findsOneWidget);
    expect(find.text('93% left'), findsOneWidget);
    expect(find.textContaining('(in about 2 h 5 min)'), findsOneWidget);
    expect(find.textContaining('(in about 3 d 4 h)'), findsOneWidget);
    expect(find.textContaining('me@example.com · Plus plan'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
