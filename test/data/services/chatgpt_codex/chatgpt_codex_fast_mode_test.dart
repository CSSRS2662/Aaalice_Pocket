import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/models/prompt_assistant/prompt_assistant_models.dart';
import 'package:nai_launcher/data/services/chatgpt_codex/chatgpt_codex_fast_mode.dart';

void main() {
  final codex = ProviderPreset.chatgptCodex.createConfig();
  const apiKeyProvider = ProviderConfig(
    id: 'cloud',
    name: 'Cloud',
    baseUrl: 'https://cloud.example',
  );

  String? tier(ProviderConfig provider, String model, {bool enabled = true}) =>
      ChatGptCodexFastMode.serviceTierFor(provider, model, enabled: enabled);

  test('a ChatGPT login asks for the priority tier when Fast is on', () {
    expect(tier(codex, 'gpt-5.5'), 'priority');
    expect(tier(codex, 'gpt-6-sol'), 'priority');
    expect(tier(codex, 'gpt-5.5', enabled: false), isNull);
  });

  test('models without a Fast tier and API keys keep the default', () {
    expect(tier(codex, 'gpt-5.3-codex-spark'), isNull);
    expect(tier(codex, 'gpt-5.4-mini'), isNull);
    expect(tier(apiKeyProvider, 'gpt-5.5'), isNull);
    expect(
      ChatGptCodexFastMode.availableFor(apiKeyProvider, 'gpt-5.5'),
      isFalse,
    );
    expect(ChatGptCodexFastMode.availableFor(codex, 'gpt-5.5'), isTrue);
  });
}
