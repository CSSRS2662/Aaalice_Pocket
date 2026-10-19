import 'package:flutter/material.dart';

import '../../../../../core/utils/localization_extension.dart';
import '../../../../adaptive/adaptive_presenter.dart';
import '../../core/editor_state.dart';
import '../../core/editor_tool_groups.dart';
import '../../tools/tool_base.dart';
import '../toolbar/editor_toolbar_tools.dart';
import '../toolbar/mobile_toolbar.dart';
import 'editor_segmented_switch.dart';
import 'mobile_tool_quick_options.dart';

/// 工具栏上方的选项条：折叠工具的同族切换、当前工具的常用设置与「全部参数」
class MobileToolOptionsBar extends StatelessWidget {
  const MobileToolOptionsBar({
    super.key,
    required this.state,
    this.onShiftEdges,
  });

  final EditorState state;
  final VoidCallback? onShiftEdges;

  static const double height = 60;

  /// 工具自己的完整设置面板，与桌面右侧面板相同
  Future<void> _showSettings(BuildContext context) async {
    final tool = state.currentTool;
    if (tool == null) return;
    await AdaptivePresenter.showPanel<void>(
      context: context,
      // 面板自带工具名标题，面板标题写入口名称，避免重复
      title: context.l10n.editor_toolAllSettings,
      // 矮横屏上半屏放不下一行设置，直接展开到接近全高
      initialChildSize: MediaQuery.sizeOf(context).height < 500 ? 0.9 : 0.6,
      builder: (context, scrollController) => SingleChildScrollView(
        key: const ValueKey('editor-tool-settings-sheet'),
        controller: scrollController,
        child: ValueListenableBuilder<EditorTool?>(
          valueListenable: state.toolChangeNotifier,
          builder: (context, current, _) =>
              (current ?? tool).buildSettingsPanel(context, state),
        ),
      ),
    );
    // 部分面板只刷新自身，关闭后让选项条与滑杆读到新值
    if (!state.isDisposed) state.requestUiUpdate();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const ValueKey('editor-tool-options'),
      color: Theme.of(context).colorScheme.surface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: height),
        child: ListenableBuilder(
          listenable: Listenable.merge([
            state,
            editorToolAvailability(state),
            state.selectionManager.selectionNotifier,
          ]),
          builder: (context, _) {
            final tool = state.currentTool;
            final slot = mobileSlotOfCurrentTool(state);
            return Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 6, 4, 6),
              child: Row(
                children: [
                  if (slot != null && slot.isFolded) ...[
                    // 至多占一半，留出常用设置的位置
                    Flexible(
                      child: _VariantSwitch(state: state, slot: slot),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: MobileToolQuickOptions(
                      state: state,
                      onShiftEdges: onShiftEdges,
                      onShowSettings: () => _showSettings(context),
                    ),
                  ),
                  if (tool != null)
                    IconButton(
                      key: const ValueKey('editor-tool-settings-button'),
                      tooltip: context.l10n.editor_toolAllSettings,
                      icon: const Icon(Icons.tune),
                      onPressed: () => _showSettings(context),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 折叠按钮里的同族工具：选中的显示名称，其余只显示图标
class _VariantSwitch extends StatelessWidget {
  const _VariantSwitch({required this.state, required this.slot});

  final EditorState state;
  final EditorToolSlot slot;

  @override
  Widget build(BuildContext context) {
    final entries = slot.entries;
    EditorToolEntry? selected;
    for (final entry in entries) {
      if (isEditorToolEntrySelected(state, entry)) selected = entry;
    }
    return EditorSegmentedSwitch<EditorToolEntry>(
      labelSelectedOnly: true,
      segments: [
        for (final entry in entries)
          EditorSegment(
            key: ValueKey('editor-tool-variant-${entry.tool.id}'),
            value: entry,
            label: editorToolLabel(context, entry.tool, entry.targetRole),
            icon: entry.tool.icon,
          ),
      ],
      selected: selected,
      onSelected: (entry) => activateEditorToolEntry(state, entry),
    );
  }
}
