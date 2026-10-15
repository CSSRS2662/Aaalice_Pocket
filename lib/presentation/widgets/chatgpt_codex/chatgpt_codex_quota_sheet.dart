import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/localization_extension.dart';
import '../../../data/models/prompt_assistant/prompt_assistant_models.dart';
import '../../../data/services/chatgpt_codex/chatgpt_codex_usage.dart';
import '../../adaptive/adaptive_presenter.dart';
import '../../adaptive/content_sized_adaptive_form.dart';
import '../../prompt_assistant/providers/chatgpt_codex_account_provider.dart';
import '../../prompt_assistant/providers/chatgpt_codex_usage_provider.dart';
import '../../themes/core/layered_surface_style.dart';
import 'chatgpt_codex_quota_format.dart';

/// Opens the Codex quota of [provider]'s ChatGPT login: each window's
/// remaining share and its reset time in the device time zone.
Future<void> showChatGptCodexQuotaSheet(
  BuildContext context,
  ProviderConfig provider,
) {
  return AdaptivePresenter.showForm<void>(
    context: context,
    title: context.l10n.chatgptCodex_quotaTitle,
    dialogWidth: 440,
    builder: (sheetContext, scrollController) => ContentSizedAdaptiveForm(
      scrollController: scrollController,
      content: [ChatGptCodexQuotaDetails(provider: provider)],
    ),
  );
}

/// The usage of [provider]'s account, or null before anything was read.
ChatGptCodexUsage? watchChatGptCodexUsage(
  WidgetRef ref,
  ProviderConfig provider,
) {
  final accountId = ref.watch(
    chatGptCodexAccountProvider.select(
      (accounts) => accounts[provider.id]?.accountId,
    ),
  );
  if (accountId == null) return null;
  return ref.watch(
    chatGptCodexUsageProvider.select((usage) => usage[accountId]),
  );
}

class ChatGptCodexQuotaDetails extends ConsumerStatefulWidget {
  const ChatGptCodexQuotaDetails({super.key, required this.provider});

  final ProviderConfig provider;

  @override
  ConsumerState<ChatGptCodexQuotaDetails> createState() =>
      _ChatGptCodexQuotaDetailsState();
}

class _ChatGptCodexQuotaDetailsState
    extends ConsumerState<ChatGptCodexQuotaDetails> {
  late final ChatGptCodexUsageNotifier _usage;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _usage = ref.read(chatGptCodexUsageProvider.notifier);
    _refreshing = true;
    unawaited(_read(force: false));
  }

  Future<void> _refresh({required bool force}) async {
    setState(() => _refreshing = true);
    await _read(force: force);
  }

  Future<void> _read({required bool force}) async {
    try {
      await _usage.refresh(widget.provider, force: force);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final account = ref.watch(
      chatGptCodexAccountProvider.select(
        (accounts) => accounts[widget.provider.id],
      ),
    );
    final usage = watchChatGptCodexUsage(ref, widget.provider);
    final now = DateTime.now();
    final plan = usage?.planType ?? account?.planType;
    final identity = [
      if (account?.email case final email?) email,
      if (plan != null) l10n.chatgptCodex_plan(_planLabel(plan)),
    ].join(' · ');
    final exhausted =
        usage != null &&
        (usage.limitReached ||
            [usage.primary, usage.secondary].any(
              (window) => window != null && window.remainingPercent <= 0,
            ));

    return Column(
      key: const ValueKey('chatgpt-codex-quota-details'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (identity.isNotEmpty)
          Text(
            identity,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        const SizedBox(height: 12),
        if (usage == null || !usage.hasWindows)
          Text(
            _refreshing ? l10n.common_loading : l10n.chatgptCodex_quotaEmpty,
            key: const ValueKey('chatgpt-codex-quota-empty'),
            style: theme.textTheme.bodyMedium,
          )
        else ...[
          if (usage.primary case final window?)
            _WindowSection(
              key: const ValueKey('chatgpt-codex-quota-primary'),
              name: chatGptCodexWindowName(l10n, window.length, primary: true),
              window: window,
              now: now,
            ),
          if (usage.secondary case final window?) ...[
            const SizedBox(height: 16),
            _WindowSection(
              key: const ValueKey('chatgpt-codex-quota-secondary'),
              name: chatGptCodexWindowName(
                l10n,
                window.length,
                primary: false,
              ),
              window: window,
              now: now,
            ),
          ],
        ],
        if (usage != null && usage.additional.isNotEmpty) ...[
          const SizedBox(height: 16),
          for (final limit in usage.additional)
            _NamedLimitRow(limit: limit, now: now),
        ],
        if (exhausted) ...[
          const SizedBox(height: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.errorContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                l10n.chatgptCodex_limitReached,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onErrorContainer,
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          l10n.chatgptCodex_quotaNote,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                usage == null
                    ? ''
                    : l10n.chatgptCodex_updatedAt(usage.observedAt.toLocal()),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
            TextButton.icon(
              key: const ValueKey('chatgpt-codex-quota-refresh'),
              onPressed: _refreshing ? null : () => _refresh(force: true),
              icon: _refreshing
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded, size: 18),
              label: Text(l10n.common_refresh),
            ),
          ],
        ),
      ],
    );
  }
}

/// `plus` → `Plus`; the backend sends lower-case plan ids.
String _planLabel(String plan) =>
    plan.isEmpty ? plan : '${plan[0].toUpperCase()}${plan.substring(1)}';

class _WindowSection extends StatelessWidget {
  const _WindowSection({
    super.key,
    required this.name,
    required this.window,
    required this.now,
  });

  final String name;
  final ChatGptCodexUsageWindow window;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final remaining = window.remainingPercent;
    final low = remaining < 10;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(child: Text(name, style: theme.textTheme.titleSmall)),
            Text(
              l10n.chatgptCodex_remaining(chatGptCodexPercentText(window)),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: low ? colors.error : colors.onSurface,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _QuotaTrack(fraction: remaining / 100, warning: low),
        if (window.resetsAt case final resetsAt?) ...[
          const SizedBox(height: 6),
          Text(
            chatGptCodexResetText(l10n, resetsAt, now),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _NamedLimitRow extends StatelessWidget {
  const _NamedLimitRow({required this.limit, required this.now});

  final ChatGptCodexNamedLimit limit;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final parts = [
      for (final (window, primary) in [
        (limit.primary, true),
        (limit.secondary, false),
      ])
        if (window != null)
          '${chatGptCodexWindowName(l10n, window.length, primary: primary)} '
              '${chatGptCodexPercentText(window)}',
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: controlSurfaceColor(colors),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(limit.name, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 2),
          Text(
            parts.join(' · '),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuotaTrack extends StatelessWidget {
  const _QuotaTrack({required this.fraction, required this.warning});

  final double fraction;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 8,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: colors.surfaceContainerHighest),
            FractionallySizedBox(
              alignment: AlignmentDirectional.centerStart,
              widthFactor: fraction.clamp(0.0, 1.0),
              child: ColoredBox(
                color: warning ? colors.error : colors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
