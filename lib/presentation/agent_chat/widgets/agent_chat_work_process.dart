import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/utils/localization_extension.dart';
import '../../adaptive/interaction_policy.dart';
import '../../themes/core/layered_surface_style.dart';
import '../models/agent_chat_turn_timeline.dart';
import '../providers/agent_chat_state.dart';
import 'agent_chat_tool_widgets.dart';
import 'agent_chat_turn.dart';

/// One stage of a turn's work: what the agent said it would do (its
/// narration, the stage summary), or guidance the user sent meanwhile, then
/// the thinking and tools behind it.
class AgentChatWorkStage {
  AgentChatWorkStage({this.narration, this.steer});

  String? narration;
  final String? steer;
  final List<AgentChatTurnItem> items = [];

  Iterable<AgentChatTurnItem> get tools =>
      items.where((item) => item.kind == AgentChatTurnItemKind.tool);

  bool get failed => tools.any((item) => item.failed);
}

/// Splits a turn's work into stages: each narration or guidance opens one,
/// and what the agent says right after guidance belongs to it.
List<AgentChatWorkStage> agentChatWorkStages(
  Iterable<AgentChatTurnItem> items,
) {
  final stages = <AgentChatWorkStage>[];
  for (final item in items) {
    switch (item.kind) {
      case AgentChatTurnItemKind.narration:
        final last = stages.isEmpty ? null : stages.last;
        if (last != null && last.narration == null && last.tools.isEmpty) {
          last.narration = item.narration;
        } else {
          stages.add(AgentChatWorkStage(narration: item.narration));
        }
      case AgentChatTurnItemKind.steer:
        stages.add(AgentChatWorkStage(steer: item.steer));
      case AgentChatTurnItemKind.reasoning || AgentChatTurnItemKind.tool:
        if (stages.isEmpty) stages.add(AgentChatWorkStage());
        stages.last.items.add(item);
    }
  }
  return stages;
}

/// The tools of a stage on one line, repeated tools counted:
/// "搜索标签 ×3 · 编辑提示词分区".
String agentChatToolsSummary(
  BuildContext context,
  Iterable<AgentChatTurnItem> tools,
) {
  final counts = <String, int>{};
  for (final item in tools) {
    final label = agentToolLabel(context, item.toolName);
    counts[label] = (counts[label] ?? 0) + 1;
  }
  return [
    for (final MapEntry(key: label, value: count) in counts.entries)
      count > 1 ? '$label ×$count' : label,
  ].join(' · ');
}

String _formatDuration(Duration duration) {
  if (duration.inSeconds < 1) return '${duration.inMilliseconds}ms';
  if (duration.inMinutes < 1) return '${duration.inSeconds}s';
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '${duration.inMinutes}m ${seconds}s';
}

/// How the agent worked on a turn. While it runs, each stage summary reads
/// as text with its own tools under it, earlier stages fold their tools into
/// one line, and a footer says what happens now. Once done, the work becomes
/// one card: the outcome, then the numbered stage summaries, each opening
/// its tools.
class AgentChatWorkProcess extends StatefulWidget {
  const AgentChatWorkProcess({
    super.key,
    required this.turn,
    required this.running,
    required this.activities,
    this.liveNarration = '',
    this.liveThinking = '',
    this.awaitingApproval = false,
  });

  final AgentChatTurnModel turn;
  final bool running;
  final List<AgentToolActivity> activities;

  /// What the agent is saying before its next tools, still streaming.
  final String liveNarration;

  /// Its thinking, still streaming.
  final String liveThinking;
  final bool awaitingApproval;

  @override
  State<AgentChatWorkProcess> createState() => _AgentChatWorkProcessState();
}

class _AgentChatWorkProcessState extends State<AgentChatWorkProcess> {
  Timer? _elapsedTimer;
  final FocusNode _shortcutFocus = FocusNode(debugLabel: 'Agent work process');
  bool _collapsed = false;
  bool _restored = false;

  /// Stages whose tools the user opened (or, while running, folded).
  final Set<int> _toggledStages = {};

  String get _storageIdentifier =>
      'agent-work-process-${widget.turn.timeline?.id ?? widget.turn.ordinal}';

  @override
  void initState() {
    super.initState();
    _syncTimer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_restored) return;
    _restored = true;
    final stored = PageStorage.maybeOf(
      context,
    )?.readState(context, identifier: _storageIdentifier);
    if (stored is bool) _collapsed = stored;
  }

  @override
  void didUpdateWidget(covariant AgentChatWorkProcess oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.turn.ordinal != widget.turn.ordinal) {
      _toggledStages.clear();
      _collapsed = false;
      _restored = false;
    }
    // The stage that was live keeps its tools open only while it is live.
    if (oldWidget.running != widget.running) _toggledStages.clear();
    _syncTimer();
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    _shortcutFocus.dispose();
    super.dispose();
  }

  void _syncTimer() {
    _elapsedTimer?.cancel();
    if (widget.running && _validStartedAt != null) {
      _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  int? get _validStartedAt {
    final startedAt = widget.turn.timeline?.startedAt;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (startedAt == null || startedAt <= 0 || startedAt > now) return null;
    return startedAt;
  }

  Duration? get _duration {
    final startedAt = _validStartedAt;
    if (startedAt == null) return null;
    final endedAt = widget.running
        ? DateTime.now().millisecondsSinceEpoch
        : widget.turn.timeline?.completedAt;
    if (endedAt == null || endedAt < startedAt) return null;
    return Duration(milliseconds: endedAt - startedAt);
  }

  void _toggleCollapsed() {
    _shortcutFocus.requestFocus();
    setState(() {
      _collapsed = !_collapsed;
      PageStorage.maybeOf(
        context,
      )?.writeState(context, _collapsed, identifier: _storageIdentifier);
    });
  }

  void _toggleStage(int index) => setState(() {
    if (!_toggledStages.remove(index)) _toggledStages.add(index);
  });

  @override
  Widget build(BuildContext context) {
    final activeCallIds = {
      for (final activity in widget.activities) activity.toolCallId,
    };
    final stages = agentChatWorkStages(
      widget.turn.workItems.where(
        (item) =>
            !activeCallIds.contains(item.call?.id ?? item.result?.toolCallId),
      ),
    );
    final status = widget.turn.timeline?.status;
    final failed = status == AgentChatTurnStatus.failed;
    if (stages.isEmpty &&
        widget.activities.isEmpty &&
        widget.liveNarration.isEmpty &&
        widget.liveThinking.isEmpty &&
        !widget.running &&
        !failed) {
      return const SizedBox.shrink();
    }
    final child = widget.running
        ? _running(context, stages)
        : _finished(context, stages, status);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyT, control: true):
            _toggleCollapsed,
      },
      child: Focus(
        focusNode: _shortcutFocus,
        child: Padding(
          key: ValueKey('agent-work-process-${widget.turn.ordinal}'),
          padding: const EdgeInsets.only(bottom: 12),
          child: child,
        ),
      ),
    );
  }

  Widget _running(BuildContext context, List<AgentChatWorkStage> stages) {
    final shown = [...stages];
    if (widget.liveNarration.trim().isNotEmpty) {
      final last = shown.isEmpty ? null : shown.last;
      if (last != null && last.narration == null && last.tools.isEmpty) {
        last.narration = widget.liveNarration.trim();
      } else {
        shown.add(AgentChatWorkStage(narration: widget.liveNarration.trim()));
      }
    }
    if (shown.isEmpty &&
        (widget.activities.isNotEmpty || widget.liveThinking.isNotEmpty)) {
      shown.add(AgentChatWorkStage());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, stage) in shown.indexed)
          _StageRow(
            key: ValueKey('agent-work-stage-${widget.turn.ordinal}-$index'),
            number: index + 1,
            stage: stage,
            current: index == shown.length - 1,
            last: index == shown.length - 1,
            // The live stage shows its tools; earlier ones fold them.
            toolsOpen:
                (index == shown.length - 1) != _toggledStages.contains(index),
            onToggleTools: () => _toggleStage(index),
            activities: index == shown.length - 1
                ? widget.activities
                : const [],
            liveThinking: index == shown.length - 1 ? widget.liveThinking : '',
          ),
        _LiveFooter(
          key: ValueKey('agent-work-live-${widget.turn.ordinal}'),
          label: _liveLabel(context, stages),
          awaitingApproval: widget.awaitingApproval,
          duration: _duration,
        ),
      ],
    );
  }

  String _liveLabel(BuildContext context, List<AgentChatWorkStage> stages) {
    final l10n = context.l10n;
    if (widget.awaitingApproval) return l10n.agentChat_phaseAwaitingApproval;
    for (final activity in widget.activities) {
      if (activity.status == AgentToolActivityStatus.running) {
        return l10n.agentChat_doingTool(
          agentToolLabel(context, activity.toolName),
        );
      }
    }
    for (final stage in stages.reversed) {
      for (final item in stage.tools) {
        if (item.pending) {
          return l10n.agentChat_doingTool(
            agentToolLabel(context, item.toolName),
          );
        }
      }
    }
    return l10n.agentChat_thinking;
  }

  Widget _finished(
    BuildContext context,
    List<AgentChatWorkStage> stages,
    AgentChatTurnStatus? status,
  ) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final failed = status == AgentChatTurnStatus.failed;
    final stopped =
        status == AgentChatTurnStatus.aborted ||
        status == AgentChatTurnStatus.interrupted;
    final actions = stages.fold<int>(
      0,
      (count, stage) => count + stage.tools.length,
    );
    final duration = _duration;
    final title = [
      failed
          ? l10n.agentChat_workFailed
          : stopped
          ? l10n.agentChat_workStopped
          : l10n.agentChat_worked,
      if (duration != null) _formatDuration(duration),
      if (actions > 0) l10n.agentChat_workActions(actions),
    ].join(' · ');
    final (icon, iconColor) = failed
        ? (Icons.error_outline_rounded, theme.colorScheme.error)
        : stopped
        ? (Icons.stop_circle_outlined, theme.colorScheme.onSurfaceVariant)
        : (Icons.check_circle_outline_rounded, agentToolSuccessColor(theme));
    final error = widget.turn.timeline?.error;
    return Container(
      decoration: BoxDecoration(
        color: sectionSurfaceColor(theme.colorScheme),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.fromLTRB(12, 0, 8, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: !_collapsed,
            child: InkWell(
              key: ValueKey('agent-work-header-${widget.turn.ordinal}'),
              onTap: _toggleCollapsed,
              borderRadius: BorderRadius.circular(10),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: context.interactionPolicy.touchAvailable ? 44 : 36,
                ),
                child: Row(
                  children: [
                    Icon(icon, size: 17, color: iconColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: failed
                              ? theme.colorScheme.error
                              : theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Icon(
                      _collapsed
                          ? Icons.expand_more_rounded
                          : Icons.expand_less_rounded,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (failed && error != null && error.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(25, 0, 4, 6),
              child: Text(
                error.trim(),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          if (!_collapsed)
            for (final (index, stage) in stages.indexed)
              _SummaryLine(
                key: ValueKey(
                  'agent-work-summary-${widget.turn.ordinal}-$index',
                ),
                number: index + 1,
                stage: stage,
                open: _toggledStages.contains(index),
                onToggle: () => _toggleStage(index),
              ),
        ],
      ),
    );
  }
}

/// A stage while the agent works: its number on the rail, the guidance or
/// summary, and its tools (open for the live stage, one line otherwise).
class _StageRow extends StatelessWidget {
  const _StageRow({
    super.key,
    required this.number,
    required this.stage,
    required this.current,
    required this.last,
    required this.toolsOpen,
    required this.onToggleTools,
    required this.activities,
    required this.liveThinking,
  });

  final int number;
  final AgentChatWorkStage stage;
  final bool current;
  final bool last;
  final bool toolsOpen;
  final VoidCallback onToggleTools;
  final List<AgentToolActivity> activities;
  final String liveThinking;

  static const double _rail = 26;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final hasTools =
        stage.items.isNotEmpty ||
        activities.isNotEmpty ||
        liveThinking.isNotEmpty;
    return Stack(
      children: [
        if (!last)
          Positioned(
            left: 8.25,
            top: 23,
            bottom: 0,
            child: Container(width: 1.5, color: colors.outlineVariant),
          ),
        Positioned(
          left: 0,
          top: 2,
          child: Container(
            width: 18,
            height: 18,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: current
                  ? colors.primaryContainer
                  : sectionSurfaceColor(colors),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: theme.textTheme.labelSmall?.copyWith(
                color: current
                    ? colors.onPrimaryContainer
                    : colors.onSurfaceVariant,
                height: 1,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: _rail, bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (stage.steer case final steer?) _SteerNote(text: steer),
              if (stage.narration case final narration?)
                SelectableText(
                  narration,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
                ),
              if (hasTools)
                if (toolsOpen) ...[
                  const SizedBox(height: 2),
                  for (final item in stage.items)
                    if (item.kind == AgentChatTurnItemKind.reasoning)
                      AgentChatReasoningTile(thinking: item.thinking!)
                    else
                      _ToolRow(item: item),
                  for (final activity in activities)
                    AgentChatToolActivityTile(activity: activity),
                  if (liveThinking.isNotEmpty)
                    AgentChatReasoningTile(thinking: liveThinking, live: true),
                ] else if (stage.tools.isNotEmpty)
                  _FoldedTools(stage: stage, onTap: onToggleTools),
            ],
          ),
        ),
      ],
    );
  }
}

/// Guidance the user sent while the agent worked, where the agent took it in.
class _SteerNote extends StatelessWidget {
  const _SteerNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 7, 12, 8),
      decoration: BoxDecoration(
        color: controlSurfaceColor(theme.colorScheme),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(
                  Icons.alt_route_rounded,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            TextSpan(
              text: '${context.l10n.agentChat_steerNote}  ',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
            TextSpan(text: text),
          ],
        ),
        style: theme.textTheme.bodySmall?.copyWith(height: 1.45),
      ),
    );
  }
}

/// An earlier stage's tools on one line; tapping opens them.
class _FoldedTools extends StatelessWidget {
  const _FoldedTools({required this.stage, required this.onTap});

  final AgentChatWorkStage stage;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final failed = stage.failed;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: context.interactionPolicy.touchAvailable ? 40 : 30,
        ),
        child: Row(
          children: [
            Icon(
              failed
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_outline_rounded,
              size: 15,
              color: failed
                  ? theme.colorScheme.error
                  : agentToolSuccessColor(theme),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                agentChatToolsSummary(context, stage.tools),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Icon(
              Icons.expand_more_rounded,
              size: 17,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

/// One finished stage in the card: its number, its summary (the guidance,
/// or its tools when it said nothing), and its tools once opened.
class _SummaryLine extends StatelessWidget {
  const _SummaryLine({
    super.key,
    required this.number,
    required this.stage,
    required this.open,
    required this.onToggle,
  });

  final int number;
  final AgentChatWorkStage stage;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = context.l10n;
    final steer = stage.steer;
    final text =
        stage.narration ??
        (steer != null ? null : agentChatToolsSummary(context, stage.tools));
    final hasDetails = stage.items.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: hasDetails ? onToggle : null,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 18,
                  height: 18,
                  margin: const EdgeInsets.only(top: 1),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: controlSurfaceColor(colors),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$number',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                      height: 1,
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (steer != null)
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '${l10n.agentChat_steerNote}  ',
                                style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                              TextSpan(text: steer),
                            ],
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            height: 1.5,
                          ),
                        ),
                      if (text != null && text.isNotEmpty)
                        Text(
                          text,
                          style: theme.textTheme.bodySmall?.copyWith(
                            height: 1.5,
                            color: stage.narration == null
                                ? colors.onSurfaceVariant
                                : colors.onSurface,
                          ),
                        ),
                    ],
                  ),
                ),
                if (hasDetails)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, top: 1),
                    child: Icon(
                      open
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 17,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.only(left: 27, bottom: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final item in stage.items)
                  if (item.kind == AgentChatTurnItemKind.reasoning)
                    AgentChatReasoningTile(thinking: item.thinking!)
                  else
                    _ToolRow(item: item),
              ],
            ),
          ),
      ],
    );
  }
}

/// One tool call: its name with the short result and status; tapping opens
/// the arguments and the full result.
class _ToolRow extends StatefulWidget {
  const _ToolRow({required this.item});

  final AgentChatTurnItem item;

  @override
  State<_ToolRow> createState() => _ToolRowState();
}

class _ToolRowState extends State<_ToolRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;
    final id = item.call?.id ?? item.result?.toolCallId ?? item.messageIndex;
    final label = agentToolLabel(context, item.toolName);
    final summary = item.pending
        ? context.l10n.agentChat_toolRunning
        : item.result == null
        ? ''
        : agentToolResultSummary(context, item.result!, fallback: '');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: ValueKey('agent-turn-tool-item-$id'),
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: context.interactionPolicy.touchAvailable ? 40 : 30,
            ),
            child: Row(
              children: [
                Icon(
                  agentToolIcon(item.toolName),
                  size: 15,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: label),
                        if (summary.isNotEmpty)
                          TextSpan(
                            text: ' · $summary',
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                const SizedBox(width: 6),
                if (item.pending)
                  SizedBox.square(
                    dimension: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.6,
                      value: MediaQuery.disableAnimationsOf(context)
                          ? 0.75
                          : null,
                    ),
                  )
                else
                  Semantics(
                    label: item.failed
                        ? context.l10n.common_error
                        : context.l10n.common_success,
                    child: ExcludeSemantics(
                      child: Icon(
                        item.failed ? Icons.close_rounded : Icons.check_rounded,
                        key: ValueKey('agent-turn-tool-status-$id'),
                        size: 15,
                        color: item.failed
                            ? theme.colorScheme.error
                            : agentToolSuccessColor(theme),
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
        if (_expanded) AgentChatWorkItemDetails(item: item),
      ],
    );
  }
}

/// What happens now, at the foot of the running work, with the time spent.
class _LiveFooter extends StatelessWidget {
  const _LiveFooter({
    super.key,
    required this.label,
    required this.awaitingApproval,
    required this.duration,
  });

  final String label;
  final bool awaitingApproval;
  final Duration? duration;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Semantics(
      liveRegion: true,
      label: label,
      child: SizedBox(
        height: 24,
        child: Row(
          children: [
            SizedBox(
              width: 26,
              child: Align(
                alignment: Alignment.centerLeft,
                child: awaitingApproval
                    ? Icon(
                        Icons.pan_tool_outlined,
                        size: 15,
                        color: theme.colorScheme.primary,
                      )
                    : SizedBox.square(
                        dimension: 13,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.7,
                          value: MediaQuery.disableAnimationsOf(context)
                              ? 0.75
                              : null,
                        ),
                      ),
              ),
            ),
            Expanded(
              child: ExcludeSemantics(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
              ),
            ),
            if (duration case final value?)
              ExcludeSemantics(
                child: Text(_formatDuration(value), style: style),
              ),
          ],
        ),
      ),
    );
  }
}
