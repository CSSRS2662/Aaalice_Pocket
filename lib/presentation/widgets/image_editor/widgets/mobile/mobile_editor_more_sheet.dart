import 'package:flutter/material.dart';

import '../../../../adaptive/adaptive_presenter.dart';
import '../../../../themes/design_tokens.dart';
import '../../../common/heading_semantics.dart';

/// 「更多」里的一项；在打开面板时求值，启用状态跟随当时的编辑状态
@immutable
class EditorMenuAction {
  const EditorMenuAction({
    required this.id,
    required this.icon,
    required this.label,
    required this.onSelected,
    this.enabled = true,
    this.trailing,
  });

  /// 测试与读屏用的稳定标识
  final String id;
  final IconData icon;
  final String label;
  final VoidCallback onSelected;
  final bool enabled;

  /// 行尾的当前值，例如输出尺寸
  final String? trailing;
}

/// 按职责分组的一段操作
@immutable
class EditorMenuSection {
  const EditorMenuSection({required this.title, required this.actions});

  final String title;
  final List<EditorMenuAction> actions;
}

/// 移动端顶栏「更多」：分组列出蒙版、图层与画布操作，关闭面板后再执行所选操作
Future<void> showEditorMoreSheet(
  BuildContext context, {
  required List<EditorMenuSection> sections,
}) async {
  final chosen = await AdaptivePresenter.showPanel<VoidCallback>(
    context: context,
    title: MaterialLocalizations.of(context).moreButtonTooltip,
    initialChildSize: 0.55,
    dialogWidth: 420,
    // 项数很少，一次建好；放大文字时整体滚动
    builder: (panelContext, scrollController) => SingleChildScrollView(
      key: const ValueKey('editor-more-sheet'),
      controller: scrollController,
      padding: const EdgeInsets.only(bottom: DesignTokens.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final section in sections)
            if (section.actions.isNotEmpty) ...[
              _SectionHeader(title: section.title),
              for (final action in section.actions)
                _ActionTile(
                  action: action,
                  onTap: () =>
                      Navigator.of(panelContext).pop(action.onSelected),
                ),
            ],
        ],
      ),
    ),
  );
  chosen?.call();
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return HeadingSemantics(
      level: 3,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          DesignTokens.spacingLg,
          DesignTokens.spacingMd,
          DesignTokens.spacingLg,
          DesignTokens.spacingXxs,
        ),
        child: Text(
          title,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.action, required this.onTap});

  final EditorMenuAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final trailing = action.trailing;
    return ListTile(
      key: ValueKey('editor-more-${action.id}'),
      enabled: action.enabled,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spacingLg,
      ),
      leading: Icon(action.icon),
      title: Text(action.label),
      trailing: trailing == null
          ? null
          : Text(
              trailing,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
      onTap: onTap,
    );
  }
}
