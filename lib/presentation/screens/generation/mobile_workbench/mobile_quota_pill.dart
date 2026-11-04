import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../providers/cost_estimate_provider.dart';
import '../../../providers/subscription_provider.dart';
import '../../../themes/core/layered_surface_style.dart';
import '../../../themes/theme_extension.dart';
import '../../../widgets/anlas/anlas_icon.dart';
import '../../../widgets/anlas/opus_stamina_bar.dart';
import '../../../widgets/anlas/opus_stamina_sheet.dart';

/// 顶栏额度胶囊：余额居中，五段体力条填满可用宽度。
class MobileQuotaPill extends ConsumerWidget {
  const MobileQuotaPill({super.key, required this.textStyle});

  final TextStyle? textStyle;

  static const double minimumWidth = 88;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(subscriptionNotifierProvider);
    final cost = ref.watch(estimatedCostProvider);
    final usage = watchVisibleOpusUsage(ref);
    final level = usage == null ? null : OpusStaminaLevel.from(usage);
    final balance = state.balance;
    final balanceText = balance == null
        ? '--'
        : NumberFormat('#,###').format(balance);
    final warning = state.isError || (balance != null && balance < cost);
    final enabled = !state.isLoading && !state.isUnsupported;
    final staminaText = level == null
        ? null
        : level.exhausted
        ? context.l10n.stamina_stateExhausted
        : '${level.available.round()}%';
    final label = state.isUnsupported
        ? context.l10n.anlas_thirdPartyUnavailable
        : state.isError
        ? context.l10n.common_clickToRetry
        : staminaText == null
        ? 'Anlas $balanceText · ${context.l10n.common_refresh}'
        : 'Anlas $balanceText · ${context.l10n.stamina_barSemantics(staminaText)}';
    final radius = BorderRadius.circular(theme.appTheme.controlRadius + 2);

    void activate() {
      HapticFeedback.lightImpact();
      final notifier = ref.read(subscriptionNotifierProvider.notifier);
      if (state.isLoaded) {
        unawaited(
          notifier.refreshBalance(
            priority: SubscriptionRefreshPriority.userInitiated,
          ),
        );
      } else {
        unawaited(notifier.fetchSubscription());
      }
      if (usage != null) showOpusStaminaSheet(context);
    }

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      onTap: enabled ? activate : null,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: Material(
          key: const ValueKey('generation-mobile-quota'),
          color: controlSurfaceColor(theme.colorScheme),
          borderRadius: radius,
          child: InkWell(
            onTap: enabled ? activate : null,
            borderRadius: radius,
            child: SizedBox(
              height: 44,
              child: _QuotaReadout(
                balance: balanceText,
                textStyle: textStyle ?? theme.textTheme.titleSmall,
                warning: warning,
                loading: state.isLoading,
                level: level,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QuotaReadout extends StatelessWidget {
  const _QuotaReadout({
    required this.balance,
    required this.textStyle,
    required this.warning,
    required this.loading,
    required this.level,
  });

  final String balance;
  final TextStyle? textStyle;
  final bool warning;
  final bool loading;
  final OpusStaminaLevel? level;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: loading
                    ? SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          value: MediaQuery.disableAnimationsOf(context)
                              ? 0.75
                              : null,
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnlasIcon(
                            size: 14,
                            color: warning ? colors.error : colors.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            balance,
                            style: textStyle?.copyWith(
                              color: warning ? colors.error : colors.onSurface,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
          if (level != null) ...[
            const SizedBox(height: 4),
            _StaminaSegments(level: level!),
          ],
        ],
      ),
    );
  }
}

class _StaminaSegments extends StatelessWidget {
  const _StaminaSegments({required this.level});

  final OpusStaminaLevel level;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      key: const ValueKey('generation-mobile-stamina-track'),
      height: 4,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: Row(
          children: [
            for (var index = 0; index < 5; index++) ...[
              if (index > 0) const SizedBox(width: 1),
              Expanded(
                child: ColoredBox(
                  color: colors.onSurfaceVariant.withValues(alpha: 0.18),
                  child: FractionallySizedBox(
                    key: ValueKey('generation-mobile-stamina-fill-$index'),
                    alignment: AlignmentDirectional.centerStart,
                    heightFactor: 1,
                    widthFactor: (level.available / 20 - index).clamp(0.0, 1.0),
                    child: ColoredBox(color: colors.primary),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
