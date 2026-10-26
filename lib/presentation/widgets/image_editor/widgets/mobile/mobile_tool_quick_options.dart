import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../../core/utils/localization_extension.dart';
import '../../../../adaptive/adaptive_presenter.dart';
import '../../../../themes/core/layered_surface_style.dart';
import '../../../common/horizontal_action_strip.dart';
import '../../core/editor_state.dart';
import '../../frame/frame_tool_panel.dart';
import '../../tools/blur_tool.dart';
import '../../tools/brush_tool.dart';
import '../../tools/clone_stamp_tool.dart';
import '../../tools/closed_region_fill_tool.dart';
import '../../tools/color_picker_tool.dart';
import '../../tools/eraser_tool.dart';
import '../../tools/fill_tool.dart';
import '../../tools/frame_tool.dart';
import '../../tools/magic_wand_tool.dart';
import '../../tools/move_tool.dart';
import '../../tools/selection/base_selection_tool.dart';
import '../panels/color_panel.dart';
import 'editor_segmented_switch.dart';

/// 选项条中段：当前工具最常用的一两项设置，完整设置在「全部参数」里。
/// 选项条随编辑状态重建，这里只读当前值、改完通知刷新。
class MobileToolQuickOptions extends StatelessWidget {
  const MobileToolQuickOptions({
    super.key,
    required this.state,
    this.onShiftEdges,
    this.onShowSettings,
  });

  final EditorState state;

  /// 打开当前工具的完整设置，容差这类不常调的值从这里进
  final VoidCallback? onShowSettings;

  /// 取景框的「扩展边缘」对话框由工作区提供
  final VoidCallback? onShiftEdges;

  static const List<double> maskSizePresets = [10, 20, 40, 80, 160];

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final mask = state.isMaskLayerActive;
    void changed() => state.requestUiUpdate();
    return switch (state.currentTool) {
      final BrushTool brush when mask => _SizePresetChips(
        value: brush.maskSize,
        onSelected: (size) {
          brush.setMaskSize(size);
          changed();
        },
      ),
      final BrushTool brush => _BrushPresets(state: state, brush: brush),
      final EraserTool eraser when mask => _SizePresetChips(
        value: eraser.size,
        onSelected: (size) {
          eraser.setSize(size);
          changed();
        },
      ),
      final EraserTool eraser => _InlineSlider(
        label: l10n.editor_hardness,
        value: eraser.hardness * 100,
        max: 100,
        suffix: '%',
        onChanged: (value) {
          eraser.setHardness(value / 100);
          changed();
        },
      ),
      final MagicWandTool wand => _MagicWandOptions(
        state: state,
        wand: wand,
        onShowSettings: onShowSettings,
      ),
      final FillTool fill => Row(
        children: [
          Expanded(
            child: _InlineSlider(
              label: l10n.editor_tolerance,
              value: fill.tolerance.toDouble(),
              max: 255,
              onChanged: (value) {
                fill.setTolerance(value.round());
                changed();
              },
            ),
          ),
          if (!mask) EditorColorSwatchButton(state: state),
        ],
      ),
      ClosedRegionFillTool() => _Hint(l10n.editor_clickInsideClosedRegion),
      final BlurTool blur => _InlineSlider(
        label: l10n.editor_intensity,
        value: blur.intensity * 100,
        max: 100,
        suffix: '%',
        onChanged: (value) {
          blur.setIntensity(value / 100);
          changed();
        },
      ),
      final CloneStampTool clone => _CloneSourceOptions(tool: clone),
      final ColorPickerTool picker => _ColorPickerOptions(
        state: state,
        picker: picker,
      ),
      BaseSelectionTool() => _SelectionOptions(state: state),
      MoveTool() => _MoveHint(state: state),
      FrameTool() => _FrameOptions(state: state, onShiftEdges: onShiftEdges),
      _ => const SizedBox.shrink(),
    };
  }
}

/// 选项条里的胶囊按钮；选中时用强调色面
class EditorQuickChip extends StatelessWidget {
  const EditorQuickChip({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.selected = false,
    this.minWidth = 0,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final enabled = onTap != null;
    final foreground = !enabled
        ? colorScheme.onSurface.withValues(alpha: 0.38)
        : selected
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurface;
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      child: Material(
        color: selected
            ? colorScheme.primaryContainer
            : controlSurfaceColor(colorScheme),
        borderRadius: BorderRadius.circular(12),
        animationDuration: Duration.zero,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: 44, minWidth: minWidth),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final text = Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: foreground,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  );
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    spacing: 6,
                    children: [
                      if (icon != null) Icon(icon, size: 18, color: foreground),
                      if (constraints.hasBoundedWidth)
                        Flexible(child: text)
                      else
                        text,
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 前景色；点开颜色面板
class EditorColorSwatchButton extends StatelessWidget {
  const EditorColorSwatchButton({super.key, required this.state});

  final EditorState state;

  Future<void> _open(BuildContext context) => AdaptivePresenter.showPanel<void>(
    context: context,
    title: context.l10n.editor_colorPanelTitle,
    initialChildSize: 0.5,
    builder: (context, scrollController) => SingleChildScrollView(
      controller: scrollController,
      child: ColorPanel(state: state),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return IconButton(
      key: const ValueKey('editor-quick-color'),
      tooltip: context.l10n.editor_colorPanelTitle,
      onPressed: () => _open(context),
      icon: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: state.foregroundColor,
          shape: BoxShape.circle,
          border: Border.all(color: colorScheme.outline, width: 1),
        ),
      ),
    );
  }
}

class _SizePresetChips extends StatelessWidget {
  const _SizePresetChips({required this.value, required this.onSelected});

  final double value;
  final ValueChanged<double> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The chips scroll sideways; the short label keeps its full width.
    return Row(
      children: [
        Text(
          context.l10n.editor_size,
          maxLines: 1,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 5,
          child: HorizontalActionStrip(
            child: Row(
              spacing: 6,
              children: [
                for (final size in MobileToolQuickOptions.maskSizePresets)
                  EditorQuickChip(
                    key: ValueKey('editor-size-chip-${size.round()}'),
                    label: '${size.round()}',
                    minWidth: 48,
                    selected: value.round() == size.round(),
                    onTap: () => onSelected(size),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _BrushPresets extends StatelessWidget {
  const _BrushPresets({required this.state, required this.brush});

  final EditorState state;
  final BrushTool brush;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        EditorColorSwatchButton(state: state),
        Expanded(
          child: HorizontalActionStrip(
            child: Row(
              spacing: 6,
              children: [
                for (final (index, preset) in defaultBrushPresets.indexed)
                  EditorQuickChip(
                    key: ValueKey('editor-quick-brush-preset-$index'),
                    label: brushPresetLabel(context, index),
                    selected: brush.selectedPresetIndex == index,
                    onTap: () {
                      brush.applyPreset(preset, index);
                      state.requestUiUpdate();
                    },
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _InlineSlider extends StatelessWidget {
  const _InlineSlider({
    required this.label,
    required this.value,
    required this.max,
    required this.onChanged,
    this.suffix = '',
  });

  final String label;
  final double value;
  final double max;
  final String suffix;
  final ValueChanged<double>? onChanged;

  /// The narrowest track still worth dragging.
  static const double _minTrack = 96;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final valueStyle = style?.copyWith(
      color: theme.colorScheme.onSurface,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    // The readout keeps the width of its largest value, so the track does
    // not shift under the finger as the number gains a digit.
    final valueWidth = _quickTextWidth(
      context,
      '${max.round()}$suffix',
      valueStyle,
    );
    final labelWidth = _quickTextWidth(context, label, style);
    final labelText = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
    final valueText = SizedBox(
      width: valueWidth,
      child: Text(
        '${value.round()}$suffix',
        maxLines: 1,
        textAlign: TextAlign.end,
        style: valueStyle,
      ),
    );
    final slider = Expanded(
      child: Slider(
        value: value.clamp(0, max),
        max: max,
        label: label,
        onChanged: onChanged,
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= labelWidth + valueWidth + _minTrack) {
          return Row(children: [labelText, slider, valueText]);
        }
        // Too narrow for a row of three: the name sits over the value
        // beside the track, rather than being cut to a few letters.
        final caption = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            labelText,
            Text('${value.round()}$suffix', maxLines: 1, style: valueStyle),
          ],
        );
        final captionWidth = math.max(labelWidth, valueWidth);
        return Row(
          children: [
            if (constraints.maxWidth >= captionWidth + _minTrack / 2)
              caption
            else
              Flexible(child: caption),
            slider,
          ],
        );
      },
    );
  }
}

/// The single-line width of [text] in [style] at the current text scale.
double _quickTextWidth(BuildContext context, String text, TextStyle? style) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: DefaultTextStyle.of(context).style.merge(style),
    ),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final width = painter.width.ceilToDouble();
  painter.dispose();
  return width;
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Row(
      spacing: 8,
      children: [
        Icon(Icons.info_outline, size: 18, color: color),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

class _MagicWandOptions extends StatelessWidget {
  const _MagicWandOptions({
    required this.state,
    required this.wand,
    this.onShowSettings,
  });

  final EditorState state;
  final MagicWandTool wand;
  final VoidCallback? onShowSettings;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final enabled = !wand.isApplying;
    void changed() => state.requestUiUpdate();
    return HorizontalActionStrip(
      child: Row(
        spacing: 6,
        children: [
          EditorSegmentedSwitch<MagicWandSelectionMode>(
            segments: [
              EditorSegment(
                value: MagicWandSelectionMode.smartObject,
                label: l10n.editor_magicWandSmartObject,
              ),
              EditorSegment(
                value: MagicWandSelectionMode.colorArea,
                label: l10n.editor_magicWandColorArea,
              ),
            ],
            selected: wand.mode,
            onSelected: enabled
                ? (mode) {
                    wand.setMode(mode);
                    changed();
                  }
                : null,
          ),
          if (wand.mode == MagicWandSelectionMode.colorArea)
            EditorQuickChip(
              key: const ValueKey('editor-quick-wand-tolerance'),
              label: '${l10n.editor_tolerance} ${wand.tolerance}',
              onTap: enabled ? onShowSettings : null,
            ),
          EditorQuickChip(
            key: const ValueKey('editor-quick-wand-invert'),
            icon: Icons.flip,
            label: l10n.editor_magicWandInvert,
            selected: wand.invert,
            onTap: enabled
                ? () {
                    wand.setInvert(!wand.invert);
                    changed();
                  }
                : null,
          ),
        ],
      ),
    );
  }
}

class _CloneSourceOptions extends StatelessWidget {
  const _CloneSourceOptions({required this.tool});

  final CloneStampTool tool;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: tool.sourceListenable,
      builder: (context, _) {
        final theme = Theme.of(context);
        final picking = tool.isPickingSource;
        final chip = EditorQuickChip(
          key: const ValueKey('editor-quick-clone-source'),
          icon: Icons.my_location,
          label: context.l10n.editor_cloneStampSetSource,
          selected: picking,
          onTap: () => tool.setPickingSource(!picking),
        );
        // The chip keeps its whole label; the status takes what is left and
        // only gives way when the strip is too narrow for both.
        final chipWidth =
            _quickTextWidth(
              context,
              context.l10n.editor_cloneStampSetSource,
              theme.textTheme.labelLarge,
            ) +
            24 +
            18 +
            6;
        return LayoutBuilder(
          builder: (context, constraints) {
            // Too narrow for the chip and a readable status: the chip wins,
            // and its selected state still shows that a point is awaited.
            if (constraints.maxWidth < chipWidth + 72) {
              return Row(children: [Flexible(child: chip)]);
            }
            return Row(
              spacing: 8,
              children: [
                chip,
                Expanded(
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      cloneStampSourceStatus(context, tool),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _ColorPickerOptions extends StatelessWidget {
  const _ColorPickerOptions({required this.state, required this.picker});

  final EditorState state;
  final ColorPickerTool picker;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      children: [
        Expanded(
          child: HorizontalActionStrip(
            child: Row(
              spacing: 6,
              children: [
                EditorSegmentedSwitch<ColorPickerSampleMode>(
                  segments: [
                    EditorSegment(
                      value: ColorPickerSampleMode.point,
                      label: l10n.editor_samplePoint,
                    ),
                    EditorSegment(
                      value: ColorPickerSampleMode.area,
                      label: l10n.editor_sampleArea,
                    ),
                  ],
                  selected: picker.sampleMode,
                  onSelected: (mode) {
                    picker.setSampleMode(mode);
                    state.requestUiUpdate();
                  },
                ),
                EditorSegmentedSwitch<ColorPickerSource>(
                  segments: [
                    EditorSegment(
                      value: ColorPickerSource.currentLayer,
                      label: l10n.editor_sourceCurrentLayer,
                    ),
                    EditorSegment(
                      value: ColorPickerSource.allLayers,
                      label: l10n.editor_sourceAllLayers,
                    ),
                  ],
                  selected: picker.source,
                  onSelected: (source) {
                    picker.setSource(source);
                    state.requestUiUpdate();
                  },
                ),
              ],
            ),
          ),
        ),
        EditorColorSwatchButton(state: state),
      ],
    );
  }
}

class _SelectionOptions extends StatelessWidget {
  const _SelectionOptions({required this.state});

  final EditorState state;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Path?>(
      valueListenable: state.selectionManager.selectionNotifier,
      builder: (context, selection, _) {
        final l10n = context.l10n;
        final has = selection != null;
        return HorizontalActionStrip(
          child: Row(
            spacing: 6,
            children: [
              EditorQuickChip(
                key: const ValueKey('editor-quick-clear-selection'),
                icon: Icons.deselect,
                label: l10n.selection_clear_selection,
                onTap: has ? () => state.clearSelection() : null,
              ),
              EditorQuickChip(
                key: const ValueKey('editor-quick-invert-selection'),
                icon: Icons.flip,
                label: l10n.selection_invert_selection,
                onTap: has ? state.invertSelection : null,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MoveHint extends StatelessWidget {
  const _MoveHint({required this.state});

  final EditorState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final layer = state.layerManager.activeLayer;
    final hint = switch ((layer, state.selectionPath)) {
      (null, _) => l10n.editor_moveNoLayer,
      (_, final _?) => l10n.editor_moveSelectionHint,
      (final active?, null) when !state.layerMover.canMoveWholeLayer(active) =>
        l10n.editor_moveBaseLayerHint,
      _ => l10n.editor_moveLayerHint,
    };
    return _Hint(hint);
  }
}

/// 取景框：尺寸与发送读数，扩展边缘、重置与裁切
class _FrameOptions extends StatelessWidget {
  const _FrameOptions({required this.state, this.onShiftEdges});

  final EditorState state;
  final VoidCallback? onShiftEdges;

  @override
  Widget build(BuildContext context) {
    final commands = state.frameCommands;
    if (commands == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: Listenable.merge([commands, state.framePreviewNotifier]),
      builder: (context, _) {
        final theme = Theme.of(context);
        final l10n = context.l10n;
        final frame = state.displayFrame;
        final estimate = commands.requestEstimate;
        final numbers = theme.textTheme.bodySmall?.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
        );
        final cost = estimate == null
            ? null
            : estimate.cost == 0
            ? l10n.editor_frameRequestFree
            : l10n.editor_frameRequestCost(estimate.cost);
        return Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.editor_frameSizeReadout(
                      frame.width.round(),
                      frame.height.round(),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: numbers?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (estimate != null)
                    Text(
                      '${l10n.editor_frameRequestReadout(estimate.requestWidth, estimate.requestHeight)} · $cost',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: numbers?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (onShiftEdges != null)
              _FrameAction(
                key: const ValueKey('editor-frame-extend'),
                icon: Icons.open_in_full,
                label: l10n.editor_frameShortExtend,
                tooltip: l10n.editor_shiftEdges,
                onTap: onShiftEdges,
              ),
            _FrameAction(
              key: const ValueKey('editor-frame-reset'),
              icon: Icons.fit_screen,
              label: l10n.editor_frameShortReset,
              tooltip: l10n.editor_resetFrame,
              onTap: commands.canResetFrame ? commands.resetFrame : null,
            ),
            _FrameAction(
              key: const ValueKey('editor-frame-crop'),
              icon: Icons.crop,
              label: l10n.editor_frameShortCrop,
              tooltip: l10n.editor_cropToFrame,
              busy: commands.isCroppingToFrame,
              onTap: commands.canCropToFrame
                  ? () => cropToFrameWithFeedback(context, commands)
                  : null,
            ),
          ],
        );
      },
    );
  }
}

/// 图标加短名的小按钮；完整名称在提示里
class _FrameAction extends StatelessWidget {
  const _FrameAction({
    super.key,
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onTap,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = onTap == null
        ? theme.colorScheme.onSurface.withValues(alpha: 0.38)
        : theme.colorScheme.onSurface;
    return Tooltip(
      message: tooltip,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        enabled: onTap != null,
        label: tooltip,
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 52,
            height: 52,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 2,
              children: [
                if (busy)
                  const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(icon, size: 20, color: color),
                MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.2,
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(color: color),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
