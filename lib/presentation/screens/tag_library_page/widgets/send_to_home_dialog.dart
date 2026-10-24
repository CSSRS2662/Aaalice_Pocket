import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/character_prompt_block_parser.dart';
import '../../../../core/utils/comfyui_prompt_parser/pipe_parser.dart';
import '../../../../core/utils/localization_extension.dart';
import '../../../../core/utils/sd_to_nai_converter.dart';
import '../../../../data/models/tag_library/tag_library_entry.dart';
import '../../../../presentation/providers/pending_prompt_provider.dart';
import '../../../adaptive/adaptive_presenter.dart';
import '../../../themes/core/layered_surface_style.dart';
import '../../../widgets/common/adaptive_dialog_frame.dart';
import '../../../widgets/common/themed_radio.dart';
import '../../../widgets/common/translated_tag_text.dart';

// 使用现有的 SendTargetType 从 pending_prompt_provider.dart

/// 发送选项配置
class SendOptions {
  final SendTargetType targetType;
  final bool sendAsAlias;

  const SendOptions({required this.targetType, this.sendAsAlias = false});
}

/// 发送到主页对话框
///
/// 功能：
/// 1. 智能检测竖线格式并提供分解选项
/// 2. 实时预览发送效果
/// 3. 别名解析开关
class SendToHomeDialog extends ConsumerStatefulWidget {
  final TagLibraryEntry entry;
  final ScrollController? scrollController;

  const SendToHomeDialog({
    super.key,
    required this.entry,
    this.scrollController,
  });

  static Future<SendOptions?> show(
    BuildContext context, {
    required TagLibraryEntry entry,
  }) {
    return AdaptivePresenter.showForm<SendOptions>(
      context: context,
      titleBuilder: (panelContext) {
        final theme = Theme.of(panelContext);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              panelContext.l10n.sendToHome_titleFor(entry.displayName),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              panelContext.l10n.sendToHome_chooseTarget,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        );
      },
      dialogWidth: 480,
      builder: (panelContext, scrollController) =>
          SendToHomeDialog(entry: entry, scrollController: scrollController),
    );
  }

  @override
  ConsumerState<SendToHomeDialog> createState() => _SendToHomeDialogState();
}

class _SendToHomeDialogState extends ConsumerState<SendToHomeDialog> {
  late SendTargetType _selectedTarget;
  bool _sendAsAlias = false;

  @override
  void initState() {
    super.initState();
    // 默认选择：如果是竖线格式，默认智能分解；否则发送到主提示词
    _selectedTarget = _isPipeFormat
        ? SendTargetType.smartDecompose
        : SendTargetType.mainPrompt;
  }

  /// 检测是否为竖线格式
  CharacterPromptBlockParseResult get _promptParts =>
      CharacterPromptBlockParser.parse(widget.entry.content);

  bool get _isPipeFormat =>
      PipeParser.isPipeFormat(_promptParts.positivePrompt);

  /// 获取发送内容
  /// 如果 sendAsAlias 为 true，返回 <条目名> 形式
  /// 否则返回实际内容
  String get _processedContent {
    if (_sendAsAlias) {
      // 作为别名发送：包装为 <条目名>
      return '<${widget.entry.name}>';
    }
    // 应用 SD→NAI 转换和格式化
    return SdToNaiConverter.convert(_promptParts.positivePrompt);
  }

  /// 解析竖线格式结果
  ParsedResult get _parsedResult {
    // 如果作为别名发送或非竖线格式，直接返回内容
    if (_sendAsAlias || !_isPipeFormat) {
      return ParsedResult(mainPrompt: _processedContent, characters: const []);
    }

    final result = PipeParser.parse(_processedContent);
    return ParsedResult(
      mainPrompt: result.globalPrompt,
      characters: result.characters.map((c) => c.prompt).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parsed = _parsedResult;

    return AdaptiveDialogFrame(
      key: const ValueKey('send-to-home-dialog-frame'),
      maxWidth: 480,
      maxHeight: 700,
      reservedVerticalSpace: 0,
      horizontalMargin: 0,
      child: SingleChildScrollView(
        key: const ValueKey('send-to-home-dialog-scroll'),
        controller: widget.scrollController,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTargetOptions(theme),
            const SizedBox(height: 16),
            _buildAliasToggle(theme),
            const Divider(height: 24),
            _buildPreviewSection(theme, parsed),
            const SizedBox(height: 16),
            _buildActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildActions() {
    final cancelButton = TextButton(
      onPressed: () => Navigator.of(context).pop(),
      child: Text(context.l10n.common_cancel),
    );
    final sendButton = FilledButton.icon(
      onPressed: () {
        Navigator.of(context).pop(
          SendOptions(targetType: _selectedTarget, sendAsAlias: _sendAsAlias),
        );
      },
      icon: const Icon(Icons.send, size: 18),
      label: Text(context.l10n.sendToHome_send),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
        if (constraints.maxWidth < 360 || textScale > 1.5) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [cancelButton, const SizedBox(height: 8), sendButton],
          );
        }
        return Row(
          children: [
            Expanded(child: cancelButton),
            const SizedBox(width: 12),
            Expanded(flex: 2, child: sendButton),
          ],
        );
      },
    );
  }

  /// 构建发送目标选项
  Widget _buildTargetOptions(ThemeData theme) {
    return Column(
      children: [
        // 主提示词选项（始终可用）
        _TargetOptionTile(
          title: context.l10n.sendToHome_mainPrompt,
          subtitle: _isPipeFormat
              ? context.l10n.sendToHome_mainPromptPipeSubtitle
              : context.l10n.sendToHome_mainPromptSubtitle,
          isSelected: _selectedTarget == SendTargetType.mainPrompt,
          onTap: () =>
              setState(() => _selectedTarget = SendTargetType.mainPrompt),
        ),
        // 智能分解选项（仅竖线格式可用）
        if (_isPipeFormat) ...[
          _TargetOptionTile(
            title: context.l10n.sendToHome_smartDecompose,
            subtitle: context.l10n.sendToHome_smartDecomposeSubtitle(
              _parsedResult.characters.length,
            ),
            isSelected: _selectedTarget == SendTargetType.smartDecompose,
            onTap: () =>
                setState(() => _selectedTarget = SendTargetType.smartDecompose),
            isRecommended: true,
          ),
        ],
        // 角色选项
        _TargetOptionTile(
          title: context.l10n.sendToHome_replaceCharacter,
          subtitle: context.l10n.sendToHome_replaceCharacterSubtitle,
          isSelected: _selectedTarget == SendTargetType.replaceCharacter,
          onTap: () =>
              setState(() => _selectedTarget = SendTargetType.replaceCharacter),
        ),
        _TargetOptionTile(
          title: context.l10n.sendToHome_appendCharacter,
          subtitle: context.l10n.sendToHome_appendCharacterSubtitle,
          isSelected: _selectedTarget == SendTargetType.appendCharacter,
          onTap: () =>
              setState(() => _selectedTarget = SendTargetType.appendCharacter),
        ),
        // 固定词选项
        _TargetOptionTile(
          title: context.l10n.sendToHome_fixedTags,
          subtitle: context.l10n.sendToHome_fixedTagsSubtitle,
          isSelected: _selectedTarget == SendTargetType.fixedTag,
          onTap: () =>
              setState(() => _selectedTarget = SendTargetType.fixedTag),
        ),
      ],
    );
  }

  /// 构建别名解析开关
  Widget _buildAliasToggle(ThemeData theme) {
    // The whole row toggles, so the label is as easy to hit as the switch.
    return MergeSemantics(
      child: Material(
        color: controlSurfaceColor(theme.colorScheme),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          key: const ValueKey('send-to-home-alias-row'),
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _sendAsAlias = !_sendAsAlias),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(
                  Icons.data_object_rounded,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.sendToHome_sendAsAlias,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        context.l10n.sendToHome_sendAsAliasSubtitle(
                          widget.entry.name,
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _sendAsAlias,
                  onChanged: (value) => setState(() => _sendAsAlias = value),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 构建预览区域
  Widget _buildPreviewSection(ThemeData theme, ParsedResult parsed) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: sectionSurfaceColor(theme.colorScheme),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.preview_outlined,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                context.l10n.sendToHome_preview,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildPreviewContent(theme, parsed),
        ],
      ),
    );
  }

  /// 构建预览内容
  Widget _buildPreviewContent(ThemeData theme, ParsedResult parsed) {
    // 作为别名发送时，统一显示别名形式
    if (_sendAsAlias) {
      return _buildAliasPreview(theme);
    }

    return switch (_selectedTarget) {
      SendTargetType.smartDecompose => _buildSmartDecomposePreview(
        theme,
        parsed,
      ),
      SendTargetType.mainPrompt => _PreviewItem(
        label: context.l10n.naiAlgorithm_mainPrompt,
        content: _processedContent,
        color: theme.colorScheme.primary,
      ),
      SendTargetType.replaceCharacter ||
      SendTargetType.appendCharacter => _buildCharacterPreview(parsed),
      SendTargetType.fixedTag => _PreviewItem(
        label: context.l10n.fixedTags_label,
        content: _processedContent,
        color: Colors.orange,
      ),
    };
  }

  /// 构建别名发送预览
  Widget _buildAliasPreview(ThemeData theme) {
    final (label, color) = switch (_selectedTarget) {
      SendTargetType.mainPrompt => (
        context.l10n.naiAlgorithm_mainPrompt,
        theme.colorScheme.primary,
      ),
      SendTargetType.smartDecompose => (
        context.l10n.sendToHome_smartDecompose,
        theme.colorScheme.tertiary,
      ),
      SendTargetType.replaceCharacter || SendTargetType.appendCharacter => (
        context.l10n.sendToHome_characterPrompt,
        theme.colorScheme.tertiary,
      ),
      SendTargetType.fixedTag => (context.l10n.fixedTags_label, Colors.orange),
    };
    return _PreviewItem(label: label, content: _processedContent, color: color);
  }

  /// 构建智能分解预览
  Widget _buildSmartDecomposePreview(ThemeData theme, ParsedResult parsed) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PreviewItem(
          label: context.l10n.naiAlgorithm_mainPrompt,
          content: parsed.mainPrompt,
          color: theme.colorScheme.primary,
        ),
        ...parsed.characters.asMap().entries.map(
          (e) => _PreviewItem(
            label: context.l10n.sendToHome_characterIndex(e.key + 1),
            content: e.value,
            color: theme.colorScheme.secondary,
          ),
        ),
      ],
    );
  }

  /// 构建角色预览
  Widget _buildCharacterPreview(ParsedResult parsed) {
    final hasCharacters = _isPipeFormat && parsed.characters.isNotEmpty;
    final content = hasCharacters
        ? parsed.characters.join('\n| ')
        : _processedContent;
    final label = hasCharacters
        ? context.l10n.sendToHome_characterPromptCount(parsed.characters.length)
        : context.l10n.sendToHome_characterPrompt;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PreviewItem(
          label: label,
          content: content,
          color: theme.colorScheme.tertiary,
        ),
        if (_promptParts.hasNegativeBlock &&
            _promptParts.negativePrompt.isNotEmpty) ...[
          const SizedBox(height: 12),
          _PreviewItem(
            label: context.l10n.prompt_negativePrompt,
            content: _promptParts.negativePrompt,
            color: theme.colorScheme.error,
          ),
        ],
      ],
    );
  }
}

/// 解析结果
class ParsedResult {
  final String mainPrompt;
  final List<String> characters;

  ParsedResult({required this.mainPrompt, required this.characters});
}

/// 一个发送目标：单选圆点、名称与说明。
class _TargetOptionTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isRecommended;

  const _TargetOptionTile({
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
    this.isRecommended = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Semantics(
      selected: isSelected,
      inMutuallyExclusiveGroup: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                ExcludeSemantics(
                  child: ThemedRadio<bool>(
                    value: true,
                    groupValue: isSelected,
                    onChanged: (_) => onTap(),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Wrap(
                        spacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            title,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                          ),
                          if (isRecommended)
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: colors.primaryContainer,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                child: Text(
                                  context.l10n.sendToHome_recommended,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colors.onPrimaryContainer,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
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

/// 预览项
class _PreviewItem extends StatelessWidget {
  final String label;
  final String content;
  final Color color;

  const _PreviewItem({
    required this.label,
    required this.content,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (content.isEmpty)
            Text(
              context.l10n.common_emptyValue,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            )
          else
            TranslatedPromptText(
              content,
              selectable: false,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface,
                height: 1.4,
              ),
              maxLines: 5,
            ),
        ],
      ),
    );
  }
}
