import 'package:flutter/material.dart';

import '../../../core/utils/localization_extension.dart';
import '../../../data/models/prompt_assistant/prompt_assistant_models.dart';
import '../../adaptive/interaction_policy.dart';
import 'agent_chat_header.dart';

/// One composer chip for what the agent may do: the permission mode and web
/// access, each as an icon. It opens a sheet on touch and a menu otherwise;
/// the chat is the only place these are set.
class AgentChatAccessControl extends StatelessWidget {
  const AgentChatAccessControl({
    super.key,
    required this.mode,
    required this.webAccessEnabled,
    required this.webAccessAvailable,
    required this.enabled,
    required this.onModeSelected,
    required this.onWebAccessChanged,
  });

  final AgentPermissionMode mode;
  final bool webAccessEnabled;

  /// Whether web access can be switched now (its settings have loaded).
  final bool webAccessAvailable;
  final bool enabled;
  final ValueChanged<AgentPermissionMode> onModeSelected;
  final ValueChanged<bool> onWebAccessChanged;

  static IconData modeIcon(AgentPermissionMode mode) => switch (mode) {
    AgentPermissionMode.safe => Icons.shield_outlined,
    AgentPermissionMode.askBeforeSensitiveActions => Icons.gpp_maybe_outlined,
    AgentPermissionMode.fullAccess => Icons.verified_user_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final policy = context.interactionPolicy;
    final color = theme.colorScheme.onSurfaceVariant.withValues(
      alpha: enabled ? 1 : 0.4,
    );
    final label =
        '${l10n.agentChat_permissionMode}: ${agentPermissionModeLabel(l10n, mode)} · '
        '${l10n.agentChat_webAccessLabel}: '
        '${webAccessEnabled ? l10n.agentChat_changeYes : l10n.agentChat_changeNo}';
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: InkWell(
          key: const ValueKey('agent-chat-access-control'),
          onTap: enabled ? () => _open(context) : null,
          borderRadius: BorderRadius.circular(policy.minimumControlExtent / 2),
          child: SizedBox(
            height: policy.minimumControlExtent,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    modeIcon(mode),
                    key: ValueKey('agent-chat-access-mode-${mode.name}'),
                    size: 18,
                    color: color,
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    webAccessEnabled
                        ? Icons.public_rounded
                        : Icons.public_off_outlined,
                    key: ValueKey(
                      webAccessEnabled
                          ? 'agent-chat-access-web-on'
                          : 'agent-chat-access-web-off',
                    ),
                    size: 18,
                    color: color,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    if (context.interactionPolicy.usesAnchoredMenus) {
      await _showMenu(context);
    } else {
      await _showSheet(context);
    }
  }

  Future<void> _showSheet(BuildContext context) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => _AccessSheet(
        mode: mode,
        webAccessEnabled: webAccessEnabled,
        webAccessAvailable: webAccessAvailable,
        onModeSelected: (value) {
          Navigator.pop(sheetContext);
          onModeSelected(value);
        },
        onWebAccessChanged: onWebAccessChanged,
      ),
    );
  }

  Future<void> _showMenu(BuildContext context) async {
    final l10n = context.l10n;
    final box = context.findRenderObject()! as RenderBox;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
    final selected = await showMenu<Object>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(origin.dx, origin.dy, box.size.width, box.size.height),
        Offset.zero & overlay.size,
      ),
      items: [
        for (final value in AgentPermissionMode.values)
          PopupMenuItem<Object>(
            value: value,
            height: 52,
            child: _ModeRow(mode: value, selected: value == mode),
          ),
        const PopupMenuDivider(),
        CheckedPopupMenuItem<Object>(
          value: _toggleWeb,
          checked: webAccessEnabled,
          enabled: webAccessAvailable,
          child: Text(l10n.agentChat_webAccessLabel),
        ),
      ],
    );
    if (selected case final AgentPermissionMode value) {
      onModeSelected(value);
    } else if (identical(selected, _toggleWeb)) {
      onWebAccessChanged(!webAccessEnabled);
    }
  }

  static const Object _toggleWeb = Object();
}

class _AccessSheet extends StatefulWidget {
  const _AccessSheet({
    required this.mode,
    required this.webAccessEnabled,
    required this.webAccessAvailable,
    required this.onModeSelected,
    required this.onWebAccessChanged,
  });

  final AgentPermissionMode mode;
  final bool webAccessEnabled;
  final bool webAccessAvailable;
  final ValueChanged<AgentPermissionMode> onModeSelected;
  final ValueChanged<bool> onWebAccessChanged;

  @override
  State<_AccessSheet> createState() => _AccessSheetState();
}

class _AccessSheetState extends State<_AccessSheet> {
  late bool _web = widget.webAccessEnabled;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return SingleChildScrollView(
      key: const ValueKey('agent-chat-access-sheet'),
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
            child: Text(
              l10n.agentChat_permissionMode,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          for (final value in AgentPermissionMode.values)
            InkWell(
              key: ValueKey('agent-chat-access-option-${value.name}'),
              onTap: () => widget.onModeSelected(value),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 10,
                ),
                child: _ModeRow(mode: value, selected: value == widget.mode),
              ),
            ),
          Divider(
            height: 16,
            indent: 8,
            endIndent: 8,
            color: theme.colorScheme.outlineVariant,
          ),
          SwitchListTile(
            key: const ValueKey('agent-chat-access-web'),
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            secondary: const Icon(Icons.public_rounded),
            title: Text(l10n.agentChat_webAccessLabel),
            value: _web,
            onChanged: widget.webAccessAvailable
                ? (value) {
                    setState(() => _web = value);
                    widget.onWebAccessChanged(value);
                  }
                : null,
          ),
        ],
      ),
    );
  }
}

class _ModeRow extends StatelessWidget {
  const _ModeRow({required this.mode, required this.selected});

  final AgentPermissionMode mode;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(
          AgentChatAccessControl.modeIcon(mode),
          size: 20,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                agentPermissionModeLabel(l10n, mode),
                style: theme.textTheme.bodyMedium,
              ),
              Text(
                agentPermissionModeDescription(l10n, mode),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 22,
          child: selected
              ? Icon(Icons.check_rounded, color: theme.colorScheme.primary)
              : null,
        ),
      ],
    );
  }
}
