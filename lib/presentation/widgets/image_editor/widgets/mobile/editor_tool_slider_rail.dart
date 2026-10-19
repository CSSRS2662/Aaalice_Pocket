import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../../core/utils/localization_extension.dart';
import '../../../../themes/core/layered_surface_style.dart';
import '../../core/editor_state.dart';
import '../../tools/blur_tool.dart';
import '../../tools/brush_tool.dart';
import '../../tools/clone_stamp_tool.dart';
import '../../tools/eraser_tool.dart';

/// 画布侧边的一根竖向滑杆
@immutable
class EditorToolSliderSpec {
  const EditorToolSliderSpec({
    required this.id,
    required this.label,
    required this.icon,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.exponent = 1,
    this.suffix = '',
    this.previewsSize = false,
  });

  final String id;
  final String label;
  final IconData icon;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  /// 大于 1 时低端更细，小笔刷也能拖准
  final double exponent;
  final String suffix;

  /// 拖动时在画布中央显示笔刷大小
  final bool previewsSize;

  double fractionOf(double value) {
    final linear = ((value - min) / (max - min)).clamp(0.0, 1.0);
    return math.pow(linear, 1 / exponent).toDouble();
  }

  double valueAt(double fraction) =>
      min + (max - min) * math.pow(fraction.clamp(0.0, 1.0), exponent);

  String format(double value) => '${value.round()}$suffix';
}

/// 当前工具的大小与不透明度；其他工具没有滑杆
List<EditorToolSliderSpec> editorToolSliderSpecs(
  BuildContext context,
  EditorState state,
) {
  final l10n = context.l10n;

  EditorToolSliderSpec size(
    double value,
    double max,
    ValueChanged<double> update,
  ) => EditorToolSliderSpec(
    id: 'size',
    label: l10n.editor_size,
    icon: Icons.line_weight,
    value: value,
    min: 1,
    max: max,
    exponent: 2,
    previewsSize: true,
    onChanged: (value) {
      update(value);
      state.requestUiUpdate();
    },
  );

  EditorToolSliderSpec opacity(double value, ValueChanged<double> update) =>
      EditorToolSliderSpec(
        id: 'opacity',
        label: l10n.editor_opacity,
        icon: Icons.opacity,
        value: value * 100,
        min: 0,
        max: 100,
        suffix: '%',
        onChanged: (value) {
          update(value / 100);
          state.requestUiUpdate();
        },
      );

  return switch (state.currentTool) {
    final BrushTool brush when state.isMaskLayerActive => [
      size(brush.maskSize, 500, brush.setMaskSize),
    ],
    final BrushTool brush => [
      size(brush.settings.size, 500, brush.setSize),
      opacity(brush.settings.opacity, brush.setOpacity),
    ],
    final EraserTool eraser => [size(eraser.size, 500, eraser.setSize)],
    final BlurTool blur => [size(blur.size, 200, blur.setSize)],
    final CloneStampTool clone => [
      size(clone.size, 200, clone.setSize),
      opacity(clone.opacity, clone.setOpacity),
    ],
    _ => const [],
  };
}

/// 当前工具的竖向滑杆，跟着工具与图层切换；两根时大小占多一些
class EditorToolSliderRail extends StatelessWidget {
  const EditorToolSliderRail({
    super.key,
    required this.state,
    required this.maxHeight,
    this.onSizePreview,
  });

  final EditorState state;
  final double maxHeight;

  /// 拖动大小时给出画布上的笔刷直径（文档像素），松手时为空
  final ValueChanged<double?>? onSizePreview;

  static const double _gap = 8;

  /// 低于这个高度时不显示滑杆，大小仍在选项条与全部参数里
  static const double minimumHeight = 96;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        state,
        state.toolChangeNotifier,
        state.layerManager.activeLayerNotifier,
      ]),
      builder: (context, _) {
        final specs = editorToolSliderSpecs(context, state);
        if (specs.isEmpty || maxHeight < minimumHeight) {
          return const SizedBox.shrink();
        }
        final single = specs.length == 1 || maxHeight < minimumHeight * 2;
        final shown = single ? specs.take(1).toList() : specs;
        final first = single
            ? math.min(maxHeight, 200.0)
            : math.min((maxHeight - _gap) * 0.6, 180.0);
        final second = math.min(maxHeight - _gap - first, 120.0);
        return Column(
          key: const ValueKey('editor-tool-slider-rail'),
          mainAxisSize: MainAxisSize.min,
          spacing: _gap,
          children: [
            for (final (index, spec) in shown.indexed)
              EditorVerticalSlider(
                key: ValueKey('editor-tool-slider-${spec.id}'),
                spec: spec,
                height: index == 0 ? first : second,
                onDragValue: spec.previewsSize ? onSizePreview : null,
              ),
          ],
        );
      },
    );
  }
}

/// 竖向滑杆：顶部数值、中间轨道、底部图标；上下拖动或点按轨道调整
class EditorVerticalSlider extends StatelessWidget {
  const EditorVerticalSlider({
    super.key,
    required this.spec,
    required this.height,
    this.onDragValue,
  });

  final EditorToolSliderSpec spec;
  final double height;
  final ValueChanged<double?>? onDragValue;

  static const double width = 44;
  static const double _labelExtent = 26;
  static const double _thumbRadius = 10;

  double _fractionAt(double dy) {
    const top = _labelExtent + _thumbRadius;
    final length = height - 2 * (_labelExtent + _thumbRadius);
    if (length <= 0) return spec.fractionOf(spec.value);
    return 1 - ((dy - top) / length).clamp(0.0, 1.0);
  }

  void _update(Offset localPosition) {
    final value = spec.valueAt(_fractionAt(localPosition.dy));
    spec.onChanged(value);
    onDragValue?.call(value);
  }

  void _step(int direction) {
    final fraction = spec.fractionOf(spec.value) + direction * 0.05;
    spec.onChanged(spec.valueAt(fraction));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final fraction = spec.fractionOf(spec.value);
    final valueText = spec.format(spec.value);
    return Semantics(
      slider: true,
      label: spec.label,
      value: valueText,
      increasedValue: spec.format(spec.valueAt(fraction + 0.05)),
      decreasedValue: spec.format(spec.valueAt(fraction - 0.05)),
      onIncrease: () => _step(1),
      onDecrease: () => _step(-1),
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) => _update(details.localPosition),
          onTapUp: (_) => onDragValue?.call(null),
          onTapCancel: () => onDragValue?.call(null),
          onVerticalDragStart: (details) => _update(details.localPosition),
          onVerticalDragUpdate: (details) => _update(details.localPosition),
          onVerticalDragEnd: (_) => onDragValue?.call(null),
          onVerticalDragCancel: () => onDragValue?.call(null),
          child: Tooltip(
            message: spec.label,
            excludeFromSemantics: true,
            child: Material(
              color: overlaySurfaceColor(colorScheme),
              shape: const StadiumBorder(),
              child: SizedBox(
                width: width,
                height: height,
                child: Column(
                  children: [
                    SizedBox(
                      height: _labelExtent,
                      child: Center(
                        child: MediaQuery.withClampedTextScaling(
                          maxScaleFactor: 1.2,
                          child: Text(
                            valueText,
                            maxLines: 1,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: _SliderTrackPainter(
                          fraction: fraction,
                          thumbRadius: _thumbRadius,
                          track: colorScheme.outlineVariant,
                          active: colorScheme.primary,
                          thumb: colorScheme.surface,
                        ),
                      ),
                    ),
                    SizedBox(
                      height: _labelExtent,
                      child: Icon(
                        spec.icon,
                        size: 16,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SliderTrackPainter extends CustomPainter {
  _SliderTrackPainter({
    required this.fraction,
    required this.thumbRadius,
    required this.track,
    required this.active,
    required this.thumb,
  });

  final double fraction;
  final double thumbRadius;
  final Color track;
  final Color active;
  final Color thumb;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2;
    final top = thumbRadius;
    final bottom = size.height - thumbRadius;
    if (bottom <= top) return;
    final y = bottom - (bottom - top) * fraction;
    final line = Paint()
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(x, top), Offset(x, bottom), line..color = track);
    canvas.drawLine(Offset(x, y), Offset(x, bottom), line..color = active);
    canvas.drawCircle(Offset(x, y), thumbRadius, Paint()..color = thumb);
    canvas.drawCircle(
      Offset(x, y),
      thumbRadius - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = active,
    );
  }

  @override
  bool shouldRepaint(_SliderTrackPainter oldDelegate) =>
      oldDelegate.fraction != fraction ||
      oldDelegate.track != track ||
      oldDelegate.active != active ||
      oldDelegate.thumb != thumb;
}
