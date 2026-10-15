import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../../data/models/prompt_assistant/prompt_assistant_models.dart';
import '../../../prompt_assistant/providers/chatgpt_codex_account_provider.dart';
import 'chatgpt_codex_login_sheet.dart';

/// The ChatGPT login of [provider], read on first show.
ChatGptCodexAccount? _watchAccount(WidgetRef ref, ProviderConfig provider) =>
    ref.watch(
      chatGptCodexAccountProvider.select((accounts) => accounts[provider.id]),
    );

/// Provider card line for a ChatGPT login: who is signed in, or that no one
/// is.
class ChatGptCodexAccountStatus extends ConsumerStatefulWidget {
  const ChatGptCodexAccountStatus({
    super.key,
    required this.provider,
    this.style,
  });

  final ProviderConfig provider;
  final TextStyle? style;

  @override
  ConsumerState<ChatGptCodexAccountStatus> createState() =>
      _ChatGptCodexAccountStatusState();
}

class _ChatGptCodexAccountStatusState
    extends ConsumerState<ChatGptCodexAccountStatus> {
  @override
  void initState() {
    super.initState();
    unawaited(
      ref.read(chatGptCodexAccountProvider.notifier).load(widget.provider.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final account = _watchAccount(ref, widget.provider);
    final colors = Theme.of(context).colorScheme;
    final text = switch (account) {
      null => l10n.chatgptCodex_notSignedIn,
      ChatGptCodexAccount(needsLogin: true) => l10n.chatgptCodex_needsLogin,
      ChatGptCodexAccount(:final email?) => l10n.chatgptCodex_signedIn(email),
      _ => l10n.chatgptCodex_signedInNoEmail,
    };
    return Text(
      text,
      key: ValueKey('chatgpt-codex-status-${widget.provider.id}'),
      style: widget.style?.copyWith(
        color: account == null || account.needsLogin ? colors.error : null,
      ),
    );
  }
}

/// Sign in, or sign out of, [provider]'s ChatGPT login.
class ChatGptCodexAccountAction extends ConsumerWidget {
  const ChatGptCodexAccountAction({super.key, required this.provider});

  final ProviderConfig provider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final account = _watchAccount(ref, provider);
    if (account == null || account.needsLogin) {
      return TextButton.icon(
        key: ValueKey('chatgpt-codex-sign-in-${provider.id}'),
        onPressed: () =>
            unawaited(showChatGptCodexLoginSheet(context, provider)),
        icon: const Icon(Icons.login_rounded, size: 16),
        label: Text(l10n.chatgptCodex_signIn),
      );
    }
    return TextButton.icon(
      key: ValueKey('chatgpt-codex-sign-out-${provider.id}'),
      onPressed: () => unawaited(
        ref.read(chatGptCodexAccountProvider.notifier).logout(provider.id),
      ),
      icon: const Icon(Icons.logout_rounded, size: 16),
      label: Text(l10n.chatgptCodex_signOut),
    );
  }
}
