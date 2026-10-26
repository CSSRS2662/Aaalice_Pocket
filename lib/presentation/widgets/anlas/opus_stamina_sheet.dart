import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/services/opus_usage_estimator.dart';
import '../../../core/utils/localization_extension.dart';
import '../../adaptive/adaptive_presenter.dart';
import '../../adaptive/content_sized_adaptive_form.dart';
import '../../providers/cost_estimate_provider.dart';
import '../../providers/generation/image_workflow_controller.dart';
import '../../providers/image_generation_provider.dart';
import '../../providers/subscription_provider.dart';
import '../../themes/core/layered_surface_style.dart';
import 'opus_stamina_bar.dart';

/// 打开 V5 体力详情：剩余量、估算张数、回充时间、规则与本次消耗。
Future<void> showOpusStaminaSheet(BuildContext context) {
  return AdaptivePresenter.showForm<void>(
    context: context,
    title: context.l10n.stamina_title,
    dialogWidth: 440,
    builder: (sheetContext, scrollController) => ContentSizedAdaptiveForm(
      scrollController: scrollController,
      content: const [OpusStaminaDetails()],
    ),
  );
}

class OpusStaminaDetails extends ConsumerWidget {
  const OpusStaminaDetails({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usage = watchVisibleOpusUsage(ref);
    if (usage == null) return const SizedBox.shrink();
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final level = OpusStaminaLevel.from(usage);

    final params = ref.watch(generationParamsNotifierProvider);
    final workflow = ref.watch(imageWorkflowControllerProvider);
    final focusedMask = ref.watch(focusedInpaintMaskRequestSizeProvider);
    // The limit is charged by the Anlas price of each free image, so the count
    // follows the effort, size, steps and strength in use.
    final imageAnlas = opusUsageImageAnlas(
      params,
      workflow,
      focusedMaskGeometry: focusedMask,
    );
    final cost = ref.watch(estimatedCostProvider);
    final balance = ref.watch(anlasBalanceProvider);
    final consumesStamina = imageAnlas != null && !level.exhausted;
    final formatter = NumberFormat('#,###');

    final stateLabel = level.exhausted
        ? l10n.stamina_stateExhausted
        : level.overflow
        ? l10n.stamina_stateBonus
        : level.low
        ? l10n.stamina_stateLow
        : l10n.stamina_stateAvailable;
    final images = imageAnlas == null
        ? 0
        : OpusUsageEstimator.imagesForPercent(
            level.available,
            imageAnlas: imageAnlas,
          );
    final imagesText = imageAnlas == null && !level.exhausted
        ? l10n.stamina_notConsumed
        : l10n.stamina_imagesValue(formatter.format(images));
    final perImageText = imageAnlas == null
        ? '--'
        : l10n.stamina_perImageValue(
            _percentText(OpusUsageEstimator.percentPerImage(imageAnlas)),
          );
    final ratePerDay = OpusUsageEstimator.refillPercentPerDay(
      usage.timeUntilNextPercent,
    );
    final rateText = level.percent > 100
        ? l10n.stamina_overCap
        : level.percent == 100
        ? l10n.stamina_full
        : ratePerDay <= 0
        ? '--'
        : l10n.stamina_refillRateValue(
            _ratePerDayText(ratePerDay),
            formatter.format(
              OpusUsageEstimator.imagesForPercent(
                ratePerDay,
                imageAnlas: imageAnlas ?? OpusUsageEstimator.defaultImageAnlas,
              ),
            ),
          );
    final toFull = OpusUsageEstimator.timeToFull(
      percent: level.percent,
      secondsPerPercent: usage.timeUntilNextPercent,
    );
    final fullText = toFull == null
        ? '--'
        : toFull == Duration.zero
        ? l10n.stamina_full
        : toFull.inDays > 0
        ? l10n.stamina_aboutDaysHours(toFull.inDays, toFull.inHours % 24)
        : l10n.stamina_aboutHours(toFull.inHours < 1 ? 1 : toFull.inHours);
    final costText = formatter.format(cost);
    final thisGeneration = consumesStamina
        ? (cost > 0
              ? l10n.stamina_costStaminaAndAnlas(costText)
              : l10n.stamina_costStamina)
        : (cost > 0 ? l10n.stamina_costAnlas(costText) : l10n.stamina_costFree);

    return Column(
      key: const ValueKey('opus-stamina-details'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.stamina_subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: 10,
          children: [
            Text(
              level.exhausted ? '0%' : '${level.percent.round()}%',
              key: const ValueKey('opus-stamina-percent'),
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: level.exhausted ? colors.error : colors.onSurface,
                height: 1.1,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                stateLabel,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: level.exhausted
                      ? colors.error
                      : colors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        OpusStaminaTrack(level: level, height: 8),
        const SizedBox(height: 16),
        _DetailRows(
          rows: [
            (l10n.stamina_estimateImages, imagesText),
            (l10n.stamina_perImage, perImageText),
            if (level.purchased > 0)
              (l10n.stamina_extraUsage, '+${level.purchased.round()}%'),
            (l10n.stamina_refillRate, rateText),
            (l10n.stamina_timeToFull, fullText),
          ],
        ),
        if (level.exhausted) ...[
          const SizedBox(height: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.errorContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                l10n.stamina_exhaustedNote,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onErrorContainer,
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          l10n.stamina_rateNote,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        Text(l10n.stamina_rulesTitle, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        _RuleRow(color: colors.primary, text: l10n.stamina_ruleConsumes),
        _RuleRow(color: colors.tertiary, text: l10n.stamina_ruleAnlas),
        _RuleRow(color: colors.outline, text: l10n.stamina_ruleOtherModels),
        const SizedBox(height: 16),
        _DetailRows(
          rows: [
            (
              l10n.stamina_anlasBalance,
              balance == null ? '--' : formatter.format(balance),
            ),
            (l10n.stamina_thisGeneration, thisGeneration),
          ],
        ),
      ],
    );
  }
}

class _DetailRows extends StatelessWidget {
  const _DetailRows({required this.rows});

  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: controlSurfaceColor(colors),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                indent: 14,
                endIndent: 14,
                color: colors.onSurface.withValues(alpha: 0.06),
              ),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        rows[i].$1,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      // Values form a column; a value on two lines keeps
                      // both lines in it.
                      child: Text(
                        rows[i].$2,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({required this.color, required this.text});

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 7, right: 10),
            child: DecoratedBox(
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: const SizedBox.square(dimension: 7),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A small share of the allowance with enough digits to tell settings apart:
/// 0.058, 0.12, 1.5.
String _percentText(double percent) {
  if (percent >= 1) return percent.toStringAsFixed(1);
  if (percent >= 0.1) return percent.toStringAsFixed(2);
  return percent.toStringAsFixed(3);
}

/// The refill rate to one decimal, as the website shows it: 14.3, 11.
String _ratePerDayText(double percentPerDay) {
  final tenths = (percentPerDay * 10).round();
  return tenths % 10 == 0
      ? '${tenths ~/ 10}'
      : (tenths / 10).toStringAsFixed(1);
}
