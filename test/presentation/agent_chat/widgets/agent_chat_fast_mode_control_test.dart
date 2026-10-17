import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/agent/agent_types.dart';
import 'package:nai_launcher/data/models/agent/agent_settings.dart';
import 'package:nai_launcher/data/models/prompt_assistant/prompt_assistant_models.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/agent_chat/widgets/agent_chat_model_picker.dart';
import 'package:nai_launcher/presentation/agent_settings/providers/agent_settings_provider.dart';

final _codex = ProviderPreset.chatgptCodex.createConfig();
const _cloud = ProviderConfig(
  id: 'cloud',
  name: 'Cloud',
  baseUrl: 'https://cloud.example',
);

final _config = PromptAssistantConfigState.defaults().copyWith(
  providers: [_codex, _cloud],
  models: [
    for (final (provider, model) in [
      (_codex.id, 'gpt-5.5'),
      (_codex.id, 'gpt-5.3-codex-spark'),
      (_cloud.id, 'gpt-5.5'),
    ])
      ModelConfig(
        providerId: provider,
        name: model,
        displayName: model,
        forTask: AssistantTaskType.chat,
      ),
  ],
);

const _option = ValueKey('agent-chat-fast-mode-option');
const _indicator = ValueKey('agent-chat-fast-mode-indicator');

Future<void> _pump(
  WidgetTester tester, {
  String? providerId,
  String model = 'gpt-5.5',
  bool fastModeEnabled = false,
  Future<void> Function(bool enabled)? onFastModeChanged,
  double width = 1180,
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomRight,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width - 24),
            child: AgentChatConfigurationControl(
              config: _config,
              agentSettings: AgentSettingsState(
                initialized: true,
                settings: AgentSettings(
                  chat: AgentChatConfig(
                    modelReference: AgentModelReference(
                      providerId: providerId ?? _codex.id,
                      model: model,
                    ),
                  ),
                ),
              ),
              routeLabel: model,
              routeError: '',
              thinkingLevel: ThinkingLevel.medium,
              availableThinkingLevels: const [
                ThinkingLevel.low,
                ThinkingLevel.medium,
                ThinkingLevel.high,
              ],
              enabled: true,
              onModelSelected: (_, _) async {},
              onThinkingSelected: (_) async {},
              fastModeEnabled: fastModeEnabled,
              onFastModeChanged: onFastModeChanged ?? (_) async {},
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openPicker(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('agent-chat-model-selector')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Fast mode sits under the reasoning levels for ChatGPT logins', (
    tester,
  ) async {
    bool? changed;
    await _pump(
      tester,
      onFastModeChanged: (enabled) async => changed = enabled,
    );
    expect(find.byKey(_indicator), findsNothing);

    await _openPicker(tester);
    final option = find.byKey(_option);
    expect(option, findsOneWidget);
    expect(find.text('Fast mode'), findsOneWidget);
    expect(
      tester.getTopLeft(option).dy,
      greaterThan(
        tester
            .getTopLeft(
              find.byKey(const ValueKey('agent-chat-thinking-option-high')),
            )
            .dy,
      ),
    );
    expect(
      tester.getSize(option).height,
      greaterThanOrEqualTo(kMinInteractiveDimension),
    );

    await tester.tap(option);
    await tester.pumpAndSettle();
    expect(changed, isTrue);
    expect(find.byKey(_option), findsNothing);
  });

  testWidgets('turning Fast mode off goes through the same switch', (
    tester,
  ) async {
    bool? changed;
    await _pump(
      tester,
      fastModeEnabled: true,
      onFastModeChanged: (enabled) async => changed = enabled,
    );

    await _openPicker(tester);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(changed, isFalse);
  });

  testWidgets('the selector shows a bolt while Fast mode is on', (
    tester,
  ) async {
    for (final width in const [320.0, 600.0, 840.0, 1180.0, 1600.0]) {
      for (final textScale in const [1.0, 3.0]) {
        await _pump(
          tester,
          fastModeEnabled: true,
          width: width,
          textScale: textScale,
        );
        expect(
          find.byKey(_indicator),
          findsOneWidget,
          reason: '$width x$textScale',
        );
        expect(tester.takeException(), isNull, reason: '$width x$textScale');
      }
    }
  });

  testWidgets('routes without a Fast tier hide the switch and the bolt', (
    tester,
  ) async {
    for (final (providerId, model) in [
      (_cloud.id, 'gpt-5.5'),
      (_codex.id, 'gpt-5.3-codex-spark'),
    ]) {
      await _pump(
        tester,
        providerId: providerId,
        model: model,
        fastModeEnabled: true,
      );
      expect(find.byKey(_indicator), findsNothing, reason: model);

      await _openPicker(tester);
      expect(find.byKey(_option), findsNothing, reason: model);
      await tester.tap(
        find.byKey(const ValueKey('agent-chat-model-picker-close')),
      );
      await tester.pumpAndSettle();
    }
  });

  testWidgets('the picker keeps Fast mode reachable at 320 wide and 3x text', (
    tester,
  ) async {
    await _pump(tester, width: 320, textScale: 3);

    await _openPicker(tester);
    final option = find.byKey(_option);
    await tester.scrollUntilVisible(
      option,
      120,
      scrollable: find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();

    expect(option.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
