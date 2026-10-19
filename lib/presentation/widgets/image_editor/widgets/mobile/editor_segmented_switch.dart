import 'package:flutter/material.dart';

import '../../../../themes/core/layered_surface_style.dart';

/// 分段开关里的一段；[leading] 为图标或序号徽标
@immutable
class EditorSegment<T> {
  const EditorSegment({
    required this.value,
    required this.label,
    this.icon,
    this.leading,
    this.key,
    this.enabled = true,
  });

  final T value;
  final String label;
  final IconData? icon;
  final Widget? leading;
  final Key? key;
  final bool enabled;
}

/// 移动端编辑器的互斥模式：一块控件色面，选中段铺页面色面并加粗。
/// [labelSelectedOnly] 时未选中段只显示图标，名称留给提示与读屏。
class EditorSegmentedSwitch<T> extends StatelessWidget {
  const EditorSegmentedSwitch({
    super.key,
    required this.segments,
    required this.selected,
    required this.onSelected,
    this.expand = false,
    this.labelSelectedOnly = false,
  });

  final List<EditorSegment<T>> segments;
  final T? selected;
  final ValueChanged<T>? onSelected;

  /// 各段等分可用宽度
  final bool expand;
  final bool labelSelectedOnly;

  static const double height = 44;
  static const double _inset = 3;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final children = [
      for (final segment in segments)
        _Segment<T>(
          key: segment.key,
          segment: segment,
          selected: segment.value == selected,
          showLabel: !labelSelectedOnly || segment.value == selected,
          onTap: onSelected == null || !segment.enabled
              ? null
              : () => onSelected!(segment.value),
        ),
    ];
    // 宽度有限时各段可以收窄、名称渐隐；在横向滚动条里保持完整宽度
    return LayoutBuilder(
      builder: (context, constraints) {
        final bounded = constraints.hasBoundedWidth;
        return Container(
          height: height,
          padding: const EdgeInsets.all(_inset),
          decoration: BoxDecoration(
            color: controlSurfaceColor(colorScheme),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            spacing: 2,
            children: [
              for (final child in children)
                if (expand)
                  Expanded(child: child)
                else if (bounded)
                  Flexible(child: child)
                else
                  child,
            ],
          ),
        );
      },
    );
  }
}

class _Segment<T> extends StatelessWidget {
  static const double _leadingExtent = 18;

  const _Segment({
    super.key,
    required this.segment,
    required this.selected,
    required this.showLabel,
    required this.onTap,
  });

  final EditorSegment<T> segment;
  final bool selected;
  final bool showLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final enabled = onTap != null;
    final foreground = !enabled
        ? colorScheme.onSurface.withValues(alpha: 0.38)
        : selected
        ? colorScheme.onSurface
        : colorScheme.onSurfaceVariant;
    final leading =
        segment.leading ??
        (segment.icon == null
            ? null
            : Icon(segment.icon, size: 18, color: foreground));
    final text = Text(
      segment.label,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.fade,
      style: theme.textTheme.labelLarge?.copyWith(
        color: foreground,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
      ),
    );
    // 太窄时只留图标，名称交给提示与读屏
    final content = LayoutBuilder(
      builder: (context, constraints) {
        final wantsLabel = showLabel || leading == null;
        final fitsLabel =
            leading == null || constraints.maxWidth >= _leadingExtent + 16;
        return Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 4,
          children: [
            ?leading,
            if (wantsLabel && fitsLabel) Flexible(child: text),
          ],
        );
      },
    );
    final button = Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: segment.label,
      excludeSemantics: true,
      child: Material(
        color: selected ? colorScheme.surface : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        animationDuration: Duration.zero,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(9),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: 40,
              minHeight: EditorSegmentedSwitch.height - 6,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Center(widthFactor: 1, child: content),
            ),
          ),
        ),
      ),
    );
    if (showLabel && segment.leading == null && segment.icon == null) {
      return button;
    }
    return Tooltip(
      message: segment.label,
      excludeFromSemantics: true,
      child: button,
    );
  }
}
