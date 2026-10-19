import 'package:flutter/material.dart';

import '../../../common/horizontal_action_strip.dart';
import '../../../common/themed_divider.dart';
import '../../core/editor_state.dart';
import '../../core/editor_tool_groups.dart';
import '../../tools/tool_base.dart';
import 'editor_toolbar_flyout.dart';
import 'editor_toolbar_tools.dart';

/// 重绘会话一次只列出当前编辑对象（蒙版或图片）的工具组和通用组；
/// 编辑会话没有角色，列出全部组
List<EditorToolSection> mobileEditorToolSections(EditorState state) {
  final sections = editorToolSections(state);
  if (!state.rolePolicy.rolesEnabled) return sections;
  final roleGroup = editorToolGroupForRole(state.activeLayerRole);
  return [
    for (final section in sections)
      if (section.group == roleGroup || section.group == EditorToolGroup.common)
        section,
  ];
}

/// [tool] 此刻在移动端工具栏上有入口
bool isEditorToolShownOnMobile(EditorState state, EditorTool tool) {
  return mobileEditorToolSections(state).any(
    (section) => section.entries.any(
      (entry) =>
          entry.tool == tool &&
          (entry.targetRole == null ||
              entry.targetRole == state.activeLayerRole),
    ),
  );
}

/// 当前工具所在的按钮；不在工具栏上时为空
EditorToolSlot? mobileSlotOfCurrentTool(EditorState state) {
  for (final section in mobileEditorToolSections(state)) {
    for (final slot in section.slots) {
      if (slot.entries.any(
        (entry) => isEditorToolEntrySelected(state, entry),
      )) {
        return slot;
      }
    }
  }
  return null;
}

/// 移动端工具栏：图标加短名；放得下时等分整行，放不下时滚动
class MobileToolbar extends StatelessWidget {
  const MobileToolbar({
    super.key,
    required this.state,
    this.axis = Axis.horizontal,
  });

  final EditorState state;

  /// 横屏时竖排在画布左侧
  final Axis axis;

  /// 横排时的高度、竖排时的宽度
  static const double extent = 64;

  static const double _slotExtent = 52;

  @override
  Widget build(BuildContext context) {
    final horizontal = axis == Axis.horizontal;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SizedBox(
        height: horizontal ? extent : null,
        width: horizontal ? null : extent,
        child: ListenableBuilder(
          listenable: editorToolAvailability(state),
          builder: (context, _) => LayoutBuilder(
            builder: (context, constraints) {
              final sections = mobileEditorToolSections(state);
              final slotCount = sections.fold(
                0,
                (count, section) => count + section.slots.length,
              );
              final available = horizontal
                  ? constraints.maxWidth
                  : constraints.maxHeight;
              final fits = available >= slotCount * _slotExtent + 16;
              final row = Flex(
                direction: axis,
                mainAxisSize: fits ? MainAxisSize.max : MainAxisSize.min,
                children: [
                  for (final (index, section) in sections.indexed) ...[
                    if (index > 0)
                      ThemedDivider(
                        height: 1,
                        vertical: horizontal,
                        indent: 16,
                        endIndent: 16,
                      ),
                    _wrapFlexible(
                      fits,
                      section.slots.length,
                      _MobileToolSection(
                        key: ValueKey(
                          'editor-tool-group-${section.group.name}',
                        ),
                        state: state,
                        section: section,
                        axis: axis,
                        expand: fits,
                      ),
                    ),
                  ],
                ],
              );
              final padded = Padding(
                padding: horizontal
                    ? const EdgeInsets.symmetric(horizontal: 4)
                    : const EdgeInsets.symmetric(vertical: 4),
                child: row,
              );
              if (fits) return padded;
              return horizontal
                  ? HorizontalActionStrip(child: padded)
                  : SingleChildScrollView(child: padded);
            },
          ),
        ),
      ),
    );
  }

  static Widget _wrapFlexible(bool expand, int flex, Widget child) =>
      expand ? Expanded(flex: flex, child: child) : child;
}

class _MobileToolSection extends StatelessWidget {
  const _MobileToolSection({
    super.key,
    required this.state,
    required this.section,
    required this.axis,
    required this.expand,
  });

  final EditorState state;
  final EditorToolSection section;
  final Axis axis;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Flex(
        direction: axis,
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: [
          for (final slot in section.slots)
            MobileToolbar._wrapFlexible(
              expand,
              1,
              _MobileToolSlot(
                key: ValueKey('editor-tool-slot-${slot.key}'),
                state: state,
                slot: slot,
                axis: axis,
              ),
            ),
        ],
      ),
    );
  }
}

/// 折叠按钮显示该族当前或最近用过的工具；选中后再点一次换到同族下一个，
/// 长按仍可展开同族工具
class _MobileToolSlot extends StatelessWidget {
  const _MobileToolSlot({
    super.key,
    required this.state,
    required this.slot,
    required this.axis,
  });

  final EditorState state;
  final EditorToolSlot slot;
  final Axis axis;

  @override
  Widget build(BuildContext context) {
    final entry = displayedEntryOf(state, slot);
    final selected = isEditorToolEntrySelected(state, entry);
    final button = _MobileToolButton(
      key: ValueKey('editor-tool-${entry.key}'),
      icon: entry.tool.icon,
      label: editorToolLabel(context, entry.tool, entry.targetRole),
      shortLabel: editorToolShortLabel(context, entry.tool, entry.targetRole),
      isSelected: selected,
      folded: slot.isFolded,
      onTap: () {
        if (slot.isFolded && selected) {
          final entries = slot.entries;
          final next = entries[(entries.indexOf(entry) + 1) % entries.length];
          activateEditorToolEntry(state, next);
        } else {
          activateEditorToolEntry(state, entry);
        }
      },
    );
    if (!slot.isFolded) return button;
    return EditorToolbarFlyout(
      placement: axis == Axis.horizontal
          ? EditorToolbarFlyoutPlacement.above
          : EditorToolbarFlyoutPlacement.side,
      items: editorToolSlotFlyoutItems(context, state, slot),
      child: button,
    );
  }
}

class _MobileToolButton extends StatelessWidget {
  const _MobileToolButton({
    super.key,
    required this.icon,
    required this.label,
    required this.shortLabel,
    required this.isSelected,
    required this.onTap,
    this.folded = false,
  });

  final IconData icon;
  final String label;
  final String shortLabel;
  final bool isSelected;
  final VoidCallback onTap;

  /// 同族还有其他工具
  final bool folded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final iconColor = isSelected
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurfaceVariant;

    final button = Semantics(
      button: true,
      selected: isSelected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 56),
          child: ExcludeSemantics(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Material(
                  color: isSelected
                      ? colorScheme.primaryContainer
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  animationDuration: Duration.zero,
                  child: SizedBox(
                    width: 46,
                    height: 32,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Center(child: Icon(icon, size: 21, color: iconColor)),
                        if (folded)
                          EditorToolbarFoldIndicator(color: iconColor),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.3,
                  child: Text(
                    shortLabel,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isSelected
                          ? colorScheme.onSurface
                          : colorScheme.onSurfaceVariant,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      // 折叠按钮的说明交给二级菜单，长按也留给它
      child: folded
          ? button
          : Tooltip(message: label, excludeFromSemantics: true, child: button),
    );
  }
}
