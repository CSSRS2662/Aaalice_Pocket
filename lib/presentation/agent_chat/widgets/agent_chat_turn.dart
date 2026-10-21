import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/agent/agent_media_display_policy.dart';
import '../../../core/agent/agent_types.dart';
import '../../../core/utils/localization_extension.dart';
import '../models/agent_chat_prompt_envelope.dart';
import '../models/agent_chat_turn_timeline.dart';
import 'agent_chat_tool_widgets.dart';

/// Immutable display projection for Thread -> Turn -> Item.
///
/// The runtime message list remains untouched. This projection only decides
/// which causal items share a visual turn and which details start collapsed.
class AgentChatThreadModel {
  const AgentChatThreadModel({required this.turns});

  factory AgentChatThreadModel.fromMessages(
    List<Message> messages, {
    List<AgentChatTurnTimeline> timeline = const [],
  }) {
    final turns = <AgentChatTurnModel>[];
    void addMessage(AgentChatTurnModel turn, Message message, int index) {
      // A later message in the same turn guided the work in progress.
      if (isVisualUserMessage(message)) {
        final text = visibleUserMessage(message)?.text.trim() ?? '';
        if (text.isNotEmpty) {
          turn.workItems.add(
            AgentChatTurnItem.steer(
              steer: text,
              messageIndex: index,
              timestamp: message.timestamp,
            ),
          );
        }
        return;
      }
      if (message is! AssistantMessage && message is! ToolResultMessage) {
        return;
      }
      if (message is AssistantMessage) {
        final toolUse =
            message.toolCalls.isNotEmpty ||
            message.stopReason == StopReason.toolUse;
        if (toolUse) {
          for (final content in message.content) {
            if (content case AssistantThinkingContent(
              :final thinking,
            ) when thinking.trim().isNotEmpty) {
              turn.workItems.add(
                AgentChatTurnItem.reasoning(
                  thinking: thinking.trim(),
                  messageIndex: index,
                  timestamp: message.timestamp,
                ),
              );
            } else if (content case AssistantTextContent(
              :final text,
            ) when text.trim().isNotEmpty) {
              turn.workItems.add(
                AgentChatTurnItem.narration(
                  narration: text.trim(),
                  messageIndex: index,
                  timestamp: message.timestamp,
                ),
              );
            } else if (content case final ToolCallContent call) {
              turn.workItems.add(
                AgentChatTurnItem.tool(
                  call: call,
                  messageIndex: index,
                  timestamp: message.timestamp,
                ),
              );
            }
          }
        } else {
          final thinking = message.content
              .whereType<AssistantThinkingContent>()
              .map((content) => content.thinking.trim())
              .where((text) => text.isNotEmpty)
              .join('\n\n');
          if (thinking.isNotEmpty) {
            turn.workItems.add(
              AgentChatTurnItem.reasoning(
                thinking: thinking,
                messageIndex: index,
                timestamp: message.timestamp,
              ),
            );
          }
          if (message.text.trim().isNotEmpty) {
            turn.finalMessages.add(
              AgentChatIndexedMessage(message: message, index: index),
            );
          }
        }
        return;
      }
      if (message is ToolResultMessage) {
        final match = turn.workItems.lastWhere(
          (item) => item.call?.id == message.toolCallId && item.result == null,
          orElse: AgentChatTurnItem.new,
        );
        if (match.call != null) {
          match.result = message;
          match.completedTimestamp = message.timestamp;
        } else {
          turn.workItems.add(
            AgentChatTurnItem.toolResult(
              result: message,
              messageIndex: index,
              timestamp: message.timestamp,
            ),
          );
        }
      }
    }

    var messageIndex = 0;
    for (final timelineTurn in timeline) {
      final entryCount = timelineTurn.items
          .where((item) => item.kind != AgentChatTimelineItemKind.toolCall)
          .length;
      final requestedEnd = messageIndex + entryCount;
      final end = requestedEnd < messages.length
          ? requestedEnd
          : messages.length;
      int? userIndex;
      for (var index = messageIndex; index < end; index++) {
        if (isVisualUserMessage(messages[index])) {
          userIndex = index;
          break;
        }
      }
      final turn = AgentChatTurnModel(
        ordinal: turns.length,
        userMessage: userIndex == null ? null : messages[userIndex],
        userMessageIndex: userIndex ?? -1,
        timeline: timelineTurn,
      );
      for (var index = messageIndex; index < end; index++) {
        if (index != userIndex) addMessage(turn, messages[index], index);
      }
      turns.add(turn);
      messageIndex = end;
    }

    AgentChatTurnModel? legacyTurn;
    for (var index = messageIndex; index < messages.length; index++) {
      final message = messages[index];
      if (isVisualUserMessage(message)) {
        legacyTurn = AgentChatTurnModel(
          ordinal: turns.length,
          userMessage: message,
          userMessageIndex: index,
        );
        turns.add(legacyTurn);
        continue;
      }
      legacyTurn ??= AgentChatTurnModel(ordinal: turns.length);
      if (!turns.contains(legacyTurn)) turns.add(legacyTurn);
      addMessage(legacyTurn, message, index);
    }
    return AgentChatThreadModel(turns: turns);
  }

  final List<AgentChatTurnModel> turns;
}

class AgentChatTurnModel {
  AgentChatTurnModel({
    required this.ordinal,
    this.userMessage,
    this.userMessageIndex = -1,
    this.timeline,
  });

  final int ordinal;
  final Message? userMessage;
  final int userMessageIndex;
  final AgentChatTurnTimeline? timeline;
  final List<AgentChatTurnItem> workItems = [];
  final List<AgentChatIndexedMessage> finalMessages = [];

  List<ToolResultMessage> get mediaResults => [
    for (final item in workItems)
      if (item.result case final result?
          when agentToolDisplaysMedia(item.toolName))
        result,
  ];

  String get preview {
    final message = userMessage;
    if (message == null) return '';
    return visibleUserMessage(message)?.text.trim() ?? '';
  }
}

class AgentChatIndexedMessage {
  const AgentChatIndexedMessage({required this.message, required this.index});

  final Message message;
  final int index;
}

enum AgentChatTurnItemKind { reasoning, narration, tool, steer }

class AgentChatTurnItem {
  AgentChatTurnItem()
    : kind = AgentChatTurnItemKind.tool,
      thinking = null,
      narration = null,
      steer = null,
      call = null,
      result = null,
      messageIndex = -1,
      timestamp = null,
      completedTimestamp = null;

  AgentChatTurnItem.reasoning({
    required this.thinking,
    required this.messageIndex,
    required this.timestamp,
  }) : kind = AgentChatTurnItemKind.reasoning,
       narration = null,
       steer = null,
       call = null,
       result = null,
       completedTimestamp = timestamp;

  AgentChatTurnItem.narration({
    required this.narration,
    required this.messageIndex,
    required this.timestamp,
  }) : kind = AgentChatTurnItemKind.narration,
       thinking = null,
       steer = null,
       call = null,
       result = null,
       completedTimestamp = timestamp;

  /// Guidance the user sent while the work was running.
  AgentChatTurnItem.steer({
    required this.steer,
    required this.messageIndex,
    required this.timestamp,
  }) : kind = AgentChatTurnItemKind.steer,
       thinking = null,
       narration = null,
       call = null,
       result = null,
       completedTimestamp = timestamp;

  AgentChatTurnItem.tool({
    required this.call,
    required this.messageIndex,
    required this.timestamp,
  }) : kind = AgentChatTurnItemKind.tool,
       thinking = null,
       narration = null,
       steer = null,
       result = null,
       completedTimestamp = null;

  AgentChatTurnItem.toolResult({
    required this.result,
    required this.messageIndex,
    required this.timestamp,
  }) : kind = AgentChatTurnItemKind.tool,
       thinking = null,
       narration = null,
       steer = null,
       call = null,
       completedTimestamp = timestamp;

  final AgentChatTurnItemKind kind;
  final String? thinking;
  final String? narration;
  final String? steer;
  final ToolCallContent? call;
  ToolResultMessage? result;
  final int messageIndex;
  final int? timestamp;
  int? completedTimestamp;

  bool get failed => result?.isError ?? false;
  bool get pending => kind == AgentChatTurnItemKind.tool && result == null;
  String get toolName => call?.name ?? result?.toolName ?? '';
}

/// The arguments and result of one tool call, opened from its row.
class AgentChatWorkItemDetails extends StatelessWidget {
  const AgentChatWorkItemDetails({super.key, required this.item});

  final AgentChatTurnItem item;

  @override
  Widget build(BuildContext context) {
    final call = item.call;
    final result = item.result;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (call != null && call.arguments.isNotEmpty)
            _ToolArgumentsTile(
              key: ValueKey('agent-tool-args-${call.id}'),
              text: const JsonEncoder.withIndent('  ').convert(call.arguments),
            ),
          if (result != null) ...[
            AgentChatToolResultTile(
              key: ValueKey('agent-turn-tool-result-${result.toolCallId}'),
              result: result,
              showMedia: false,
              nested: true,
            ),
          ],
        ],
      ),
    );
  }
}

class _ToolArgumentsTile extends StatefulWidget {
  const _ToolArgumentsTile({super.key, required this.text});

  final String text;

  @override
  State<_ToolArgumentsTile> createState() => _ToolArgumentsTileState();
}

class _ToolArgumentsTileState extends State<_ToolArgumentsTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: const ValueKey('agent-tool-arguments-toggle'),
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
            child: Row(
              children: [
                Icon(
                  Icons.tune_rounded,
                  size: 15,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.l10n.generation_params,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Icon(
                  _expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 17,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        if (_expanded) _TranscriptText(text: widget.text),
      ],
    );
  }
}

class _TranscriptText extends StatelessWidget {
  const _TranscriptText({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(maxHeight: 240),
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        key: PageStorageKey('agent-transcript-${text.hashCode}'),
        child: SelectableText(
          text,
          key: PageStorageKey('agent-transcript-text-${text.hashCode}'),
          style: theme.textTheme.bodySmall?.copyWith(
            fontFamily: 'monospace',
            height: 1.45,
          ),
        ),
      ),
    );
  }
}
