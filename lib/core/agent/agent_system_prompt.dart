import '../../data/models/agent/agent_settings.dart';

/// [sessionInstructions] come after the general instructions in both modes:
/// they hold for the current conversation only and win where they differ.
String composeAgentSystemPrompt({
  required String builtInPrompt,
  required String customInstructions,
  required AgentSystemPromptMode mode,
  required String runtimeContext,
  String sessionInstructions = '',
}) {
  final builtIn = builtInPrompt.trim();
  final custom = customInstructions.trim();
  final session = sessionInstructions.trim();
  return [
    if (mode == AgentSystemPromptMode.override)
      custom
    else ...[
      builtIn,
      if (custom.isNotEmpty)
        '<user_behavior_instructions>\n$custom\n</user_behavior_instructions>',
    ],
    if (session.isNotEmpty)
      '<conversation_instructions>\n'
          'The user set these for this conversation only. Follow them here; '
          'where they differ from the instructions above, these win.\n'
          '$session\n'
          '</conversation_instructions>',
    runtimeContext.trim(),
  ].where((section) => section.isNotEmpty).join('\n\n');
}
