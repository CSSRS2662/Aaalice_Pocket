import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nai_launcher/core/utils/localization_extension.dart';

import '../../../../../core/autocomplete/tag_translation_lookup.dart';
import '../../../../../core/utils/nai_prompt_parser.dart';
import '../../../../adaptive/interaction_policy.dart';
import '../../../../themes/core/layered_surface_style.dart';
import '../../app_toast.dart';
import '../../translated_tag_text.dart';
import 'detail_tag_picks.dart';
import 'selection_copy_shortcuts.dart';

/// 提示词分组展示组件
///
/// 用于在图像详情页中展示分组提示词（主提示词、固定词、质量词等）
/// 支持展开/折叠、复制、添加到词库等功能。给出 [tagPicks] 时，长按词条
/// 开始多选，之后轻点即选中或取消，标题栏换成本组的全选。
class PromptSection extends StatefulWidget {
  final String title;
  final IconData icon;
  final String content;
  final List<String>? tags;
  final bool initiallyExpanded;
  final bool showAddToLibrary;
  final VoidCallback? onAddToLibrary;
  final Future<void> Function()? onCopy;
  final Color? borderColor;
  final bool showTranslation;
  final Widget? customContent;
  final List<String> fixedTags;
  final List<String> characterTags;
  final Set<int>? fixedTagIndexes;
  final Set<int>? characterTagIndexes;
  final bool allTagsAreFixed;
  final bool isNegative;

  /// The picks shared by the panel's sections; null turns picking off.
  final DetailTagPicks? tagPicks;

  /// Which prompt this section's tags are picked as.
  final DetailTagSide pickSide;
  final int tagIndexOffset;
  final bool cardStyle;
  final bool encloseContent;
  final VoidCallback? onReuse;

  const PromptSection({
    super.key,
    required this.title,
    required this.icon,
    required this.content,
    this.tags,
    this.initiallyExpanded = false,
    this.showAddToLibrary = false,
    this.onAddToLibrary,
    this.onCopy,
    this.borderColor,
    this.showTranslation = true,
    this.customContent,
    this.fixedTags = const [],
    this.characterTags = const [],
    this.fixedTagIndexes,
    this.characterTagIndexes,
    this.allTagsAreFixed = false,
    this.isNegative = false,
    this.tagPicks,
    this.pickSide = DetailTagSide.positive,
    this.tagIndexOffset = 0,
    this.cardStyle = false,
    this.encloseContent = true,
    this.onReuse,
  });

  @override
  State<PromptSection> createState() => _PromptSectionState();
}

class _PromptSectionState extends State<PromptSection> {
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
  }

  Future<void> _copyContent() async {
    if (widget.content.isEmpty) return;

    await Clipboard.setData(ClipboardData(text: widget.content));
    if (mounted) {
      AppToast.success(context, context.l10n.toast_copiedTitle(widget.title));
    }
  }

  void _copyTag(String tag) {
    Clipboard.setData(ClipboardData(text: tag));
    AppToast.success(context, context.l10n.toast_tagCopied);
  }

  bool get _picking => widget.tagPicks?.active ?? false;

  /// A tap copies the tag, or picks it while picking.
  void _tapTag(int index, String tag) {
    final picks = widget.tagPicks;
    if (picks != null && picks.active) {
      picks.toggle(widget.pickSide, widget.tagIndexOffset + index, tag);
    } else {
      _copyTag(tag);
    }
  }

  /// A long press starts picking with the tag, or picks it.
  VoidCallback? _longPressTag(int index, String tag) {
    final picks = widget.tagPicks;
    if (picks == null) return null;
    return () =>
        picks.toggle(widget.pickSide, widget.tagIndexOffset + index, tag);
  }

  List<String> get _displayTags {
    if (widget.tags != null) return widget.tags!;
    if (widget.content.isEmpty) return [];
    return NaiPromptParser.splitSegments(widget.content);
  }

  int get _tagCount {
    if (widget.tags != null) return widget.tags!.length;
    return _displayTags.length;
  }

  int get _pickedCount => List.generate(_tagCount, (index) => index)
      .where(
        (index) => widget.tagPicks!.isPicked(
          widget.pickSide,
          widget.tagIndexOffset + index,
        ),
      )
      .length;

  @override
  Widget build(BuildContext context) {
    final picks = widget.tagPicks;
    if (picks == null) return _buildSection(context);
    return ListenableBuilder(
      listenable: picks,
      builder: (context, _) => _buildSection(context),
    );
  }

  Widget _buildSection(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasContent = widget.content.isNotEmpty;
    if (widget.cardStyle) return _buildCard(theme, colorScheme, hasContent);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(colorScheme, theme, hasContent),
        ClipRect(
          child: AnimatedSize(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _isExpanded && hasContent
                ? Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: _buildContent(colorScheme, theme, _displayTags),
                  )
                : const SizedBox(width: double.infinity, height: 0),
          ),
        ),
      ],
    );
  }

  Widget _buildCard(ThemeData theme, ColorScheme colors, bool hasContent) {
    final radius = BorderRadius.circular(12);
    return IntrinsicHeight(
      child: Material(
        color: sectionSurfaceColor(colors),
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: hasContent
              ? () => setState(() => _isExpanded = !_isExpanded)
              : null,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildCardTitle(theme, colors),
                if (_isExpanded && hasContent) ...[
                  const SizedBox(height: 8),
                  _buildContent(colors, theme, _displayTags),
                ] else if (!widget.allTagsAreFixed && hasContent)
                  Text(
                    widget.content,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                const Spacer(),
                const SizedBox(height: 4),
                _buildCardActions(theme, colors),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCardTitle(ThemeData theme, ColorScheme colors) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 44),
    child: Row(
      children: [
        Icon(
          widget.icon,
          size: 14,
          color: widget.allTagsAreFixed
              ? colors.tertiary
              : widget.isNegative
              ? colors.error
              : colors.primary,
        ),
        const SizedBox(width: 4),
        Expanded(child: Text(widget.title, style: theme.textTheme.titleSmall)),
        const SizedBox(width: 4),
        Icon(
          _isExpanded ? Icons.expand_less : Icons.expand_more,
          size: 16,
          color: colors.onSurfaceVariant,
        ),
      ],
    ),
  );

  Widget _buildCardActions(ThemeData theme, ColorScheme colors) => Wrap(
    alignment: WrapAlignment.spaceBetween,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Text(
        _picking ? '$_pickedCount/$_tagCount' : '$_tagCount',
        style: theme.textTheme.labelSmall?.copyWith(
          color: colors.onSurfaceVariant,
        ),
      ),
      if (_picking)
        _buildPickAllButton(colors, 44)
      else
        IconButton(
          key: const ValueKey('detail-reuse-group'),
          tooltip: context.l10n.detail_reusePromptGroup,
          onPressed: widget.onReuse,
          icon: const Icon(Icons.playlist_add, size: 20),
          style: IconButton.styleFrom(minimumSize: const Size.square(44)),
        ),
    ],
  );

  Widget _buildHeader(
    ColorScheme colorScheme,
    ThemeData theme,
    bool hasContent,
  ) {
    final actionTargetSize = context.interactionPolicy.minimumControlExtent;
    final accentColor = widget.allTagsAreFixed
        ? colorScheme.tertiary
        : widget.isNegative
        ? colorScheme.error
        : colorScheme.primary;
    final titleColor = hasContent
        ? colorScheme.onSurface
        : colorScheme.onSurfaceVariant;

    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: hasContent
                ? () => setState(() => _isExpanded = !_isExpanded)
                : null,
            child: MouseRegion(
              cursor: hasContent
                  ? SystemMouseCursors.click
                  : SystemMouseCursors.basic,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: context.interactionPolicy.minimumControlExtent,
                ),
                child: Row(
                  children: [
                    Icon(
                      widget.icon,
                      size: 16,
                      color: hasContent ? accentColor : titleColor,
                    ),
                    const SizedBox(width: 6),
                    // The title takes the room it needs before the count;
                    // the chevron keeps to the end.
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              widget.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: titleColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (hasContent)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: accentColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                _picking
                                    ? '$_pickedCount'
                                          '/$_tagCount'
                                    : '$_tagCount',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: accentColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (hasContent)
                      Icon(
                        _isExpanded ? Icons.expand_less : Icons.expand_more,
                        size: 20,
                        color: colorScheme.onSurfaceVariant,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (hasContent && _picking) ...[
          const SizedBox(width: 4),
          _buildPickAllButton(colorScheme, actionTargetSize),
        ] else if (hasContent) ...[
          const SizedBox(width: 4),
          IconButton(
            onPressed: widget.onCopy ?? _copyContent,
            icon: Icon(
              Icons.copy,
              size: 16,
              color: colorScheme.onSurfaceVariant,
            ),
            tooltip: context.l10n.detail_copyLabel(widget.title),
            style: IconButton.styleFrom(
              padding: const EdgeInsets.all(6),
              minimumSize: Size.square(actionTargetSize),
            ),
          ),
          if (widget.showAddToLibrary && widget.onAddToLibrary != null)
            IconButton(
              onPressed: widget.onAddToLibrary,
              icon: Icon(
                Icons.library_add,
                size: 16,
                color: colorScheme.onSurfaceVariant,
              ),
              tooltip: context.l10n.tagLibrary_addToLibrary,
              style: IconButton.styleFrom(
                padding: const EdgeInsets.all(6),
                minimumSize: Size.square(actionTargetSize),
              ),
            ),
        ],
      ],
    );
  }

  /// Picks every tag of the section, or drops them once all are picked.
  Widget _buildPickAllButton(ColorScheme colorScheme, double targetSize) {
    final picks = widget.tagPicks!;
    final tags = _displayTags;
    final all = tags.isNotEmpty && _pickedCount == tags.length;
    return IconButton(
      key: ValueKey('detail-pick-all-${widget.pickSide.name}'),
      onPressed: () => picks.setRange(
        widget.pickSide,
        tags,
        offset: widget.tagIndexOffset,
        picked: !all,
      ),
      icon: Icon(
        all ? Icons.deselect_rounded : Icons.select_all_rounded,
        size: 18,
        color: all ? colorScheme.primary : colorScheme.onSurfaceVariant,
      ),
      tooltip: all
          ? context.l10n.common_deselectAll
          : context.l10n.common_selectAll,
      style: IconButton.styleFrom(
        padding: const EdgeInsets.all(6),
        minimumSize: Size.square(targetSize),
      ),
    );
  }

  Widget _buildContent(
    ColorScheme colorScheme,
    ThemeData theme,
    List<String> tags,
  ) {
    final surfaceColor = widget.isNegative
        ? colorScheme.errorContainer.withValues(alpha: 0.12)
        : widget.borderColor?.withValues(alpha: 0.10) ??
              colorScheme.surfaceContainerLow;

    final content =
        widget.customContent ??
        (tags.isNotEmpty
            ? _TagChipGrid(
                tags: tags,
                onTagTap: _tapTag,
                onTagLongPress: _longPressTag,
                pickedOf: _picking
                    ? (index) => widget.tagPicks!.isPicked(
                        widget.pickSide,
                        widget.tagIndexOffset + index,
                      )
                    : null,
                showTranslation: widget.showTranslation,
                fixedTags: widget.fixedTags,
                characterTags: widget.characterTags,
                fixedTagIndexes: widget.fixedTagIndexes,
                characterTagIndexes: widget.characterTagIndexes,
                allTagsAreFixed: widget.allTagsAreFixed,
                isNegative: widget.isNegative,
              )
            : Text(
                context.l10n.detail_noContent,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ));
    if (widget.cardStyle || !widget.encloseContent) return content;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: content,
    );
  }
}

String _normalizePromptTag(String tag) {
  var result = tag.trim().toLowerCase();
  final weighted = RegExp(
    r'^-?\d+(?:\.\d+)?::(.+?)(?:::)?$',
  ).firstMatch(result);
  if (weighted != null) result = weighted.group(1)!.trim();
  result = result.replaceFirst(RegExp(r'^[\{\[]+'), '');
  result = result.replaceFirst(RegExp(r'[\}\]]+$'), '');
  return result.trim();
}

/// 标签芯片网格组件
class _TagChipGrid extends StatelessWidget {
  final List<String> tags;
  final void Function(int index, String tag) onTagTap;
  final VoidCallback? Function(int index, String tag) onTagLongPress;

  /// Whether the tag at an index is picked; null while not picking.
  final bool Function(int index)? pickedOf;
  final bool showTranslation;
  final List<String> fixedTags;
  final List<String> characterTags;
  final Set<int>? fixedTagIndexes;
  final Set<int>? characterTagIndexes;
  final bool allTagsAreFixed;
  final bool isNegative;

  const _TagChipGrid({
    required this.tags,
    required this.onTagTap,
    required this.onTagLongPress,
    required this.pickedOf,
    required this.fixedTags,
    required this.characterTags,
    required this.fixedTagIndexes,
    required this.characterTagIndexes,
    required this.allTagsAreFixed,
    required this.isNegative,
    this.showTranslation = true,
  });

  @override
  Widget build(BuildContext context) {
    final normalizedFixedTags = fixedTags
        .expand(NaiPromptParser.splitSegments)
        .map(_normalizePromptTag)
        .where((tag) => tag.isNotEmpty)
        .toSet();
    final normalizedCharacterTags = characterTags
        .expand(NaiPromptParser.splitSegments)
        .map(_normalizePromptTag)
        .where((tag) => tag.isNotEmpty)
        .toSet();

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: tags
          .asMap()
          .entries
          .map(
            (entry) => _TranslatedTagChip(
              tag: entry.value,
              onTap: () => onTagTap(entry.key, entry.value),
              onLongPress: onTagLongPress(entry.key, entry.value),
              picked: pickedOf?.call(entry.key),
              showTranslation: showTranslation,
              isFixed:
                  allTagsAreFixed ||
                  (fixedTagIndexes?.contains(entry.key) ??
                      normalizedFixedTags.contains(
                        _normalizePromptTag(entry.value),
                      )),
              isCharacter:
                  characterTagIndexes?.contains(entry.key) ??
                  normalizedCharacterTags.contains(
                    _normalizePromptTag(entry.value),
                  ),
              isNegative: isNegative,
            ),
          )
          .toList(),
    );
  }
}

/// 带翻译的标签芯片组件
class _TranslatedTagChip extends ConsumerStatefulWidget {
  final String tag;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// Whether the chip is picked; null while not picking.
  final bool? picked;
  final bool showTranslation;
  final bool isFixed;
  final bool isCharacter;
  final bool isNegative;

  const _TranslatedTagChip({
    required this.tag,
    required this.onTap,
    required this.onLongPress,
    required this.picked,
    required this.isFixed,
    required this.isCharacter,
    required this.isNegative,
    this.showTranslation = true,
  });

  @override
  ConsumerState<_TranslatedTagChip> createState() => _TranslatedTagChipState();
}

class _TranslatedTagChipState extends ConsumerState<_TranslatedTagChip> {
  bool _isHovered = false;
  String? _translation;

  @override
  void initState() {
    super.initState();
    _loadTranslation();
  }

  @override
  void didUpdateWidget(_TranslatedTagChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tag != oldWidget.tag) {
      _translation = null;
      _loadTranslation();
    }
  }

  Future<void> _loadTranslation() async {
    if (!widget.showTranslation) return;
    final service = ref.read(tagTranslationLookupProvider);
    // 提取基础标签（去除权重语法）
    final baseTag = _extractBaseTag(widget.tag);
    final result = await service.translate(baseTag);
    if (mounted && result != null) {
      setState(() => _translation = result);
    }
  }

  /// 从带权重的标签中提取基础标签
  /// 例如: "1.10::jaggy_lines::" -> "jaggy_lines"
  String _extractBaseTag(String tag) {
    var text = tag.trim();

    // 1. 处理 NAI 数值权重语法: weight::text::
    final weightMatch = RegExp(
      r'^(-?\d+\.?\d*)::(.+?)(?:::)?$',
    ).firstMatch(text);
    if (weightMatch != null) {
      text = weightMatch.group(2)!.trim();
      return text;
    }

    // 2. 处理结尾的 ::
    if (text.endsWith('::')) {
      text = text.substring(0, text.length - 2).trim();
    }

    return text;
  }

  String get _displayText {
    final displayTag = widget.tag.length > 40
        ? '${widget.tag.substring(0, 40)}...'
        : widget.tag;
    if (_translation?.isNotEmpty == true) {
      return '$displayTag ($_translation)';
    }
    return displayTag;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = widget.isFixed
        ? colorScheme.tertiary
        : widget.isCharacter
        ? colorScheme.secondary
        : widget.isNegative
        ? colorScheme.error
        : colorScheme.onSurfaceVariant;
    final isCategorized = widget.isFixed || widget.isCharacter;
    final picked = widget.picked ?? false;
    final bgColor = picked
        ? colorScheme.primaryContainer
        : isCategorized
        ? accent.withValues(alpha: _isHovered ? 0.20 : 0.12)
        : colorScheme.surfaceContainerHighest.withValues(
            alpha: _isHovered ? 0.85 : 0.60,
          );
    final textColor = picked
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurface;

    final chip = MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: context.interactionPolicy.minimumControlExtent,
          ),
          child: AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 150),
            // The ring is always there, clear unless picked, so picking
            // never changes the chip's size.
            padding: const EdgeInsets.symmetric(horizontal: 6.5, vertical: 2.5),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: picked ? colorScheme.primary : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.isFixed || widget.isCharacter) ...[
                  Icon(
                    widget.isFixed ? Icons.push_pin : Icons.person_outline,
                    size: 11,
                    color: picked ? textColor : accent,
                  ),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    _displayText,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      color: textColor,
                      fontWeight: isCategorized
                          ? FontWeight.w600
                          : FontWeight.w500,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final pickState = widget.picked;
    return pickState == null
        ? chip
        : Semantics(selected: pickState, child: chip);
  }
}

/// 角色提示词卡片组件
class CharacterPromptCard extends StatelessWidget {
  final int index;
  final String prompt;
  final String? negativePrompt;
  final String? position;
  final VoidCallback? onCopy;

  const CharacterPromptCard({
    super.key,
    required this.index,
    required this.prompt,
    this.negativePrompt,
    this.position,
    this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context, colorScheme, theme),
          const SizedBox(height: 8),
          SelectionCopyShortcuts(
            child: TranslatedPromptText(
              prompt,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                height: 1.5,
              ),
            ),
          ),
          if (negativePrompt?.isNotEmpty == true)
            _buildNegativePrompt(context, theme, colorScheme),
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            context.l10n.character_number(index + 1),
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (position?.isNotEmpty == true) ...[
          const SizedBox(width: 8),
          Icon(
            Icons.location_on_outlined,
            size: 12,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 2),
          Text(
            position!,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const Spacer(),
        IconButton(
          onPressed: () {
            final textToCopy = negativePrompt?.isNotEmpty == true
                ? '${context.l10n.prompt_positivePrompt}: $prompt\n'
                      '${context.l10n.prompt_negativePrompt}: $negativePrompt'
                : prompt;
            Clipboard.setData(ClipboardData(text: textToCopy));
            AppToast.success(context, context.l10n.toast_characterPromptCopied);
            onCopy?.call();
          },
          icon: Icon(Icons.copy, size: 16, color: colorScheme.onSurfaceVariant),
          tooltip: context.l10n.detail_copyCharacterPrompt,
          style: IconButton.styleFrom(
            padding: const EdgeInsets.all(4),
            minimumSize: Size.square(
              context.interactionPolicy.minimumControlExtent,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNegativePrompt(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Divider(color: colorScheme.outline.withValues(alpha: 0.2), height: 1),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: colorScheme.errorContainer.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.block_outlined,
                    size: 13,
                    color: colorScheme.error,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '${context.l10n.prompt_negativePrompt}:',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              SelectionCopyShortcuts(
                child: TranslatedPromptText(
                  negativePrompt!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    height: 1.55,
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 角色提示词分组组件
class CharacterPromptSection extends StatelessWidget {
  final String title;
  final List<({String prompt, String? negativePrompt, String? position})>
  characters;
  final bool initiallyExpanded;

  const CharacterPromptSection({
    super.key,
    required this.title,
    required this.characters,
    this.initiallyExpanded = true,
  });

  @override
  Widget build(BuildContext context) {
    return PromptSection(
      title: title,
      icon: Icons.people_outline,
      content: characters.map((c) => c.prompt).join(', '),
      initiallyExpanded: initiallyExpanded,
    );
  }
}
