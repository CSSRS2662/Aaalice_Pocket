import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/agent_question_notification_service.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/utils/localization_extension.dart';
import '../../router/shell_panels_overlay.dart';
import '../../widgets/common/app_toast.dart';
import '../models/agent_user_question_request.dart';
import '../providers/agent_chat_notifier.dart';
import 'agent_chat_tool_widgets.dart';

/// Mounted at the shell so hidden conversations still request attention once.
///
/// Questions always notify. A tool waiting for approval notifies only while
/// the app is in the background, where its card cannot be seen.
class AgentQuestionNotifications extends ConsumerStatefulWidget {
  const AgentQuestionNotifications({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<AgentQuestionNotifications> createState() =>
      _AgentQuestionNotificationsState();
}

class _AgentQuestionNotificationsState
    extends ConsumerState<AgentQuestionNotifications>
    with WidgetsBindingObserver {
  late final AgentQuestionNotificationService _service;
  late final StreamSubscription<String> _opened;

  /// The approval whose notification is showing.
  String? _approvalShown;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _service = ref.read(agentQuestionNotificationServiceProvider);
    _opened = _service.opened.listen((requestId) {
      if (!mounted) return;
      final state = ref.read(agentChatNotifierProvider);
      if (state.questionRequest?.toolCallId == requestId ||
          state.approvalRequest?.toolCallId == requestId) {
        ref.read(shellPanelProvider.notifier).state = ShellPanel.agent;
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_approvalShown != null) unawaited(_cancelApproval());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(_notifyApproval(ref.read(agentChatNotifierProvider)));
    }
  }

  bool get _inBackground {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    return lifecycle != null && lifecycle != AppLifecycleState.resumed;
  }

  Future<void> _update(AgentUserQuestionRequest? request) async {
    if (!mounted) return;
    final l10n = context.l10n;
    try {
      if (request == null) {
        await _service.cancel();
      } else {
        _approvalShown = null;
        AppToast.info(context, l10n.userQuestion_notification);
        await _service.show(
          requestId: request.toolCallId,
          title: l10n.userQuestion_waiting,
          message: l10n.userQuestion_notification,
          expiresAt: request.expiresAt!,
        );
      }
    } catch (error, stackTrace) {
      AppLogger.e(
        'Failed to update agent question notification',
        error,
        stackTrace,
        'AgentQuestionNotifications',
      );
      if (mounted && request != null) {
        AppToast.warning(context, l10n.userQuestion_notificationUnavailable);
      }
    }
  }

  Future<void> _notifyApproval(AgentChatState state) async {
    final request = state.approvalRequest;
    if (!mounted ||
        request == null ||
        state.questionRequest != null ||
        _approvalShown == request.toolCallId) {
      return;
    }
    final l10n = context.l10n;
    final tool = agentToolLabel(context, request.toolName);
    _approvalShown = request.toolCallId;
    try {
      await _service.show(
        requestId: request.toolCallId,
        title: l10n.agentChat_approvalNotificationTitle,
        message: l10n.agentChat_approvalNotificationMessage(tool),
      );
    } catch (error, stackTrace) {
      AppLogger.e(
        'Failed to show agent approval notification',
        error,
        stackTrace,
        'AgentQuestionNotifications',
      );
    }
  }

  Future<void> _cancelApproval() async {
    _approvalShown = null;
    // A question shown meanwhile owns the notification now.
    if (ref.read(agentChatNotifierProvider).questionRequest != null) return;
    try {
      await _service.cancel();
    } catch (error, stackTrace) {
      AppLogger.e(
        'Failed to cancel agent approval notification',
        error,
        stackTrace,
        'AgentQuestionNotifications',
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_opened.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AgentUserQuestionRequest?>(
      agentChatNotifierProvider.select((state) => state.questionRequest),
      (previous, next) {
        if (previous?.toolCallId == next?.toolCallId) return;
        unawaited(_update(next));
      },
    );
    ref.listen<String?>(
      agentChatNotifierProvider.select(
        (state) => state.approvalRequest?.toolCallId,
      ),
      (previous, next) {
        if (previous == next) return;
        if (_approvalShown != null && _approvalShown != next) {
          unawaited(_cancelApproval());
        }
        if (next != null && _inBackground) {
          unawaited(_notifyApproval(ref.read(agentChatNotifierProvider)));
        }
      },
    );
    return widget.child;
  }
}
