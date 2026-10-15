import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../../data/models/prompt_assistant/prompt_assistant_models.dart';
import '../../../../data/services/chatgpt_codex/chatgpt_codex_oauth_client.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../adaptive/adaptive_presenter.dart';
import '../../../adaptive/content_sized_adaptive_form.dart';
import '../../../prompt_assistant/providers/chatgpt_codex_account_provider.dart';
import '../../../themes/core/layered_surface_style.dart';
import 'chatgpt_codex_login_controller.dart';

/// Signs [provider] in with a ChatGPT account; true once signed in.
Future<bool> showChatGptCodexLoginSheet(
  BuildContext context,
  ProviderConfig provider,
) async {
  final result = await AdaptivePresenter.showForm<bool>(
    context: context,
    title: context.l10n.chatgptCodex_loginTitle,
    dialogWidth: 480,
    builder: (sheetContext, scrollController) => ChatGptCodexLoginPanel(
      provider: provider,
      scrollController: scrollController,
    ),
  );
  return result ?? false;
}

class ChatGptCodexLoginPanel extends ConsumerStatefulWidget {
  const ChatGptCodexLoginPanel({
    super.key,
    required this.provider,
    required this.scrollController,
    this.controller,
  });

  final ProviderConfig provider;
  final ScrollController? scrollController;

  /// Injected by tests; otherwise built from the app's providers.
  final ChatGptCodexLoginController? controller;

  @override
  ConsumerState<ChatGptCodexLoginPanel> createState() =>
      _ChatGptCodexLoginPanelState();
}

class _ChatGptCodexLoginPanelState
    extends ConsumerState<ChatGptCodexLoginPanel> {
  late final ChatGptCodexLoginController _controller;
  final _paste = TextEditingController();
  bool _pasteInvalid = false;
  bool _copied = false;
  Timer? _copiedReset;

  @override
  void initState() {
    super.initState();
    final accounts = ref.read(chatGptCodexAccountProvider.notifier);
    final providerId = widget.provider.id;
    _controller =
        widget.controller ??
        ChatGptCodexLoginController(
          client: ref.read(chatGptCodexOAuthClientProvider),
          onSignedIn: (credentials) =>
              accounts.saveLogin(providerId, credentials),
        );
    _controller.addListener(_onPhase);
  }

  void _onPhase() {
    if (!mounted) return;
    if (_controller.phase is ChatGptCodexLoginDone) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _copiedReset?.cancel();
    _controller.removeListener(_onPhase);
    if (widget.controller == null) _controller.dispose();
    _paste.dispose();
    super.dispose();
  }

  Future<void> _copy(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    setState(() => _copied = true);
    _copiedReset?.cancel();
    _copiedReset = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  void _submitPaste() {
    final accepted = _controller.submitRedirect(_paste.text);
    setState(() => _pasteInvalid = !accepted);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final phase = _controller.phase;
    return ContentSizedAdaptiveForm(
      key: const ValueKey('chatgpt-codex-login'),
      scrollController: widget.scrollController,
      content: switch (phase) {
        ChatGptCodexLoginChoosing() => _choosing(context, l10n),
        ChatGptCodexLoginStarting() => [_Progress(l10n.common_loading)],
        ChatGptCodexLoginFinishing() ||
        ChatGptCodexLoginDone() => [_Progress(l10n.chatgptCodex_finishing)],
        ChatGptCodexLoginDeviceCode(:final userCode) => _deviceCode(
          context,
          l10n,
          userCode,
        ),
        ChatGptCodexLoginBrowser(:final listening) => _browser(
          context,
          l10n,
          listening,
        ),
        ChatGptCodexLoginFailed(:final kind, :final message) => _failed(
          context,
          l10n,
          kind,
          message,
        ),
      },
      footer: phase is ChatGptCodexLoginChoosing || phase is ChatGptCodexLoginFailed
          ? null
          : Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                key: const ValueKey('chatgpt-codex-login-cancel'),
                onPressed: _controller.cancel,
                child: Text(l10n.common_cancel),
              ),
            ),
    );
  }

  List<Widget> _choosing(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    return [
      Text(l10n.chatgptCodex_loginIntro, style: theme.textTheme.bodyMedium),
      const SizedBox(height: 16),
      _MethodTile(
        key: const ValueKey('chatgpt-codex-login-device'),
        icon: Icons.pin_outlined,
        title: l10n.chatgptCodex_methodDeviceCode,
        description: l10n.chatgptCodex_methodDeviceCodeDescription,
        badge: l10n.chatgptCodex_recommended,
        onTap: () =>
            unawaited(_controller.start(ChatGptCodexLoginMethod.deviceCode)),
      ),
      const SizedBox(height: 8),
      _MethodTile(
        key: const ValueKey('chatgpt-codex-login-browser'),
        icon: Icons.open_in_browser_rounded,
        title: l10n.chatgptCodex_methodBrowser,
        description: l10n.chatgptCodex_methodBrowserDescription,
        onTap: () =>
            unawaited(_controller.start(ChatGptCodexLoginMethod.browser)),
      ),
    ];
  }

  List<Widget> _deviceCode(
    BuildContext context,
    AppLocalizations l10n,
    String code,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return [
      Text(l10n.chatgptCodex_deviceCodeStep, style: theme.textTheme.bodyMedium),
      const SizedBox(height: 12),
      DecoratedBox(
        decoration: BoxDecoration(
          color: controlSurfaceColor(colors),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          child: Center(
            child: SelectableText(
              code,
              key: const ValueKey('chatgpt-codex-login-user-code'),
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 4,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            key: const ValueKey('chatgpt-codex-login-open-verification'),
            onPressed: () => unawaited(_controller.openVerificationPage()),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: Text(l10n.chatgptCodex_openVerificationPage),
          ),
          OutlinedButton.icon(
            key: const ValueKey('chatgpt-codex-login-copy-code'),
            onPressed: () => unawaited(_copy(code)),
            icon: Icon(
              _copied ? Icons.check_rounded : Icons.copy_rounded,
              size: 18,
            ),
            label: Text(_copied ? l10n.common_copied : l10n.common_copy),
          ),
        ],
      ),
      const SizedBox(height: 16),
      _Progress(l10n.chatgptCodex_waitingApproval),
      const SizedBox(height: 8),
      Text(
        l10n.chatgptCodex_deviceCodeNote,
        style: theme.textTheme.bodySmall?.copyWith(
          color: colors.onSurfaceVariant,
        ),
      ),
    ];
  }

  List<Widget> _browser(
    BuildContext context,
    AppLocalizations l10n,
    bool listening,
  ) {
    final theme = Theme.of(context);
    return [
      Text(
        listening ? l10n.chatgptCodex_browserStep : l10n.chatgptCodex_portBusy,
        style: theme.textTheme.bodyMedium,
      ),
      const SizedBox(height: 12),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: FilledButton.tonalIcon(
          key: const ValueKey('chatgpt-codex-login-reopen'),
          onPressed: () => unawaited(_controller.openLoginPage()),
          icon: const Icon(Icons.open_in_new_rounded, size: 18),
          label: Text(l10n.chatgptCodex_openLoginPage),
        ),
      ),
      if (listening) ...[
        const SizedBox(height: 16),
        _Progress(l10n.chatgptCodex_waitingBrowser),
      ],
      const SizedBox(height: 16),
      TextField(
        key: const ValueKey('chatgpt-codex-login-paste'),
        controller: _paste,
        keyboardType: TextInputType.url,
        decoration: InputDecoration(
          labelText: l10n.chatgptCodex_pasteRedirectLabel,
          helperText: l10n.chatgptCodex_pasteRedirectHint,
          helperMaxLines: 3,
          errorText: _pasteInvalid ? l10n.chatgptCodex_pasteRedirectInvalid : null,
          errorMaxLines: 3,
        ),
        onSubmitted: (_) => _submitPaste(),
      ),
      const SizedBox(height: 8),
      Align(
        alignment: AlignmentDirectional.centerEnd,
        child: FilledButton(
          key: const ValueKey('chatgpt-codex-login-submit-paste'),
          onPressed: _submitPaste,
          child: Text(l10n.chatgptCodex_submitRedirect),
        ),
      ),
    ];
  }

  List<Widget> _failed(
    BuildContext context,
    AppLocalizations l10n,
    ChatGptCodexAuthFailure kind,
    String message,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = switch (kind) {
      ChatGptCodexAuthFailure.deviceCodeUnavailable =>
        l10n.chatgptCodex_deviceCodeUnavailable,
      ChatGptCodexAuthFailure.timedOut => l10n.chatgptCodex_loginTimedOut,
      _ => l10n.chatgptCodex_loginFailed(message),
    };
    return [
      DecoratedBox(
        decoration: BoxDecoration(
          color: colors.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            text,
            key: const ValueKey('chatgpt-codex-login-error'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onErrorContainer,
            ),
          ),
        ),
      ),
      const SizedBox(height: 12),
      Align(
        alignment: AlignmentDirectional.centerEnd,
        child: FilledButton.tonal(
          key: const ValueKey('chatgpt-codex-login-retry'),
          onPressed: _controller.cancel,
          child: Text(l10n.common_retry),
        ),
      ),
    ];
  }
}

class _MethodTile extends StatelessWidget {
  const _MethodTile({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String title;
  final String description;
  final String? badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: controlSurfaceColor(colors),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(icon, color: colors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(title, style: theme.textTheme.titleSmall),
                          if (badge case final badge?)
                            Text(
                              badge,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colors.primary,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: colors.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        const SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
      ],
    );
  }
}
