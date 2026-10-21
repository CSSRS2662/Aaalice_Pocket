import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../core/agent/resources/agent_chat_resource_reference_codec.dart';
import '../../../core/utils/localization_extension.dart';
import '../../adaptive/interaction_policy.dart';
import '../../../core/utils/token_count_format.dart';
import '../../../core/windowing/agent_chat_layout_contract.dart';
import 'agent_chat_shared_widgets.dart';
import '../../../l10n/app_localizations.dart';
import '../../themes/core/layered_surface_style.dart';
import '../models/agent_chat_slash_command.dart';
import '../providers/agent_chat_state.dart';
import 'agent_chat_access_control.dart';
import 'agent_chat_model_picker.dart';
import 'agent_chat_panel_controller.dart';
import 'agent_chat_panel_view_data.dart';
import 'agent_chat_resource_widgets.dart';
import 'agent_chat_send_button.dart';
import 'agent_chat_slash_menu.dart';

class AgentChatComposer extends StatefulWidget {
  const AgentChatComposer({
    super.key,
    required this.viewData,
    required this.commands,
    required this.controller,
  });

  final AgentChatPanelViewData viewData;
  final AgentChatPanelCommands commands;
  final AgentChatPanelController controller;

  @override
  State<AgentChatComposer> createState() => _AgentChatComposerState();
}

class _AgentChatComposerState extends State<AgentChatComposer> {
  static const _controlGap = 4.0;

  bool _editorExpanded = false;
  int _slashHighlight = 0;
  String? _observedSlashQuery;
  String? _dismissedSlashQuery;

  AgentChatPanelViewData get viewData => widget.viewData;
  AgentChatPanelCommands get commands => widget.commands;
  AgentChatPanelController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.inputController.addListener(_handleSlashQueryChanged);
  }

  @override
  void didUpdateWidget(AgentChatComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.inputController.removeListener(
        _handleSlashQueryChanged,
      );
      controller.inputController.addListener(_handleSlashQueryChanged);
    }
  }

  @override
  void dispose() {
    controller.inputController.removeListener(_handleSlashQueryChanged);
    super.dispose();
  }

  /// 只负责请求重建，派生状态一律在 build 里同步。
  ///
  /// 纯文本改动会经由草稿状态让面板重建，但只移动光标不会——而光标进出片段
  /// 决定菜单开合，所以这里补一次。面板 build 期间的 syncComposerText 也会
  /// 触发本回调，那时本帧重建已在进行，再标脏就是构建期 setState。
  void _handleSlashQueryChanged() {
    if (!mounted) return;
    final query = parseSlashQuery(controller.inputController.value)?.query;
    if (query == _observedSlashQuery) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      return;
    }
    setState(() {});
  }

  void _dismissSlashMenu() {
    setState(() => _dismissedSlashQuery = _observedSlashQuery ?? '');
  }

  /// A long or multi-line draft gets the button that enlarges the editor.
  bool get _draftNeedsRoom {
    final text = controller.inputController.text;
    return text.contains('\n') || text.length > 80;
  }

  void _toggleEditorExpanded() {
    setState(() => _editorExpanded = !_editorExpanded);
    controller.inputFocus.requestFocus();
  }

  void _moveSlashHighlight(int delta, int count) {
    setState(() => _slashHighlight = (_slashHighlight + delta + count) % count);
  }

  /// 技能插入到输入框继续编辑；会话命令没有后续正文，选中即执行。
  ///
  /// 用构建菜单时的 [queryEnd] 而不是重新读实时 selection：鼠标点击会让输入框
  /// 先失焦，此刻 selection 已经失效，再解析必然拿不到片段。
  void _acceptSlashCommand(AgentChatSlashCommand command, int queryEnd) {
    final action = command.sessionAction;
    if (action == null) {
      controller.applySlashCommand(command.name, queryEnd);
      return;
    }
    controller.removeLeadingSlashToken(queryEnd);
    commands.moreAction(action);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final slashCommands = buildSlashCommands(
      skills: viewData.state.skills,
      l10n: l10n,
      sessionActionsEnabled: viewData.sessionActionsEnabled,
    );
    controller.inputController.slashCommandNames = {
      for (final command in slashCommands) command.name.toLowerCase(),
    };
    final slashQuery = viewData.state.initialized
        ? parseSlashQuery(controller.inputController.value)
        : null;
    // 片段变化才重排：光标在片段内平移不该重置选中项，也不该撤销 Esc 之外的
    // 关闭状态。
    if (slashQuery?.query != _observedSlashQuery) {
      _observedSlashQuery = slashQuery?.query;
      _dismissedSlashQuery = null;
      _slashHighlight = 0;
    }
    final slashMatches =
        slashQuery == null || slashQuery.query == _dismissedSlashQuery
        ? const <AgentChatSlashCommand>[]
        : filterSlashCommands(slashCommands, slashQuery.query);
    final slashHighlight = slashMatches.isEmpty
        ? 0
        : _slashHighlight.clamp(0, slashMatches.length - 1);

    return Padding(
      key: const ValueKey('agent-chat-input-container'),
      padding: AgentChatLayoutContract.composerOuterPadding(viewData.width),
      child: SingleChildScrollView(
        primary: false,
        child: Container(
          key: const ValueKey('agent-chat-composer-surface'),
          decoration: BoxDecoration(
            color: controlSurfaceColor(theme.colorScheme),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (viewData.state.queuedMessages.isNotEmpty)
                _queuedMessages(theme, l10n),
              if (controller.isEditingUserMessage)
                _messageEditHeader(theme, l10n),
              if (slashMatches.isNotEmpty)
                AgentChatSlashMenu(
                  commands: slashMatches,
                  highlightIndex: slashHighlight,
                  onSelected: (command) =>
                      _acceptSlashCommand(command, slashQuery!.end),
                  onHighlightChanged: (index) =>
                      setState(() => _slashHighlight = index),
                ),
              if (viewData.state.pendingResources.isNotEmpty ||
                  controller.pendingImages.isNotEmpty)
                _attachmentCards(),
              _editor(
                context,
                theme,
                l10n,
                slashMatches,
                slashHighlight,
                slashQuery?.end ?? 0,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
                child: _composerControls(theme, l10n),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _messageEditHeader(ThemeData theme, AppLocalizations l10n) {
    return Padding(
      key: const ValueKey('agent-chat-message-edit-header'),
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 0),
      child: Row(
        children: [
          Icon(Icons.edit_outlined, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              l10n.common_edit,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            key: const ValueKey('agent-chat-cancel-message-edit'),
            onPressed: commands.cancelUserMessageEdit,
            child: Text(l10n.common_cancel),
          ),
        ],
      ),
    );
  }

  Widget _editor(
    BuildContext context,
    ThemeData theme,
    AppLocalizations l10n,
    List<AgentChatSlashCommand> slashMatches,
    int slashHighlight,
    int slashQueryEnd,
  ) {
    final target = context.interactionPolicy.minimumControlExtent;
    final showExpand = _editorExpanded || _draftNeedsRoom;
    final availableHeight = viewData.height
        .clamp(0, AgentChatComposerLayout.availableViewportHeight(context))
        .toDouble();
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final editor = TextField(
      key: const ValueKey('agent-chat-input'),
      controller: controller.inputController,
      focusNode: controller.inputFocus,
      onTapOutside: (_) => controller.inputFocus.unfocus(),
      enabled: viewData.state.initialized,
      expands: _editorExpanded,
      minLines: _editorExpanded
          ? null
          : AgentChatComposerLayout.collapsedEditorMinLines(
              availableHeight: availableHeight,
              textScale: textScale,
              touchOptimized:
                  context.interactionPolicy.shouldExposeTouchAlternatives,
            ),
      maxLines: _editorExpanded
          ? null
          : AgentChatComposerLayout.collapsedEditorMaxLines(
              availableHeight: availableHeight,
              textScale: textScale,
              touchOptimized:
                  context.interactionPolicy.shouldExposeTouchAlternatives,
            ),
      style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
      textInputAction: TextInputAction.newline,
      textAlignVertical: TextAlignVertical.top,
      decoration: InputDecoration(
        isDense: true,
        hintText: viewData.running
            ? l10n.agentChat_inputHintRunning
            : viewData.state.skills.isEmpty
            ? l10n.agentChat_inputHint
            : l10n.agentChat_inputHintWithSlash,
        hintStyle: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.82),
        ),
        contentPadding: EdgeInsets.fromLTRB(
          viewData.compactWidth ? 14 : 13,
          14,
          showExpand ? target + 6 : 14,
          10,
        ),
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
      ),
    );

    return Focus(
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        final key = event.logicalKey;
        final composing =
            controller.inputController.value.composing.isValid &&
            !controller.inputController.value.composing.isCollapsed;
        // 菜单开着时先于停止运行、队列编辑和发送处理，否则同一个键有两个归属。
        if (slashMatches.isNotEmpty && !composing) {
          if (key == LogicalKeyboardKey.escape) {
            _dismissSlashMenu();
            return KeyEventResult.handled;
          }
          if (!HardwareKeyboard.instance.isAltPressed &&
              (key == LogicalKeyboardKey.arrowDown ||
                  key == LogicalKeyboardKey.arrowUp)) {
            _moveSlashHighlight(
              key == LogicalKeyboardKey.arrowDown ? 1 : -1,
              slashMatches.length,
            );
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.tab ||
              ((key == LogicalKeyboardKey.enter ||
                      key == LogicalKeyboardKey.numpadEnter) &&
                  !HardwareKeyboard.instance.isShiftPressed &&
                  !HardwareKeyboard.instance.isControlPressed &&
                  !HardwareKeyboard.instance.isMetaPressed)) {
            _acceptSlashCommand(slashMatches[slashHighlight], slashQueryEnd);
            return KeyEventResult.handled;
          }
        }
        if (key == LogicalKeyboardKey.escape && viewData.running) {
          commands.stop();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowUp &&
            HardwareKeyboard.instance.isAltPressed &&
            viewData.state.queuedMessages.isNotEmpty) {
          commands.editQueuedMessage(viewData.state.queuedMessages.last);
          return KeyEventResult.handled;
        }
        if (key != LogicalKeyboardKey.enter &&
            key != LogicalKeyboardKey.numpadEnter) {
          return KeyEventResult.ignored;
        }
        if (controller.inputController.value.composing.isValid &&
            !controller.inputController.value.composing.isCollapsed) {
          return KeyEventResult.ignored;
        }
        if (HardwareKeyboard.instance.isShiftPressed ||
            HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed) {
          controller.insertNewline();
          return KeyEventResult.handled;
        }
        // With touch and no mouse (a phone's soft keyboard) Enter starts a
        // new line and the button sends.
        final policy = context.interactionPolicy;
        if (policy.touchAvailable && !policy.precisePointerAvailable) {
          return KeyEventResult.ignored;
        }
        if (viewData.canSend &&
            (controller.inputController.text.trim().isNotEmpty ||
                controller.pendingImages.isNotEmpty)) {
          commands.send();
        }
        return KeyEventResult.handled;
      },
      child: Stack(
        children: [
          SizedBox(
            key: const ValueKey('agent-chat-composer-editor'),
            height: _editorExpanded
                ? AgentChatComposerLayout.expandedEditorHeight(
                    availableHeight: availableHeight,
                    touchOptimized:
                        context.interactionPolicy.shouldExposeTouchAlternatives,
                  )
                : null,
            child: editor,
          ),
          if (showExpand)
            Positioned(
              top: 6,
              right: 6,
              child: AgentChatComposerExpandButton(
                key: const ValueKey('agent-chat-composer-expand'),
                expanded: _editorExpanded,
                touchOptimized:
                    context.interactionPolicy.shouldExposeTouchAlternatives,
                expandLabel:
                    '${l10n.common_expand} · ${l10n.agentChat_inputHint}',
                collapseLabel:
                    '${l10n.common_collapse} · ${l10n.agentChat_inputHint}',
                onPressed: _toggleEditorExpanded,
              ),
            ),
        ],
      ),
    );
  }

  Widget _composerControls(ThemeData theme, AppLocalizations l10n) {
    return LayoutBuilder(
      key: const ValueKey('agent-chat-composer-controls'),
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final hasDraft =
            controller.inputController.text.trim().isNotEmpty ||
            controller.pendingImages.isNotEmpty;
        // The ring is the first to go when very narrow or enlarged text
        // leaves no room for the model name.
        final showContext = constraints.maxWidth >= 260;
        final showModelName = constraints.maxWidth >= 300 && textScale < 2;
        final controls = Row(
          key: const ValueKey('agent-chat-composer-status-row'),
          children: [
            _attachmentSourceButton(theme, l10n),
            // The model takes what the row leaves; the access chip follows it.
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: _configurationSelector(showModelName: showModelName),
                  ),
                  _accessControl(),
                ],
              ),
            ),
            if (showContext)
              SizedBox(
                width: context.interactionPolicy.minimumControlExtent,
                child: _contextIndicator(theme, l10n),
              ),
            const SizedBox(width: _controlGap),
            AgentChatSendButton(
              running: viewData.running,
              hasDraft: hasDraft,
              canSend: viewData.canSend,
              disabledReason: hasDraft
                  ? l10n.agentChat_sendUnavailableHint
                  : l10n.agentChat_sendEmptyHint,
              onSend: commands.send,
              onStop: commands.stop,
              onSendAfterRun: commands.sendFollowUp,
            ),
          ],
        );

        return SizedBox(
          key: const ValueKey('agent-chat-session-controls'),
          width: double.infinity,
          child: KeyedSubtree(
            key: const ValueKey('agent-chat-message-actions'),
            child: controls,
          ),
        );
      },
    );
  }

  Widget _contextIndicator(
    ThemeData theme,
    AppLocalizations l10n, {
    bool showLabel = false,
  }) {
    final usage = viewData.state.contextUsage;
    final tokens = usage.tokens;
    final window = usage.contextWindow;
    final available = usage.available;
    final loading =
        viewData.state.compacting ||
        viewData.state.sessionContentLoading ||
        (!viewData.state.routeReady && viewData.state.routeError.isEmpty);
    final percent = usage.percent?.clamp(0, 999).round();
    final label = loading
        ? viewData.state.compacting
              ? l10n.agentChat_compacting
              : l10n.common_loading
        : available
        ? '$percent% · ${usage.estimated ? '~' : ''}${formatTokenCount(tokens!)} / ${formatTokenCount(window!)}'
        : l10n.agentChat_contextUnavailable;
    final onPressed = available && !loading && viewData.sessionActionsEnabled
        ? () => commands.moreAction(AgentChatMoreAction.compact)
        : null;
    final target = context.interactionPolicy.minimumControlExtent;
    final meterColor = available && percent != null && percent >= 100
        ? theme.colorScheme.error
        : available && percent != null && percent >= 80
        ? theme.colorScheme.tertiary
        : theme.colorScheme.primary;

    return Semantics(
      button: onPressed != null,
      label: label,
      value: percent == null ? null : '$percent%',
      child: Tooltip(
        message: label,
        child: Material(
          key: const ValueKey('agent-chat-context-surface'),
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              key: const ValueKey('agent-chat-context-target'),
              constraints: BoxConstraints(minHeight: target),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: showLabel ? 10 : 0),
                child: Row(
                  mainAxisSize: showLabel ? MainAxisSize.max : MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox.square(
                      key: const ValueKey('agent-chat-context-ring'),
                      dimension: 30,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Positioned.fill(
                            child: loading
                                ? CircularProgressIndicator(
                                    key: const ValueKey(
                                      'agent-chat-context-loading',
                                    ),
                                    strokeWidth: 3,
                                    value:
                                        MediaQuery.disableAnimationsOf(context)
                                        ? 0.75
                                        : null,
                                    color: meterColor,
                                    backgroundColor: theme
                                        .colorScheme
                                        .onSurfaceVariant
                                        .withValues(alpha: 0.3),
                                  )
                                : CircularProgressIndicator(
                                    strokeWidth: 3,
                                    value: available
                                        ? (tokens! / window!).clamp(0.0, 1.0)
                                        : 0,
                                    color: meterColor,
                                    backgroundColor: theme
                                        .colorScheme
                                        .onSurfaceVariant
                                        .withValues(alpha: 0.3),
                                  ),
                          ),
                          ExcludeSemantics(
                            child: MediaQuery.withClampedTextScaling(
                              maxScaleFactor: 1.2,
                              child: Text(
                                loading
                                    ? '…'
                                    : available
                                    ? '$percent%'
                                    : '—',
                                key: loading
                                    ? const ValueKey(
                                        'agent-chat-context-loading-label',
                                      )
                                    : available
                                    ? const ValueKey(
                                        'agent-chat-context-token-label',
                                      )
                                    : const ValueKey(
                                        'agent-chat-context-unavailable',
                                      ),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: available
                                      ? theme.colorScheme.onSurface
                                      : theme.colorScheme.onSurfaceVariant,
                                  fontSize: 9,
                                  height: 1,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (showLabel) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          loading
                              ? (viewData.state.compacting
                                    ? l10n.agentChat_compacting
                                    : l10n.common_loading)
                              : '${l10n.agentChat_contextUsageLabel} · ${available ? '$percent%' : '—'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: available
                                ? theme.colorScheme.onSurface
                                : theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Messages waiting while the agent works, one row each at the top of the
  /// composer: guidance joins the work before its next step, the rest goes
  /// out after it. Each can be taken back to edit or withdrawn.
  Widget _queuedMessages(ThemeData theme, AppLocalizations l10n) {
    final queued = viewData.state.queuedMessages;
    final target = context.interactionPolicy.minimumControlExtent;
    return Padding(
      key: const ValueKey('agent-chat-queue'),
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: target * 3),
        child: ListView.builder(
          key: const PageStorageKey('agent-chat-queue-list'),
          primary: false,
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: queued.length,
          itemBuilder: (context, index) {
            final item = queued[index];
            final steering = item.kind == AgentQueuedMessageKind.steering;
            return Container(
              key: ValueKey('agent-chat-queue-item-$index'),
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.only(left: 10),
              decoration: BoxDecoration(
                color: sectionSurfaceColor(theme.colorScheme),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(
                    steering ? Icons.alt_route_rounded : Icons.schedule_rounded,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    steering ? l10n.agentChat_steerTag : l10n.agentChat_queued,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Tooltip(
                      message: steering
                          ? l10n.agentChat_queueSteering
                          : l10n.agentChat_queueFollowUp,
                      child: Text(
                        item.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ),
                  IconButton(
                    key: ValueKey('agent-chat-queue-edit-$index'),
                    tooltip: l10n.common_edit,
                    onPressed: () async {
                      await commands.editQueuedMessage(item);
                    },
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    constraints: BoxConstraints.tightFor(
                      width: target,
                      height: target,
                    ),
                  ),
                  IconButton(
                    key: ValueKey('agent-chat-queue-remove-$index'),
                    tooltip: l10n.common_delete,
                    onPressed: () async {
                      await commands.removeQueuedMessage(item);
                    },
                    icon: const Icon(Icons.close_rounded, size: 16),
                    constraints: BoxConstraints.tightFor(
                      width: target,
                      height: target,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _attachmentCards() {
    final imageCount = controller.pendingImages.length;
    return SizedBox(
      key: const ValueKey('agent-chat-attachment-strip'),
      height: viewData.compactWidth ? 66 : 58,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
        scrollDirection: Axis.horizontal,
        itemCount: imageCount + viewData.state.pendingResources.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          if (index < imageCount) {
            return AgentChatPendingImageCard(
              image: controller.pendingImages[index],
              compactLayout: viewData.compactWidth,
              onRemove: () => controller.removePendingImage(index),
            );
          }
          final resourceIndex = index - imageCount;
          final reference = viewData.state.pendingResources[resourceIndex];
          final unavailable = viewData.state.unavailableResourceKeys.contains(
            AgentChatResourceReferenceCodec.encodeJson(reference),
          );
          return AgentChatPendingResourceCard(
            reference: reference,
            loadPreview: () => commands.resolveResourcePreview(reference),
            unavailable: unavailable,
            compactLayout: viewData.compactWidth,
            onRemove: () => commands.removePendingResource(resourceIndex),
          );
        },
      ),
    );
  }

  Widget _attachmentSourceButton(ThemeData theme, AppLocalizations l10n) {
    final child = Container(
      width: context.interactionPolicy.minimumControlExtent,
      height: context.interactionPolicy.minimumControlExtent,
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Icon(
        Icons.add,
        size: 18,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
      ),
    );
    if (context.interactionPolicy.prefersTouchPresentation) {
      return Semantics(
        key: const ValueKey('agent-chat-more-actions'),
        button: true,
        label: l10n.agentChat_addAttachment,
        child: InkWell(
          onTap: viewData.state.initialized
              ? () => _showMobileAttachmentSources(l10n)
              : null,
          borderRadius: BorderRadius.circular(9),
          child: child,
        ),
      );
    }
    return PopupMenuButton<AgentChatAttachmentAction>(
      key: const ValueKey('agent-chat-more-actions'),
      tooltip: l10n.agentChat_addAttachment,
      padding: EdgeInsets.zero,
      enabled: viewData.state.initialized,
      onSelected: _handleAttachmentAction,
      itemBuilder: (_) => [
        _attachmentItem(
          AgentChatAttachmentAction.images,
          Icons.photo_library_outlined,
          l10n.agentChat_photoLibrary,
        ),
        _attachmentItem(
          AgentChatAttachmentAction.currentCanvas,
          Icons.crop_free_rounded,
          l10n.agentChat_currentCanvas,
          enabled: viewData.currentCanvasReference != null,
        ),
        _attachmentItem(
          AgentChatAttachmentAction.referenceGallery,
          Icons.collections_outlined,
          l10n.agentChat_referenceGallery,
        ),
        _attachmentItem(
          AgentChatAttachmentAction.resourceLibrary,
          Icons.bookmarks_outlined,
          l10n.agentChat_resourceLibrary,
        ),
      ],
      child: child,
    );
  }

  PopupMenuItem<AgentChatAttachmentAction> _attachmentItem(
    AgentChatAttachmentAction action,
    IconData icon,
    String label, {
    bool enabled = true,
  }) => PopupMenuItem(
    value: action,
    enabled: enabled,
    height: 44,
    child: Row(
      children: [
        Icon(icon, size: 19),
        const SizedBox(width: 10),
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    ),
  );

  Future<void> _showMobileAttachmentSources(AppLocalizations l10n) async {
    final context = controller.inputFocus.context;
    if (context == null) return;
    controller.inputFocus.unfocus();
    final action = await showModalBottomSheet<AgentChatAttachmentAction>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: 12,
          right: 12,
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + 12,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _mobileAttachmentTile(
              sheetContext,
              AgentChatAttachmentAction.images,
              Icons.photo_library_outlined,
              l10n.agentChat_photoLibrary,
            ),
            _mobileAttachmentTile(
              sheetContext,
              AgentChatAttachmentAction.currentCanvas,
              Icons.crop_free_rounded,
              l10n.agentChat_currentCanvas,
              enabled: viewData.currentCanvasReference != null,
            ),
            _mobileAttachmentTile(
              sheetContext,
              AgentChatAttachmentAction.referenceGallery,
              Icons.collections_outlined,
              l10n.agentChat_referenceGallery,
            ),
            _mobileAttachmentTile(
              sheetContext,
              AgentChatAttachmentAction.resourceLibrary,
              Icons.bookmarks_outlined,
              l10n.agentChat_resourceLibrary,
            ),
          ],
        ),
      ),
    );
    if (action != null) await _handleAttachmentAction(action);
  }

  Widget _mobileAttachmentTile(
    BuildContext context,
    AgentChatAttachmentAction action,
    IconData icon,
    String label, {
    bool enabled = true,
  }) => ListTile(
    minTileHeight: 48,
    enabled: enabled,
    leading: Icon(icon),
    title: Text(label),
    onTap: enabled ? () => Navigator.pop(context, action) : null,
  );

  Future<void> _handleAttachmentAction(AgentChatAttachmentAction action) {
    return switch (action) {
      AgentChatAttachmentAction.images => commands.pickImages(),
      AgentChatAttachmentAction.currentCanvas => commands.attachCurrentCanvas(),
      AgentChatAttachmentAction.referenceGallery =>
        commands.openReferenceGallery(),
      AgentChatAttachmentAction.resourceLibrary =>
        commands.openResourceLibrary(),
    };
  }

  Widget _accessControl() => AgentChatAccessControl(
    mode: viewData.agentSettings.settings.chat.permissionMode,
    webAccessEnabled: viewData.agentSettings.settings.chat.webAccessEnabled,
    webAccessAvailable:
        viewData.webAccess.initialized && _agentSettingsInteractive,
    enabled: _agentSettingsInteractive,
    onModeSelected: commands.selectPermissionMode,
    onWebAccessChanged: (value) => commands.setWebAccessEnabled(value),
  );

  Widget _configurationSelector({required bool showModelName}) =>
      AgentChatConfigurationControl(
        config: viewData.config,
        agentSettings: viewData.agentSettings,
        routeLabel: viewData.state.routeLabel,
        routeError: viewData.state.routeError,
        thinkingLevel: viewData.state.thinkingLevel,
        availableThinkingLevels: viewData.state.availableThinkingLevels,
        enabled: viewData.sessionActionsEnabled && _agentSettingsInteractive,
        onModelSelected: commands.selectModel,
        onThinkingSelected: commands.selectThinkingLevel,
        restoreFocusNode: controller.inputFocus,
        showModelName: showModelName,
        fastModeEnabled: viewData.fastModeEnabled,
        onFastModeChanged: commands.setFastModeEnabled,
      );

  bool get _agentSettingsInteractive =>
      viewData.agentSettings.initialized &&
      viewData.agentSettings.error.isEmpty &&
      !viewData.controlsLocked;
}
