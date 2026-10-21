import 'package:flutter/material.dart';

import '../../../core/utils/localization_extension.dart';
import '../../adaptive/interaction_policy.dart';

/// What the composer's main button does now.
enum AgentChatSendAction {
  /// Sends a new message.
  send,

  /// Adds the draft to the work in progress, before the agent's next step.
  steer,

  /// Stops the work in progress (nothing typed).
  stop,
}

/// The composer's main button: send, then stop while the agent works, or
/// guide the work once something is typed. While guiding, a long press or
/// right click offers sending after the work instead.
class AgentChatSendButton extends StatelessWidget {
  const AgentChatSendButton({
    super.key,
    required this.running,
    required this.hasDraft,
    required this.canSend,
    required this.disabledReason,
    required this.onSend,
    required this.onStop,
    required this.onSendAfterRun,
  });

  final bool running;
  final bool hasDraft;
  final bool canSend;
  final String disabledReason;

  /// Sends, or while running guides the work in progress.
  final VoidCallback onSend;
  final VoidCallback onStop;
  final VoidCallback onSendAfterRun;

  AgentChatSendAction get action => !running
      ? AgentChatSendAction.send
      : hasDraft
      ? AgentChatSendAction.steer
      : AgentChatSendAction.stop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = context.l10n;
    final touch = context.interactionPolicy.shouldExposeTouchAlternatives;
    final extent = context.interactionPolicy.minimumControlExtent;
    final action = this.action;
    final enabled = running || (canSend && hasDraft);
    final (background, foreground) = switch (action) {
      AgentChatSendAction.stop => (colors.onSurface, colors.surface),
      _ when enabled => (colors.primary, colors.onPrimary),
      _ => (
        colors.surfaceContainerHighest,
        colors.onSurfaceVariant.withValues(alpha: 0.6),
      ),
    };
    final label = switch (action) {
      AgentChatSendAction.send => l10n.agentChat_send,
      AgentChatSendAction.steer => l10n.agentChat_steer,
      AgentChatSendAction.stop => l10n.agentChat_stop,
    };
    final steering = action == AgentChatSendAction.steer;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      hint: enabled ? null : disabledReason,
      onLongPress: steering ? onSendAfterRun : null,
      excludeSemantics: true,
      child: Tooltip(
        message: enabled ? label : disabledReason,
        waitDuration: const Duration(milliseconds: 500),
        child: SizedBox(
          key: const ValueKey('agent-chat-send'),
          width: extent,
          height: extent,
          child: Center(
            child: Material(
              key: const ValueKey('agent-chat-send-surface'),
              color: background,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: !enabled
                    ? null
                    : action == AgentChatSendAction.stop
                    ? onStop
                    : onSend,
                onLongPress: steering ? () => _showMenu(context) : null,
                onSecondaryTap: steering ? () => _showMenu(context) : null,
                child: SizedBox.square(
                  dimension: touch ? 40 : 34,
                  child: Icon(
                    switch (action) {
                      AgentChatSendAction.stop => Icons.stop_rounded,
                      _ => Icons.arrow_upward_rounded,
                    },
                    key: ValueKey('agent-chat-send-${action.name}'),
                    size: touch ? 21 : 18,
                    color: foreground,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showMenu(BuildContext context) async {
    final l10n = context.l10n;
    final box = context.findRenderObject()! as RenderBox;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
    final choice = await showMenu<AgentChatSendAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(origin.dx, origin.dy, box.size.width, box.size.height),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          key: const ValueKey('agent-chat-send-menu-steer'),
          value: AgentChatSendAction.steer,
          height: 48,
          child: _MenuRow(
            icon: Icons.alt_route_rounded,
            label: l10n.agentChat_steer,
          ),
        ),
        PopupMenuItem(
          key: const ValueKey('agent-chat-send-menu-after'),
          value: AgentChatSendAction.send,
          height: 48,
          child: _MenuRow(
            icon: Icons.schedule_rounded,
            label: l10n.agentChat_sendAfterRun,
          ),
        ),
      ],
    );
    switch (choice) {
      case AgentChatSendAction.steer:
        onSend();
      case AgentChatSendAction.send:
        onSendAfterRun();
      case AgentChatSendAction.stop || null:
        break;
    }
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 19),
      const SizedBox(width: 12),
      Flexible(child: Text(label)),
    ],
  );
}
