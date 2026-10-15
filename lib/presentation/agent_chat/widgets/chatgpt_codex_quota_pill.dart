import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/localization_extension.dart';
import '../../../data/models/prompt_assistant/prompt_assistant_models.dart';
import '../../../data/services/chatgpt_codex/chatgpt_codex_usage.dart';
import '../../prompt_assistant/providers/chatgpt_codex_account_provider.dart';
import '../../prompt_assistant/providers/chatgpt_codex_usage_provider.dart';
import '../../themes/theme_extension.dart';
import '../../widgets/chatgpt_codex/chatgpt_codex_quota_format.dart';
import '../../widgets/chatgpt_codex/chatgpt_codex_quota_sheet.dart';

/// How much of the quota the header can afford to show.
enum ChatGptCodexQuotaDensity {
  /// Every window: `5h 93% | 7d 99%`.
  full,

  /// The window with the least left: `7d 40%`.
  compact,

  /// An icon tinted by what is left; numbers stay in the tooltip and details.
  minimal;

  /// Picks the densest reading that leaves the session name a readable
  /// width of the [width] the title row offers. The pill caps its text at
  /// 1.3x, so its width grows with [textScale] only up to there.
  static ChatGptCodexQuotaDensity forTitleWidth(
    double width,
    double textScale,
  ) {
    const readableTitle = 96.0;
    final scale = textScale.clamp(1.0, 1.3);
    if (width >= readableTitle + 112 * scale) return full;
    if (width >= readableTitle + 64 * scale) return compact;
    return minimal;
  }
}

/// Header slot: the quota pill while the agent runs on a signed-in ChatGPT
/// login, nothing otherwise.
class ChatGptCodexQuotaSlot extends ConsumerStatefulWidget {
  const ChatGptCodexQuotaSlot({
    super.key,
    required this.provider,
    this.density = ChatGptCodexQuotaDensity.full,
  });

  /// The agent's provider; it signs in with ChatGPT.
  final ProviderConfig provider;
  final ChatGptCodexQuotaDensity density;

  @override
  ConsumerState<ChatGptCodexQuotaSlot> createState() =>
      _ChatGptCodexQuotaSlotState();
}

class _ChatGptCodexQuotaSlotState extends ConsumerState<ChatGptCodexQuotaSlot> {
  final _requested = <String>{};

  @override
  Widget build(BuildContext context) {
    final provider = widget.provider;
    final account = ref.watch(
      chatGptCodexAccountProvider.select((accounts) => accounts[provider.id]),
    );
    if (account == null) {
      if (_requested.add(provider.id)) {
        // The stored login is read lazily; the pill appears once it is.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          unawaited(
            ref.read(chatGptCodexAccountProvider.notifier).load(provider.id),
          );
        });
      }
      return const SizedBox.shrink();
    }
    if (account.needsLogin) return const SizedBox.shrink();
    return ChatGptCodexQuotaPill(provider: provider, density: widget.density);
  }
}

/// Header reading of the ChatGPT subscription quota: the remaining share of
/// each window, on the header colour like the stamina pill. Tapping opens the
/// reset times.
class ChatGptCodexQuotaPill extends ConsumerStatefulWidget {
  const ChatGptCodexQuotaPill({
    super.key,
    required this.provider,
    this.density = ChatGptCodexQuotaDensity.full,
  });

  final ProviderConfig provider;
  final ChatGptCodexQuotaDensity density;

  @override
  ConsumerState<ChatGptCodexQuotaPill> createState() =>
      _ChatGptCodexQuotaPillState();
}

class _ChatGptCodexQuotaPillState extends ConsumerState<ChatGptCodexQuotaPill> {
  late final ChatGptCodexUsageNotifier _usage;

  @override
  void initState() {
    super.initState();
    _usage = ref.read(chatGptCodexUsageProvider.notifier);
    unawaited(_usage.refresh(widget.provider));
  }

  @override
  void didUpdateWidget(covariant ChatGptCodexQuotaPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.provider.id != widget.provider.id) {
      unawaited(_usage.refresh(widget.provider));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final usage = watchChatGptCodexUsage(ref, widget.provider);
    final windows = <(ChatGptCodexUsageWindow, bool)>[
      if (usage?.primary case final window?) (window, true),
      if (usage?.secondary case final window?) (window, false),
    ];
    final description = windows.isEmpty
        ? l10n.chatgptCodex_quotaTitle
        : windows
              .map(
                (entry) =>
                    '${chatGptCodexWindowName(l10n, entry.$1.length, primary: entry.$2)} '
                    '${l10n.chatgptCodex_remaining(chatGptCodexPercentText(entry.$1))}',
              )
              .join(', ');
    final tightest = windows.isEmpty
        ? null
        : windows
              .reduce(
                (a, b) => b.$1.remainingPercent < a.$1.remainingPercent ? b : a,
              )
              .$1;
    final shown = switch (widget.density) {
      ChatGptCodexQuotaDensity.full => [for (final entry in windows) entry.$1],
      _ when tightest == null => const <ChatGptCodexUsageWindow>[],
      ChatGptCodexQuotaDensity.compact => [tightest],
      ChatGptCodexQuotaDensity.minimal => const <ChatGptCodexUsageWindow>[],
    };
    return Tooltip(
      message: description,
      child: Semantics(
        button: true,
        label: description,
        excludeSemantics: true,
        child: InkWell(
          key: const ValueKey('agent-chat-codex-quota'),
          onTap: () => showChatGptCodexQuotaSheet(context, widget.provider),
          borderRadius: BorderRadius.circular(theme.appTheme.controlRadius),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.3,
                child: shown.isEmpty
                    ? _QuotaIcon(tightest: tightest)
                    : _QuotaReadings(windows: shown),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// No numbers: the icon turns red when a window is nearly used up.
class _QuotaIcon extends StatelessWidget {
  const _QuotaIcon({required this.tightest});

  final ChatGptCodexUsageWindow? tightest;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final low = (tightest?.remainingPercent ?? 100) < 10;
    return Icon(
      Icons.data_usage_rounded,
      size: 18,
      color: tightest == null
          ? colors.onSurfaceVariant
          : low
          ? colors.error
          : colors.primary,
    );
  }
}

class _QuotaReadings extends StatelessWidget {
  const _QuotaReadings({required this.windows});

  final List<ChatGptCodexUsageWindow> windows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    final valueStyle = theme.textTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < windows.length; i++) ...[
          if (i > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: SizedBox(
                width: 1,
                height: 16,
                child: ColoredBox(
                  color: colors.outlineVariant.withValues(alpha: 0.7),
                ),
              ),
            ),
          Text(chatGptCodexWindowShortLabel(windows[i].length), style: labelStyle),
          const SizedBox(width: 3),
          Text(
            chatGptCodexPercentText(windows[i]),
            maxLines: 1,
            softWrap: false,
            style: valueStyle?.copyWith(
              color: windows[i].remainingPercent < 10
                  ? colors.error
                  : colors.onSurface,
            ),
          ),
        ],
      ],
    );
  }
}
