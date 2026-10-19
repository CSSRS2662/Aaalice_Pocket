import 'package:flutter/material.dart';

import '../../core/editor_state.dart';
import '../../layers/layer_role.dart';
import '../toolbar/mobile_toolbar.dart';
import 'editor_tool_slider_rail.dart';
import 'mobile_canvas_controls.dart';
import 'mobile_editor_top_bar.dart';
import 'mobile_tool_options_bar.dart';

/// 移动端编辑器：顶栏、可选的横幅（聚焦重绘条）、画布与浮层、选项条和工具栏。
/// 矮横屏时工具栏竖排在画布左侧，其余结构不变。
class MobileEditorLayout extends StatefulWidget {
  const MobileEditorLayout({
    super.key,
    required this.state,
    required this.title,
    required this.canvas,
    required this.doneLabel,
    required this.onDone,
    required this.doneListenable,
    required this.canDone,
    required this.onShowLayers,
    required this.onShowMore,
    this.banner,
    this.canvasChips = const [],
    this.onShiftEdges,
  });

  final EditorState state;
  final String title;
  final Widget canvas;
  final String doneLabel;
  final VoidCallback onDone;
  final Listenable doneListenable;
  final bool Function() canDone;
  final VoidCallback onShowLayers;
  final VoidCallback onShowMore;
  final Widget? banner;

  /// 画布左上角的状态胶囊
  final List<Widget> canvasChips;
  final VoidCallback? onShiftEdges;

  @override
  State<MobileEditorLayout> createState() => _MobileEditorLayoutState();
}

class _MobileEditorLayoutState extends State<MobileEditorLayout> {
  /// 拖动大小滑杆时的笔刷直径（文档像素）
  final ValueNotifier<double?> _sizePreview = ValueNotifier(null);
  late LayerRole _role;

  EditorState get _state => widget.state;

  @override
  void initState() {
    super.initState();
    _role = _state.activeLayerRole;
    _state.toolNotifier.addListener(_rememberTool);
    _state.layerManager.activeLayerNotifier.addListener(_followRole);
  }

  @override
  void didUpdateWidget(MobileEditorLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      oldWidget.state.toolNotifier.removeListener(_rememberTool);
      oldWidget.state.layerManager.activeLayerNotifier.removeListener(
        _followRole,
      );
      _role = _state.activeLayerRole;
      _state.toolNotifier.addListener(_rememberTool);
      _state.layerManager.activeLayerNotifier.addListener(_followRole);
    }
  }

  @override
  void dispose() {
    _state.toolNotifier.removeListener(_rememberTool);
    _state.layerManager.activeLayerNotifier.removeListener(_followRole);
    _sizePreview.dispose();
    super.dispose();
  }

  static String _roleToolKey(LayerRole role) => 'mobile:role-tool:${role.name}';

  /// 记住每种编辑对象上次用的工具；切换角色途中（尚未跟上）的退回不算
  void _rememberTool() {
    final tool = _state.currentTool;
    final role = _state.activeLayerRole;
    if (tool == null || role != _role) return;
    if (!isEditorToolShownOnMobile(_state, tool)) return;
    _state.toolbarSlotMemory.remember(_roleToolKey(role), tool.id);
  }

  /// 换到另一种编辑对象时回到它上次的工具；当前工具在新工具栏上没有入口时退回画笔
  void _followRole() {
    final role = _state.activeLayerRole;
    if (role == _role) return;
    _role = role;
    if (!_state.rolePolicy.rolesEnabled) return;
    final rememberedId = _state.toolbarSlotMemory.recall(_roleToolKey(role));
    final remembered = rememberedId == null
        ? null
        : _state.toolManager.getToolById(rememberedId);
    if (remembered != null &&
        remembered.isAvailableIn(_state) &&
        isEditorToolShownOnMobile(_state, remembered)) {
      _state.setTool(remembered);
      return;
    }
    final current = _state.currentTool;
    if (current == null || !isEditorToolShownOnMobile(_state, current)) {
      _state.setToolById('brush');
    }
  }

  @override
  Widget build(BuildContext context) {
    final topBar = MobileEditorTopBar(
      state: _state,
      title: widget.title,
      doneLabel: widget.doneLabel,
      onDone: widget.onDone,
      doneListenable: widget.doneListenable,
      canDone: widget.canDone,
      onShowLayers: widget.onShowLayers,
      onShowMore: widget.onShowMore,
    );
    final options = MobileToolOptionsBar(
      state: _state,
      onShiftEdges: widget.onShiftEdges,
    );
    final canvas = _CanvasStack(
      state: _state,
      canvas: widget.canvas,
      chips: widget.canvasChips,
      sizePreview: _sizePreview,
    );
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final landscape =
                constraints.maxWidth > constraints.maxHeight &&
                constraints.maxHeight < 520;
            return Column(
              children: [
                topBar,
                ?widget.banner,
                Expanded(
                  child: landscape
                      ? Row(
                          children: [
                            MobileToolbar(state: _state, axis: Axis.vertical),
                            Expanded(
                              child: Column(
                                children: [
                                  Expanded(child: canvas),
                                  options,
                                ],
                              ),
                            ),
                          ],
                        )
                      : canvas,
                ),
                if (!landscape) ...[options, MobileToolbar(state: _state)],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 画布与浮在其上的控件：左上状态胶囊、右上缩放、右侧滑杆与右下撤销重做。
/// 浮层之间的空白不拦截指针，仍可在那里绘制。
class _CanvasStack extends StatelessWidget {
  const _CanvasStack({
    required this.state,
    required this.canvas,
    required this.chips,
    required this.sizePreview,
  });

  final EditorState state;
  final Widget canvas;
  final List<Widget> chips;
  final ValueNotifier<double?> sizePreview;

  static const double _inset = 8;
  static const double _controlExtent = 48;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final railSpace =
            constraints.maxHeight - 2 * _controlExtent - 4 * _inset;
        return Stack(
          children: [
            Positioned.fill(child: canvas),
            Positioned(
              top: _inset,
              left: _inset,
              right: _inset,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Align(
                      alignment: AlignmentDirectional.topStart,
                      child: Wrap(spacing: 8, runSpacing: 8, children: chips),
                    ),
                  ),
                  const SizedBox(width: 8),
                  EditorZoomChip(state: state),
                ],
              ),
            ),
            PositionedDirectional(
              end: _inset,
              bottom: _inset,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                spacing: _inset,
                children: [
                  EditorToolSliderRail(
                    state: state,
                    maxHeight: railSpace,
                    onSizePreview: (size) => sizePreview.value = size,
                  ),
                  EditorUndoRedoPill(state: state),
                ],
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: ValueListenableBuilder<double?>(
                  valueListenable: sizePreview,
                  builder: (context, size, _) => size == null
                      ? const SizedBox.shrink()
                      : Center(
                          child: _SizePreviewRing(
                            diameter: size * state.canvasController.scale,
                          ),
                        ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 笔刷实际落在画布上的大小；深浅两道描边在任何底图上都看得见
class _SizePreviewRing extends StatelessWidget {
  const _SizePreviewRing({required this.diameter});

  final double diameter;

  @override
  Widget build(BuildContext context) {
    final size = diameter.clamp(4.0, 2000.0);
    return Container(
      key: const ValueKey('editor-size-preview'),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.black54),
        ),
      ),
    );
  }
}
