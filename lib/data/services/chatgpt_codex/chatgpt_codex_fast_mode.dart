import '../../models/prompt_assistant/prompt_assistant_models.dart';

/// The Codex "Fast" service tier for ChatGPT logins.
///
/// Official Codex lists it per model as the `priority` tier, "1.5x speed,
/// increased usage", on its full models; the mini and spark models have
/// none. Pi forwards the same `service_tier` request field.
abstract final class ChatGptCodexFastMode {
  static const serviceTier = 'priority';

  static bool supports(String model) {
    final id = model.trim().toLowerCase();
    return id.isNotEmpty && !id.contains('mini') && !id.contains('spark');
  }

  /// Whether [provider] and [model] offer the Fast tier at all.
  static bool availableFor(ProviderConfig provider, String model) =>
      provider.protocol.usesChatGptLogin && supports(model);

  /// The `service_tier` to send: the Fast tier when the user [enabled] it
  /// and the route has it, otherwise the account default.
  static String? serviceTierFor(
    ProviderConfig provider,
    String model, {
    required bool enabled,
  }) => enabled && availableFor(provider, model) ? serviceTier : null;
}
