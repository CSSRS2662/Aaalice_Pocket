import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/opus_usage_estimator.dart';
import '../../../core/utils/localization_extension.dart';
import '../../../data/models/image/image_params.dart';
import '../../providers/cost_estimate_provider.dart';
import '../../providers/generation/image_workflow_controller.dart';
import '../../providers/image_generation_provider.dart';
import '../../providers/subscription_provider.dart';

/// Opus 免费生成配额徽章（V5 起）
///
/// 百分比保留超过 100% 的真实配额；悬浮显示估算张数与回充说明，
/// 配额透支时转为警示色。
///
/// 仅当满足全部条件时显示：Opus 订阅、订阅响应携带 usage 字段、
/// 当前模型受配额池限制（V5）。
class OpusUsageChip extends ConsumerWidget {
  /// 紧凑模式（移动端使用）
  final bool compact;

  const OpusUsageChip({super.key, this.compact = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usage = ref.watch(
      subscriptionNotifierProvider.select(
        (state) => state.subscription?.isOpus == true
            ? state.subscription?.usage
            : null,
      ),
    );
    final params = ref.watch(generationParamsNotifierProvider);
    if (usage == null || !params.capabilities.hasOpusUsageLimit) {
      return const SizedBox.shrink();
    }
    final workflow = ref.watch(imageWorkflowControllerProvider);
    final focusedMask = ref.watch(focusedInpaintMaskRequestSizeProvider);
    final imageAnlas = opusUsageImageAnlas(
      params,
      workflow,
      focusedMaskGeometry: focusedMask,
    );

    final theme = Theme.of(context);
    final l10n = context.l10n;
    final exhausted = usage.isNegative;
    // 服务端允许回充后的额度超过 100%，文本与张数保留真实值。
    final percent = exhausted ? 0.0 : usage.percent.clamp(0.0, double.infinity);
    final accentColor = exhausted
        ? theme.colorScheme.error
        : theme.colorScheme.primary;
    // The limit is charged by each free image's Anlas price; extra usage
    // bought counts as well.
    final available = percent + usage.purchasedPercent.clamp(0, 400);
    final estimatedImages = imageAnlas == null
        ? 0
        : OpusUsageEstimator.imagesForPercent(
            available,
            imageAnlas: imageAnlas,
          );

    // Settings above 1 MP or 28 steps cost Anlas and leave the limit alone.
    final estimateLine = imageAnlas == null
        ? l10n.stamina_notConsumed
        : l10n.generation_opusUsageEstimate(estimatedImages.toString());
    final tooltip = exhausted
        ? l10n.generation_opusUsageExhausted
        : '${l10n.generation_opusUsageRemaining(percent.round().toString())}\n'
              '$estimateLine\n'
              '${l10n.generation_opusUsageRefill}';

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 300),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 6 : 8,
          vertical: compact ? 3 : 4,
        ),
        decoration: BoxDecoration(
          color: accentColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(compact ? 10 : 12),
          border: Border.all(color: accentColor.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              exhausted ? Icons.hourglass_bottom_rounded : Icons.bolt_rounded,
              size: compact ? 12 : 14,
              color: accentColor,
            ),
            const SizedBox(width: 4),
            Text(
              '${percent.round()}%',
              style: TextStyle(
                color: accentColor,
                fontWeight: FontWeight.w600,
                fontSize: compact ? 11 : 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
