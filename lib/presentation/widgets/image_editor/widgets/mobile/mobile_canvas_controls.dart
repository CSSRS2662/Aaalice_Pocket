import 'package:flutter/material.dart';

import '../../../../../core/utils/localization_extension.dart';
import '../../../../themes/core/layered_surface_style.dart';
import '../../core/editor_state.dart';
import '../toolbar/editor_view_menu.dart';

/// 浮在画布上的胶囊：浮层色面，开启的状态用强调色面
class EditorCanvasChip extends StatelessWidget {
  const EditorCanvasChip({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.selected = false,
    this.tooltip,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool selected;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final chip = Semantics(
      button: onTap != null,
      toggled: onTap != null && selected ? true : null,
      child: Material(
        color: _chipColor(context, selected),
        shape: const StadiumBorder(),
        animationDuration: Duration.zero,
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: _ChipContent(label: label, icon: icon, selected: selected),
        ),
      ),
    );
    final tooltip = this.tooltip;
    if (tooltip == null) return chip;
    return Tooltip(message: tooltip, excludeFromSemantics: true, child: chip);
  }
}

Color _chipColor(BuildContext context, bool selected) {
  final colorScheme = Theme.of(context).colorScheme;
  return selected
      ? colorScheme.primaryContainer
      : overlaySurfaceColor(colorScheme);
}

class _ChipContent extends StatelessWidget {
  const _ChipContent({required this.label, this.icon, this.selected = false});

  final String label;
  final IconData? icon;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = selected
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurface;
    final text = MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.6,
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelLarge?.copyWith(
          color: foreground,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        // 放不下时名称省略，不撑破画布边缘
        child: LayoutBuilder(
          builder: (context, constraints) => Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 6,
            children: [
              if (icon != null) Icon(icon, size: 18, color: foreground),
              if (constraints.hasBoundedWidth) Flexible(child: text) else text,
            ],
          ),
        ),
      ),
    );
  }
}

/// 当前缩放比例；点开视图菜单（缩放、适应、旋转、翻转、重置）
class EditorZoomChip extends StatelessWidget {
  const EditorZoomChip({super.key, required this.state});

  final EditorState state;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<VoidCallback>(
      key: const ValueKey('editor-zoom-chip'),
      tooltip: context.l10n.editor_viewOptions,
      onSelected: (action) => action(),
      itemBuilder: (menuContext) => editorViewMenuEntries(menuContext, state),
      child: Material(
        color: _chipColor(context, false),
        shape: const StadiumBorder(),
        child: ListenableBuilder(
          listenable: state.canvasController,
          builder: (context, _) => _ChipContent(
            label: '${(state.canvasController.scale * 100).round()}%',
          ),
        ),
      ),
    );
  }
}

/// 撤销与重做，横放在画布右下角
class EditorUndoRedoPill extends StatelessWidget {
  const EditorUndoRedoPill({super.key, required this.state});

  final EditorState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Material(
      key: const ValueKey('editor-undo-redo'),
      color: overlaySurfaceColor(Theme.of(context).colorScheme),
      shape: const StadiumBorder(),
      child: ListenableBuilder(
        listenable: Listenable.merge([state.historyManager, state]),
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: l10n.editor_undo,
              icon: const Icon(Icons.undo),
              onPressed: state.canUndo ? state.undo : null,
            ),
            IconButton(
              tooltip: l10n.editor_redo,
              icon: const Icon(Icons.redo),
              onPressed: state.canRedo ? state.redo : null,
            ),
          ],
        ),
      ),
    );
  }
}
