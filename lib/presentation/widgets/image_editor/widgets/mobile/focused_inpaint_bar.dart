import 'package:flutter/material.dart';

import '../../../../../core/utils/localization_extension.dart';
import 'editor_segmented_switch.dart';

/// 聚焦重绘的两步
enum FocusedInpaintStep { selectArea, paintMask }

/// 移动端聚焦重绘条：顶栏下方的步骤、最小上下文与发送读数，取代桌面浮在画布上的卡片
class FocusedInpaintBar extends StatelessWidget {
  const FocusedInpaintBar({
    super.key,
    required this.step,
    required this.hasArea,
    required this.minimumContext,
    required this.onMinimumContextChanged,
    required this.summary,
    required this.onStepSelected,
    required this.onClearArea,
    required this.onExit,
  });

  final FocusedInpaintStep step;

  /// 已框定聚焦区域；之前不能进入画蒙版一步
  final bool hasArea;
  final double minimumContext;
  final ValueChanged<double> onMinimumContextChanged;

  /// 发送尺寸与点数，或下一步该做什么
  final String summary;
  final ValueChanged<FocusedInpaintStep> onStepSelected;
  final VoidCallback onClearArea;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final muted = theme.colorScheme.onSurfaceVariant;
    return Material(
      key: const ValueKey('editor-focused-inpaint-bar'),
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 4, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: EditorSegmentedSwitch<FocusedInpaintStep>(
                    expand: true,
                    segments: [
                      EditorSegment(
                        key: const ValueKey('editor-focus-step-select'),
                        value: FocusedInpaintStep.selectArea,
                        label: l10n.editor_focusSelection,
                        leading: _StepBadge(
                          number: 1,
                          active: step == FocusedInpaintStep.selectArea,
                        ),
                      ),
                      EditorSegment(
                        key: const ValueKey('editor-focus-step-paint'),
                        value: FocusedInpaintStep.paintMask,
                        label: l10n.editor_focusBrush,
                        enabled: hasArea,
                        leading: _StepBadge(
                          number: 2,
                          active: step == FocusedInpaintStep.paintMask,
                        ),
                      ),
                    ],
                    selected: step,
                    onSelected: onStepSelected,
                  ),
                ),
                IconButton(
                  tooltip: l10n.editor_clearSelection,
                  icon: const Icon(Icons.deselect),
                  onPressed: hasArea ? onClearArea : null,
                ),
                IconButton(
                  tooltip: l10n.editor_focusExit,
                  icon: const Icon(Icons.close),
                  onPressed: onExit,
                ),
              ],
            ),
            _MinimumContextRow(
              label: l10n.editor_focusMinimumContextArea(
                minimumContext.round(),
              ),
              widestLabel: l10n.editor_focusMinimumContextArea(192),
              style: theme.textTheme.labelMedium?.copyWith(color: muted),
              slider: Slider(
                value: minimumContext.clamp(16, 192),
                min: 16,
                max: 192,
                divisions: 176,
                label: '${minimumContext.round()}',
                onChanged: onMinimumContextChanged,
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 6,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(Icons.info_outline, size: 16, color: muted),
                ),
                Expanded(
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ),
                ),
                Tooltip(
                  message: l10n.editor_focusContextHint,
                  triggerMode: TooltipTriggerMode.tap,
                  showDuration: const Duration(seconds: 6),
                  child: SizedBox(
                    width: 44,
                    height: 36,
                    child: Icon(Icons.help_outline, size: 18, color: muted),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StepBadge extends StatelessWidget {
  const _StepBadge({required this.number, required this.active});

  final int number;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: 18,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: active ? colorScheme.primary : colorScheme.outlineVariant,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: MediaQuery.withNoTextScaling(
            child: Text(
              '$number',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: active ? colorScheme.onPrimary : colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The minimum context label and its slider. The label keeps the width of
/// its widest value so the track does not move while dragging, and goes
/// over the track when the bar is too narrow for both.
class _MinimumContextRow extends StatelessWidget {
  const _MinimumContextRow({
    required this.label,
    required this.widestLabel,
    required this.style,
    required this.slider,
  });

  final String label;
  final String widestLabel;
  final TextStyle? style;
  final Widget slider;

  static const double _minTrack = 120;

  @override
  Widget build(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(
        text: widestLabel,
        style: DefaultTextStyle.of(context).style.merge(style),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final labelWidth = painter.width.ceilToDouble();
    painter.dispose();
    final text = Text(label, maxLines: 1, style: style);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= labelWidth + _minTrack) {
          return Row(
            children: [
              SizedBox(width: labelWidth, child: text),
              Expanded(child: slider),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
            slider,
          ],
        );
      },
    );
  }
}
