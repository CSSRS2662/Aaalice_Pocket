import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../widgets/common/image_viewport_surface.dart';
import '../../../core/agent/agent_types.dart';
import '../../../core/agent/resources/agent_chat_resource_reference.dart';
import '../../../core/agent/resources/agent_chat_resource_reference_codec.dart';
import '../../../core/utils/localization_extension.dart';
import '../../../core/windowing/agent_chat_layout_contract.dart';
import 'agent_chat_shared_widgets.dart';
import '../../adaptive/interaction_policy.dart';
import '../../themes/core/layered_surface_style.dart';
import '../../widgets/common/draggable_memory_image.dart';
import '../models/agent_chat_prompt_envelope.dart';
import '../providers/agent_chat_notifier.dart';
import 'agent_chat_panel_controller.dart';
import 'agent_chat_panel_view_data.dart';
import 'agent_chat_history.dart';
import 'agent_chat_resource_widgets.dart';
import 'agent_chat_tool_widgets.dart';
import 'agent_chat_turn.dart';
import 'agent_chat_work_process.dart';

class AgentChatMessages extends StatelessWidget {
  const AgentChatMessages({
    super.key,
    required this.viewData,
    required this.commands,
    required this.controller,
  });

  final AgentChatPanelViewData viewData;
  final AgentChatPanelCommands commands;
  final AgentChatPanelController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = viewData.state;
    if (!state.initialized || state.sessionContentLoading) {
      return Center(
        child: Semantics(
          liveRegion: true,
          label: context.l10n.common_loading,
          child: SizedBox(
            key: const ValueKey('agent-chat-session-loading'),
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              value: MediaQuery.disableAnimationsOf(context) ? 0.75 : null,
            ),
          ),
        ),
      );
    }
    if (viewData.isEmpty && !state.routeReady) {
      return _setupHint(context, theme);
    }
    if (viewData.isEmpty) {
      return _hero(context, theme);
    }
    final lastAssistantMessageIndex = state.messages.lastIndexWhere(
      (message) =>
          message is AssistantMessage &&
          message.toolCalls.isEmpty &&
          message.stopReason != StopReason.toolUse &&
          message.text.trim().isNotEmpty,
    );
    final lastUserMessageIndex = state.messages.lastIndexWhere(
      isVisualUserMessage,
    );
    final canEditLastUserMessage =
        !viewData.running &&
        !state.sessionTransitioning &&
        state.queuedMessages.isEmpty &&
        state.pendingResources.isEmpty;
    final thread = AgentChatThreadModel.fromMessages(
      state.messages,
      timeline: state.turns,
    );
    final streaming = state.streamingMessage;
    final streamingUsesTools =
        streaming != null &&
        (streaming.toolCalls.isNotEmpty ||
            streaming.stopReason == StopReason.toolUse);
    final liveThinking = streaming == null
        ? ''
        : streaming.content
              .whereType<AssistantThinkingContent>()
              .map((content) => content.thinking.trim())
              .where((text) => text.isNotEmpty)
              .join('\n\n');
    final liveNarration = streamingUsesTools ? streaming.text.trim() : '';
    if (thread.turns.isEmpty &&
        (state.streamingMessage != null ||
            state.status == AgentChatRunStatus.running ||
            state.activities.isNotEmpty)) {
      thread.turns.add(
        AgentChatTurnModel(
          ordinal: 0,
          timeline: state.turns.isEmpty ? null : state.turns.last,
        ),
      );
    }
    return Stack(
      children: [
        AgentChatThreadViewport(
          sessionId: state.activeSessionId,
          turns: thread.turns,
          controller: controller,
          horizontalPadding:
              AgentChatLayoutContract.transcriptHorizontalPadding(
                viewData.width,
              ),
          maxWidth: AgentChatLayoutContract.transcriptMaxWidth(viewData.width),
          compactLayout: viewData.compactWidth,
          hasEarlier: state.hasEarlierTurns,
          historyLoading: state.historyLoading,
          prependAnchorEntryId: state.prependAnchorEntryId,
          onLoadEarlier: commands.loadEarlierHistory,
          live: const SizedBox.shrink(),
          turnBuilder: (context, turn, current) => Column(
            key: ValueKey('agent-turn-content-${turn.ordinal}'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (turn.userMessage != null)
                _messageTile(
                  context,
                  theme,
                  turn.userMessage!,
                  messageIndex: turn.userMessageIndex,
                  isLastAssistantMessage: false,
                  canEditUserMessage:
                      canEditLastUserMessage &&
                      turn.userMessageIndex == lastUserMessageIndex,
                ),
              AgentChatWorkProcess(
                turn: turn,
                running: current && state.status == AgentChatRunStatus.running,
                activities: current ? state.activities : const [],
                liveNarration: current ? liveNarration : '',
                liveThinking: current ? liveThinking : '',
                awaitingApproval: current && state.approvalRequest != null,
              ),
              for (final result in turn.mediaResults)
                AgentChatToolResultMedia(result: result),
              for (final finalMessage in turn.finalMessages)
                _messageTile(
                  context,
                  theme,
                  finalMessage.message,
                  messageIndex: finalMessage.index,
                  isLastAssistantMessage:
                      finalMessage.index == lastAssistantMessageIndex,
                  showReasoning: false,
                ),
              if (current && streaming != null && !streamingUsesTools)
                _streamingFinalTile(context, theme, streaming),
            ],
          ),
        ),
        if (controller.showJumpToLatest)
          Positioned(
            right: viewData.compactWidth ? 16 : 10,
            bottom: 10,
            child: FilledButton.tonalIcon(
              key: const ValueKey('agent-chat-jump-to-latest'),
              onPressed: controller.followLatest,
              icon: const Icon(Icons.arrow_downward_rounded, size: 16),
              label: Text(context.l10n.agentChat_jumpToLatest),
              style: FilledButton.styleFrom(
                minimumSize: Size(
                  0,
                  context.interactionPolicy.minimumControlExtent,
                ),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
      ],
    );
  }

  Widget _hero(BuildContext context, ThemeData theme) {
    final l10n = context.l10n;
    final colors = theme.colorScheme;
    final suggestions = [
      (Icons.tune_rounded, l10n.agentChat_suggestion1),
      (Icons.image_search_outlined, l10n.agentChat_suggestion2),
      (Icons.sell_outlined, l10n.agentChat_suggestion3),
    ];
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    size: 26,
                    color: colors.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.agentChat_heroTitle,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                l10n.agentChat_heroSubtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 22),
              for (final (index, (icon, text)) in suggestions.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: sectionSurfaceColor(colors),
                    borderRadius: BorderRadius.circular(12),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      key: ValueKey('agent-chat-suggestion-$index'),
                      onTap: () => commands.useSuggestion(text),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 52),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                icon,
                                size: 19,
                                color: colors.onSurfaceVariant,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  text,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    height: 1.35,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                Icons.north_east_rounded,
                                size: 16,
                                color: colors.outline,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _setupHint(BuildContext context, ThemeData theme) {
    final compact = viewData.compactHeight;
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 20 : 28,
          vertical: compact ? 12 : 24,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: compact ? 52 : 64,
                height: compact ? 52 : 64,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(
                    alpha: 0.7,
                  ),
                  borderRadius: BorderRadius.circular(compact ? 16 : 20),
                ),
                child: Icon(
                  Icons.smart_toy_outlined,
                  size: compact ? 26 : 32,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              SizedBox(height: compact ? 12 : 18),
              Text(
                context.l10n.settings_promptAssistant,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                context.l10n.agentChat_needSetup,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
                textAlign: TextAlign.center,
              ),
              if (viewData.onOpenSettings != null) ...[
                SizedBox(height: compact ? 14 : 22),
                FilledButton.icon(
                  key: const ValueKey('agent-chat-open-settings'),
                  onPressed: viewData.onOpenSettings,
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: Text(context.l10n.promptAssistant_assistantSettings),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _messageTile(
    BuildContext context,
    ThemeData theme,
    Message message, {
    required int messageIndex,
    required bool isLastAssistantMessage,
    bool showReasoning = true,
    bool canEditUserMessage = false,
    Message? editSourceMessage,
    List<AgentChatResourceReference> resourceReferences = const [],
  }) {
    final envelope = asAgentPromptEnvelope(message);
    if (envelope != null) {
      return _messageTile(
        context,
        theme,
        visibleUserMessage(message)!,
        messageIndex: messageIndex,
        isLastAssistantMessage: isLastAssistantMessage,
        showReasoning: showReasoning,
        canEditUserMessage: canEditUserMessage,
        editSourceMessage: message,
        resourceReferences: _decodeResourceReferences(envelope.details),
      );
    }
    if (message is UserMessage) {
      final hasText = message.text.trim().isNotEmpty;
      final hovered = controller.hoveredUserMessageIndex == messageIndex;
      final actionsFocused = controller.focusedUserMessageIndex == messageIndex;
      final hasBubbleContent = hasText || message.images.isNotEmpty;
      // Touch opens the actions from a long press instead of a row under
      // every message.
      final touchMenu = context.interactionPolicy.usesTouchActionMenu;
      void showActions() => _showUserMessageActions(
        context,
        message: message,
        editSource: editSourceMessage ?? message,
        messageIndex: messageIndex,
        canEdit: canEditUserMessage && !controller.isEditingUserMessage,
      );
      return MouseRegion(
        key: ValueKey('agent-user-message-$messageIndex'),
        onEnter: (_) => controller.setHoveredUserMessageIndex(messageIndex),
        onExit: (_) {
          if (controller.hoveredUserMessageIndex == messageIndex) {
            controller.setHoveredUserMessageIndex(null);
          }
        },
        child: Align(
          alignment: Alignment.centerRight,
          child: GestureDetector(
            key: ValueKey('agent-user-message-press-$messageIndex'),
            onLongPress: touchMenu ? showActions : null,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 6, left: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (resourceReferences.isNotEmpty)
                    ConstrainedBox(
                      key: ValueKey(
                        'agent-user-message-resources-$messageIndex',
                      ),
                      constraints: BoxConstraints(
                        maxWidth: viewData.userBubbleMaxWidth,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Wrap(
                          spacing: 5,
                          runSpacing: 4,
                          alignment: WrapAlignment.end,
                          children: [
                            for (
                              var index = 0;
                              index < resourceReferences.length;
                              index++
                            )
                              AgentChatSentResourceCard(
                                key: ValueKey(
                                  'agent-user-message-resource-'
                                  '$messageIndex-$index',
                                ),
                                reference: resourceReferences[index],
                                loadPreview: () =>
                                    commands.resolveResourcePreview(
                                      resourceReferences[index],
                                    ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  if (hasBubbleContent)
                    Container(
                      key: ValueKey('agent-user-message-bubble-$messageIndex'),
                      constraints: BoxConstraints(
                        minWidth: hasText ? 44 : 0,
                        maxWidth: viewData.userBubbleMaxWidth,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: controlSurfaceColor(theme.colorScheme),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(18),
                          topRight: Radius.circular(18),
                          bottomLeft: Radius.circular(18),
                          bottomRight: Radius.circular(6),
                        ),
                      ),
                      child: IntrinsicWidth(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (message.images.isNotEmpty)
                              Padding(
                                padding: EdgeInsets.only(
                                  bottom: hasText ? 6 : 0,
                                ),
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  alignment: WrapAlignment.end,
                                  children: [
                                    for (final image in message.images)
                                      _userImage(
                                        theme,
                                        image,
                                        maxWidth:
                                            viewData.userBubbleMaxWidth - 24,
                                      ),
                                  ],
                                ),
                              ),
                            if (hasText)
                              Text(
                                message.text,
                                key: ValueKey(
                                  'agent-user-message-text-$messageIndex',
                                ),
                                textAlign: TextAlign.left,
                                style:
                                    (viewData.compactWidth
                                            ? theme.textTheme.bodyMedium
                                            : theme.textTheme.bodySmall)
                                        ?.copyWith(
                                          color: theme.colorScheme.onSurface,
                                          height: 1.5,
                                        ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  if (!touchMenu)
                    Focus(
                      onFocusChange: (focused) =>
                          controller.setFocusedUserMessageIndex(
                            focused ? messageIndex : null,
                          ),
                      child: SizedBox(
                        height: context.interactionPolicy.minimumControlExtent,
                        child: AnimatedOpacity(
                          key: ValueKey(
                            'agent-user-message-actions-$messageIndex',
                          ),
                          opacity: hovered || actionsFocused ? 1 : 0,
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 120),
                          child: IgnorePointer(
                            ignoring: !hovered && !actionsFocused,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (canEditUserMessage)
                                  _MessageActionButton(
                                    key: ValueKey(
                                      'agent-user-message-edit-$messageIndex',
                                    ),
                                    tooltip: context.l10n.common_edit,
                                    icon: Icons.edit_outlined,
                                    onPressed: controller.isEditingUserMessage
                                        ? null
                                        : () => commands.editUserMessage(
                                            editSourceMessage ?? message,
                                            messageIndex,
                                          ),
                                  ),
                                _MessageActionButton(
                                  key: ValueKey(
                                    'agent-user-message-copy-$messageIndex',
                                  ),
                                  tooltip: context.l10n.common_copy,
                                  icon: Icons.copy_all_outlined,
                                  onPressed: () =>
                                      commands.copyUserMessage(message),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    if (message is AssistantMessage) {
      final thinking = message.content
          .whereType<AssistantThinkingContent>()
          .map((content) => content.thinking)
          .join();
      if (message.text.trim().isEmpty && thinking.trim().isEmpty) {
        return const SizedBox.shrink();
      }
      return Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: viewData.assistantMaxWidth.clamp(0, 680),
          ),
          child: Padding(
            padding: const EdgeInsets.only(right: 8, bottom: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showReasoning && thinking.trim().isNotEmpty)
                  AgentChatReasoningTile(thinking: thinking),
                if (message.text.trim().isNotEmpty)
                  _assistantMarkdown(context, message.text),
                if (message.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    key: ValueKey(
                      'agent-assistant-message-footer-$messageIndex',
                    ),
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _AssistantActionBar(
                        messageIndex: messageIndex,
                        onCopy: () => commands.copyAssistantMessage(message),
                        onRetry: isLastAssistantMessage && !viewData.running
                            ? commands.retryLastMessage
                            : null,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }
    if (message is ToolResultMessage) {
      return AgentChatToolResultTile(result: message);
    }
    return const SizedBox.shrink();
  }

  /// The actions of a user message on touch, opened by a long press.
  Future<void> _showUserMessageActions(
    BuildContext context, {
    required UserMessage message,
    required Message editSource,
    required int messageIndex,
    required bool canEdit,
  }) async {
    final l10n = context.l10n;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: ValueKey('agent-user-message-copy-$messageIndex'),
              leading: const Icon(Icons.copy_all_outlined),
              title: Text(l10n.common_copy),
              onTap: () {
                Navigator.pop(sheetContext);
                commands.copyUserMessage(message);
              },
            ),
            if (canEdit)
              ListTile(
                key: ValueKey('agent-user-message-edit-$messageIndex'),
                leading: const Icon(Icons.edit_outlined),
                title: Text(l10n.common_edit),
                onTap: () {
                  Navigator.pop(sheetContext);
                  commands.editUserMessage(editSource, messageIndex);
                },
              ),
          ],
        ),
      ),
    );
  }

  List<AgentChatResourceReference> _decodeResourceReferences(Object? details) {
    if (details is! Map || details['references'] is! List) return const [];
    final references = <AgentChatResourceReference>[];
    for (final value in details['references'] as List) {
      if (value is! Map) continue;
      try {
        references.add(
          AgentChatResourceReferenceCodec.decodeJsonMap(
            Map<String, dynamic>.from(value),
          ),
        );
      } on FormatException {
        continue;
      }
    }
    return references;
  }

  Widget _userImage(
    ThemeData theme,
    ImageContent image, {
    required double maxWidth,
  }) {
    final source = image.source;
    final bytes = controller.bytesForMessageImage(source);
    final Size size;
    final Widget imageWidget;
    if (bytes != null) {
      size = controller.displaySizeForMessageImage(source, bytes);
      imageWidget = Image.memory(
        bytes,
        width: size.width,
        height: size.height,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => _brokenImage(theme),
      );
    } else if (source.url case final url?) {
      size = const Size(180, 140);
      imageWidget = Image.network(
        url,
        width: size.width,
        height: size.height,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => _brokenImage(theme),
      );
    } else {
      size = const Size(160, 120);
      imageWidget = _brokenImage(theme);
    }
    final scale = size.width > maxWidth ? maxWidth / size.width : 1.0;
    final displaySize = Size(size.width * scale, size.height * scale);
    final content = SizedBox(
      width: displaySize.width,
      height: displaySize.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ImageViewportSurface(child: imageWidget),
      ),
    );
    if (bytes == null) return content;
    return DraggableMemoryImage(
      imageBytes: bytes,
      fileName: _agentChatImageFileName(source.mimeType, 'attachment'),
      localData: _agentChatImageDragLocalData,
      feedbackWidth: 200,
      child: content,
    );
  }

  Widget _markdownImage(Uri uri, String? alt) {
    Uint8List? dataBytes;
    if (uri.scheme.toLowerCase() == 'data') {
      try {
        final key = uri.toString();
        dataBytes = controller.markdownDataImageBytes.putIfAbsent(
          key,
          () => uri.data!.contentAsBytes(),
        );
      } catch (_) {}
    }
    return AgentChatMarkdownImage(uri: uri, alt: alt, dataBytes: dataBytes);
  }

  Widget _assistantMarkdown(BuildContext context, String text) =>
      AgentChatMarkdownContent(
        text: text,
        touchOptimized: context.interactionPolicy.shouldExposeTouchAlternatives,
        imageBuilder: (uri, _, alt) => _markdownImage(uri, alt),
      );

  Widget _brokenImage(ThemeData theme) => const ColoredBox(
    color: ImageViewportSurface.background,
    child: Center(
      child: Icon(
        Icons.broken_image_outlined,
        size: 20,
        color: ImageViewportSurface.mutedForeground,
      ),
    ),
  );

  Widget _streamingFinalTile(
    BuildContext context,
    ThemeData theme,
    AssistantMessage streaming,
  ) {
    if (streaming.text.trim().isEmpty) return const SizedBox.shrink();
    return RepaintBoundary(
      key: const ValueKey('agent-streaming-final'),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: viewData.assistantMaxWidth.clamp(0, 680),
        ),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 14, right: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _assistantMarkdown(context, streaming.text),
              const SizedBox(height: 8),
              _StreamingStatus(theme: theme),
            ],
          ),
        ),
      ),
    );
  }
}

class _StreamingStatus extends StatelessWidget {
  const _StreamingStatus({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: context.l10n.agentChat_phaseResponding,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 10,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              value: MediaQuery.disableAnimationsOf(context) ? 0.75 : null,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            context.l10n.agentChat_phaseResponding,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _AssistantActionBar extends StatelessWidget {
  const _AssistantActionBar({
    required this.messageIndex,
    required this.onCopy,
    required this.onRetry,
  });

  final int messageIndex;
  final VoidCallback onCopy;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    // 两个图标与同行的时间戳一样属于消息附属信息，不承载独立层级，
    // 因此不铺色面；按钮自身的 hover 与按压反馈已足够表达可点。
    return Row(
      key: ValueKey('agent-assistant-message-actions-$messageIndex'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _MessageActionButton(
          key: ValueKey('agent-assistant-message-copy-$messageIndex'),
          tooltip: context.l10n.common_copy,
          icon: Icons.copy_all_outlined,
          largeHitArea: true,
          onPressed: onCopy,
        ),
        _MessageActionButton(
          key: ValueKey('agent-assistant-message-retry-$messageIndex'),
          tooltip: context.l10n.common_retry,
          icon: Icons.refresh_rounded,
          largeHitArea: true,
          onPressed: onRetry,
        ),
      ],
    );
  }
}

const Map<String, Object> _agentChatImageDragLocalData = {
  'source': 'agent_chat_internal',
};

String _agentChatImageFileName(String? mimeType, String stem) {
  final extension = switch (mimeType) {
    'image/jpeg' => 'jpg',
    'image/webp' => 'webp',
    'image/gif' => 'gif',
    'image/bmp' => 'bmp',
    _ => 'png',
  };
  return '$stem.$extension';
}

class _MessageActionButton extends StatelessWidget {
  const _MessageActionButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.largeHitArea = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool largeHitArea;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dimension = largeHitArea
        ? 48.0
        : context.interactionPolicy.minimumControlExtent;
    return SizedBox.square(
      dimension: dimension,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
        disabledColor: theme.colorScheme.onSurfaceVariant.withValues(
          alpha: 0.28,
        ),
        constraints: BoxConstraints.expand(width: dimension, height: dimension),
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          minimumSize: Size.square(dimension),
          maximumSize: Size.square(dimension),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        // Agent density changes spacing, not accessible pointer target sizes.
        visualDensity: VisualDensity.standard,
      ),
    );
  }
}
