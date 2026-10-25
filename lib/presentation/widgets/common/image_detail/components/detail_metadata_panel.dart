import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../../../core/utils/app_logger.dart';
import '../../../../../core/utils/localization_extension.dart';
import '../../../../../core/utils/nai_prompt_parser.dart';
import '../../../../../core/utils/nai_resolution_adapter.dart';
import '../../../../../data/models/fixed_tag/fixed_tag_entry.dart';
import '../../../../../data/models/gallery/nai_image_metadata.dart';
import '../../../../../data/models/vibe/vibe_reference.dart';
import '../../../../providers/fixed_tags_provider.dart';
import '../../../../utils/fixed_tag_metadata_matcher.dart';
import '../../add_to_library_dialog.dart';
import '../../app_toast.dart';
import '../../save_vibe_dialog.dart';
import '../../themed_divider.dart';
import '../../model_family_icon.dart';
import '../file_image_detail_data.dart';
import '../image_detail_data.dart';
import 'detail_action_buttons.dart';
import 'detail_tag_pick_bar.dart';
import 'detail_tag_picks.dart';
import 'prompt_copy_dialog.dart';
import 'prompt_section.dart';
import 'selection_copy_shortcuts.dart';
import 'vibe_section.dart';

/// 元数据面板组件
///
/// 用于在全屏预览器右侧显示完整的图片元数据信息
/// 支持折叠/展开功能
class DetailMetadataPanel extends ConsumerStatefulWidget {
  /// 当前显示的图片数据
  final ImageDetailData? currentImage;

  /// 是否默认展开
  final bool initialExpanded;

  /// 面板宽度
  final double expandedWidth;

  /// 折叠宽度
  final double collapsedWidth;

  /// 嵌入移动端面板时由外层提供标题和关闭入口，不再显示折叠控件。
  final bool collapsible;

  /// 宽度由外层分栏约束直接驱动，不在面板内部执行宽度补间。
  final bool fillAvailableWidth;

  const DetailMetadataPanel({
    super.key,
    this.currentImage,
    this.initialExpanded = true,
    this.expandedWidth = 320,
    this.collapsedWidth = 40,
    this.collapsible = true,
    this.fillAvailableWidth = false,
  }) : assert(!fillAvailableWidth || !collapsible);

  @override
  ConsumerState<DetailMetadataPanel> createState() =>
      _DetailMetadataPanelState();
}

class _DetailMetadataPanelState extends ConsumerState<DetailMetadataPanel> {
  late bool _isExpanded;
  Future<NaiImageMetadata?>? _metadataFuture;
  NaiImageMetadata? _loadedMetadata;
  (int, int)? _actualImageSize;
  FileInfo? _fileInfo;
  final _tagPicks = DetailTagPicks();

  /// Holds focus while tags are picked, so Esc leaves picking before it
  /// reaches the viewer.
  final _pickFocus = FocusNode(
    debugLabel: 'detail-tag-picks',
    skipTraversal: true,
  );

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initialExpanded;
    _tagPicks.addListener(_onTagPicksChanged);
    _startMetadataLoading();
  }

  @override
  void didUpdateWidget(covariant DetailMetadataPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当图片变化时重新加载元数据
    if (widget.currentImage?.identifier != oldWidget.currentImage?.identifier) {
      _tagPicks.end();
      _startMetadataLoading();
    }
  }

  @override
  void dispose() {
    _tagPicks
      ..removeListener(_onTagPicksChanged)
      ..dispose();
    _pickFocus.dispose();
    super.dispose();
  }

  void _onTagPicksChanged() {
    if (_tagPicks.active) {
      if (!_pickFocus.hasFocus) _pickFocus.requestFocus();
    } else if (_pickFocus.hasFocus) {
      _pickFocus.unfocus(
        disposition: UnfocusDisposition.previouslyFocusedChild,
      );
    }
  }

  KeyEventResult _handlePickKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape ||
        !_tagPicks.active) {
      return KeyEventResult.ignored;
    }
    _tagPicks.end();
    return KeyEventResult.handled;
  }

  Future<void> _copyPickedTags() async {
    final count = _tagPicks.count;
    final text = _tagPicks.text;
    if (count == 0 || text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    _tagPicks.end();
    AppToast.success(context, context.l10n.detail_pickedTagsCopied(count));
  }

  /// 启动元数据加载（双通道架构）
  ///
  /// **前台高优先级通道**：
  /// - 用户主动打开详情页时触发
  /// - 立即开始解析，不受后台预加载队列影响
  /// - 从后台队列中移除重复任务（避免重复解析）
  ///
  /// **支持的数据源**：
  /// - [FileImageDetailData]: 从 PNG 文件解析（已保存的图像）
  /// - [GeneratedImageDetailData]: 从内存字节解析（未保存的图像）
  void _startMetadataLoading() {
    final image = widget.currentImage;
    if (image == null) {
      _actualImageSize = null;
      _fileInfo = null;
      AppLogger.w(
        '[MetadataFlow] _startMetadataLoading: image is null',
        'DetailMetadataPanel',
      );
      return;
    }

    _actualImageSize = null;
    _fileInfo = image.fileInfo;
    unawaited(_loadActualImageSize(image));
    unawaited(_loadFileInfo(image));

    AppLogger.i(
      '[MetadataFlow] _startMetadataLoading: identifier=${image.identifier}, type=${image.runtimeType}',
      'DetailMetadataPanel',
    );

    // 1. 先检查同步可用的元数据
    final syncMetadata = image.metadata;
    AppLogger.d(
      '[MetadataFlow] syncMetadata check: hasData=${syncMetadata?.hasData}, has prompt="${syncMetadata?.fullPrompt.isNotEmpty == true}"',
      'DetailMetadataPanel',
    );

    if (syncMetadata != null && syncMetadata.hasData) {
      AppLogger.i(
        '[MetadataFlow] Using sync metadata (cache hit)',
        'DetailMetadataPanel',
      );
      _loadedMetadata = syncMetadata;
      _metadataFuture = null;
      return;
    }

    // 2. 异步加载元数据（支持所有数据源）
    AppLogger.i(
      '[MetadataFlow] Cache miss, starting async load...',
      'DetailMetadataPanel',
    );
    Future<NaiImageMetadata?>? future;
    if (image is FileImageDetailData) {
      AppLogger.d(
        '[MetadataFlow] Using FileImageDetailData.getMetadataAsync()',
        'DetailMetadataPanel',
      );
      future = image.getMetadataAsync();
    } else if (image is GeneratedImageDetailData) {
      AppLogger.d(
        '[MetadataFlow] Using GeneratedImageDetailData.getMetadataAsync()',
        'DetailMetadataPanel',
      );
      future = image.getMetadataAsync();
    } else if (image is LocalImageDetailData) {
      AppLogger.d(
        '[MetadataFlow] Using LocalImageDetailData.getMetadataAsync()',
        'DetailMetadataPanel',
      );
      future = image.getMetadataAsync();
    } else {
      AppLogger.w(
        '[MetadataFlow] Unknown image type: ${image.runtimeType}',
        'DetailMetadataPanel',
      );
    }

    if (future != null) {
      _metadataFuture = future
          .then((metadata) {
            AppLogger.i(
              '[MetadataFlow] Async load completed: hasData=${metadata?.hasData}, prompt length=${metadata?.fullPrompt.length ?? 0}',
              'DetailMetadataPanel',
            );
            if (mounted) {
              setState(() => _loadedMetadata = metadata);
            }
            return metadata;
          })
          .catchError((e, stack) {
            AppLogger.e(
              '[MetadataFlow] Async load failed',
              e,
              stack,
              'DetailMetadataPanel',
            );
            throw e;
          });
    } else {
      _metadataFuture = null;
      _loadedMetadata = null;
    }
  }

  Future<void> _loadFileInfo(ImageDetailData image) async {
    if (image is! FileImageDetailData) return;
    final FileInfo info;
    try {
      info = await image.getFileInfoAsync();
    } catch (error) {
      AppLogger.w(
        '[MetadataFlow] Failed to read file info: $error',
        'DetailMetadataPanel',
      );
      return;
    }
    if (!mounted || widget.currentImage?.identifier != image.identifier) return;
    setState(() => _fileInfo = info);
  }

  Future<void> _loadActualImageSize(ImageDetailData image) async {
    try {
      final filePath = switch (image) {
        FileImageDetailData() => image.filePath,
        LocalImageDetailData() => image.record.path,
        _ => null,
      };
      final headerSize = filePath == null
          ? null
          : await _tryReadImageHeaderSize(filePath);
      final size =
          headerSize ??
          NaiResolutionAdapter.readImageSize(await image.getImageBytes());
      if (!mounted || widget.currentImage?.identifier != image.identifier) {
        return;
      }
      setState(() => _actualImageSize = size);
    } catch (error) {
      AppLogger.w(
        '[MetadataFlow] Failed to read encoded image size: $error',
        'DetailMetadataPanel',
      );
    }
  }

  Future<(int, int)?> _tryReadImageHeaderSize(String path) async {
    try {
      return NaiResolutionAdapter.readImageSize(await _readImageHeader(path));
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List> _readImageHeader(String path) async {
    const headerByteLimit = 64 * 1024;
    final handle = await File(path).open();
    try {
      return await handle.read(headerByteLimit);
    } finally {
      await handle.close();
    }
  }

  void _toggleExpanded() {
    setState(() => _isExpanded = !_isExpanded);
  }

  /// 获取当前可用的元数据（同步或已加载的异步）
  NaiImageMetadata? get _currentMetadata =>
      _loadedMetadata ?? widget.currentImage?.metadata;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (widget.fillAvailableWidth) {
      return ClipRRect(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          bottomLeft: Radius.circular(16),
        ),
        child: ColoredBox(
          color: colorScheme.surface.withValues(alpha: 0.96),
          child: _buildExpandedPanel(theme),
        ),
      );
    }

    return AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      width: !widget.collapsible || _isExpanded
          ? widget.expandedWidth
          : widget.collapsedWidth,
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(16),
          bottomLeft: Radius.circular(16),
        ),
      ),
      child: Container(
        // Windows Flutter 在大图预览 + 窗口焦点切换时对 BackdropFilter
        // 合成层存在原生崩溃风险；这里保留半透明面板，避免实时背景模糊。
        color: colorScheme.surface.withValues(alpha: 0.96),
        // 宽度拖拽和折叠动画会让父级短暂保留上一帧约束。这里解除横向
        // 最小约束，再由有限宽度的 SizedBox 决定内容宽度，避免新旧宽度
        // 交叉时生成 minWidth > maxWidth 的非法约束。
        child: OverflowBox(
          minWidth: 0,
          maxWidth: double.infinity,
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: widget.expandedWidth,
            child: !widget.collapsible || _isExpanded
                ? _buildExpandedPanel(theme)
                : _buildCollapsedPanel(theme),
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedPanel(ThemeData theme) {
    final l10n = context.l10n;
    final metadata = _currentMetadata;
    final fixedTagsState = ref.watch(fixedTagsNotifierProvider);
    final isLoading = _metadataFuture != null && _loadedMetadata == null;
    final colorScheme = theme.colorScheme;

    final panel = Column(
      children: [
        if (widget.collapsible) ...[
          _PanelHeader(isExpanded: true, onToggle: _toggleExpanded),
          const ThemedDivider(height: 1),
        ],
        Expanded(
          child: widget.currentImage == null
              ? Center(
                  child: Text(
                    l10n.detail_noImage,
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                )
              : isLoading
              ? _buildLoadingState(theme)
              : metadata != null && metadata.hasData
              ? SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: _MetadataContent(
                    metadata: metadata,
                    positiveFixedTagEntries: fixedTagsState.positiveEntries,
                    negativeFixedTagEntries: fixedTagsState.negativeEntries,
                    fileInfo: _fileInfo,
                    actualImageSize: _actualImageSize,
                    tagPicks: _tagPicks,
                  ),
                )
              : _buildNoMetadataState(theme),
        ),
        // 只在有元数据时显示操作按钮
        if (metadata != null && metadata.hasData)
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ThemedDivider(height: 1),
              ListenableBuilder(
                listenable: _tagPicks,
                builder: (context, _) => _tagPicks.active
                    ? DetailTagPickBar(
                        count: _tagPicks.count,
                        onCopy: _copyPickedTags,
                        onLeave: _tagPicks.end,
                      )
                    : DetailActionButtons(
                        metadata: metadata,
                        onPickTags: _tagPicks.start,
                      ),
              ),
            ],
          ),
      ],
    );

    return Focus(
      focusNode: _pickFocus,
      onKeyEvent: _handlePickKey,
      child: ListenableBuilder(
        listenable: _tagPicks,
        // Back leaves picking before it closes the sheet or the viewer.
        builder: (context, child) => PopScope(
          canPop: !_tagPicks.active,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _tagPicks.end();
          },
          child: child!,
        ),
        child: panel,
      ),
    );
  }

  /// 构建加载状态
  Widget _buildLoadingState(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colorScheme.primary,
              value: MediaQuery.disableAnimationsOf(context) ? 0.72 : null,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            context.l10n.detail_parsingMetadata,
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
          ),
        ],
      ),
    );
  }

  /// 构建无元数据状态
  Widget _buildNoMetadataState(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 48,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    context.l10n.detail_noMetadata,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCollapsedPanel(ThemeData theme) {
    final colorScheme = theme.colorScheme;

    return GestureDetector(
      onTap: _toggleExpanded,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          alignment: Alignment.center,
          child: RotatedBox(
            quarterTurns: 1,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.chevron_left,
                  size: 16,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  context.l10n.detail_metadata,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
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

/// 面板标题栏
class _PanelHeader extends StatelessWidget {
  final bool isExpanded;
  final VoidCallback onToggle;

  const _PanelHeader({required this.isExpanded, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 20, color: colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            context.l10n.detail_imageDetails,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(
              isExpanded ? Icons.chevron_right : Icons.chevron_left,
              size: 20,
            ),
            onPressed: onToggle,
            tooltip: isExpanded
                ? context.l10n.common_collapse
                : context.l10n.common_expand,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

/// 元数据内容
class _MetadataContent extends StatelessWidget {
  final NaiImageMetadata metadata;
  final List<FixedTagEntry> positiveFixedTagEntries;
  final List<FixedTagEntry> negativeFixedTagEntries;
  final FileInfo? fileInfo;
  final (int, int)? actualImageSize;
  final DetailTagPicks? tagPicks;

  const _MetadataContent({
    required this.metadata,
    this.positiveFixedTagEntries = const [],
    this.negativeFixedTagEntries = const [],
    this.fileInfo,
    this.actualImageSize,
    this.tagPicks,
  });

  @override
  Widget build(BuildContext context) {
    final displayModel = metadata.effectiveModel ?? metadata.source;
    final resolution = actualImageSize == null
        ? metadata.sizeString
        : '${actualImageSize!.$1} × ${actualImageSize!.$2}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 基本信息（仅在有文件信息时显示）
        if (fileInfo != null) ...[
          _InfoSection(
            title: context.l10n.detail_basicInfo,
            icon: Icons.insert_drive_file_outlined,
            children: [
              _InfoRow(
                label: context.l10n.detail_fileName,
                value: fileInfo!.fileName,
              ),
              if (fileInfo!.modifiedAt != null)
                _InfoRow(
                  label: context.l10n.detail_modifiedTime,
                  value: _formatTime(context, fileInfo!.modifiedAt!),
                ),
              if (fileInfo!.size != null)
                _InfoRow(
                  label: context.l10n.detail_fileSize,
                  value: _formatSize(fileInfo!.size!),
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        // 生成参数
        _InfoSection(
          title: context.l10n.gallery_generationParams,
          icon: Icons.tune,
          children: [
            if (displayModel?.isNotEmpty == true)
              _InfoRow(
                label: context.l10n.gallery_metaModel,
                value: displayModel!,
                leading: ModelFamilyIcon(modelId: displayModel, size: 16),
              ),
            if (metadata.seed != null)
              _InfoRow(
                label: context.l10n.gallery_metaSeed,
                value: metadata.seed.toString(),
              ),
            if (metadata.steps != null)
              _InfoRow(
                label: context.l10n.gallery_metaSteps,
                value: metadata.steps.toString(),
              ),
            if (metadata.scale != null)
              _InfoRow(
                label: context.l10n.gallery_metaCfgScale,
                value: metadata.scale.toString(),
              ),
            if (metadata.sampler != null)
              _InfoRow(
                label: context.l10n.gallery_metaSampler,
                value: metadata.displaySampler,
              ),
            if (resolution.isNotEmpty)
              _InfoRow(
                label: context.l10n.gallery_metaResolution,
                value: resolution,
              ),
            if (metadata.smea == true || metadata.smeaDyn == true)
              _InfoRow(
                label: context.l10n.gallery_metaSmea,
                value: metadata.smeaDyn == true ? 'DYN' : 'ON',
              ),
            if (metadata.noiseSchedule != null)
              _InfoRow(label: 'Noise', value: metadata.noiseSchedule!),
            if (metadata.cfgRescale != null && metadata.cfgRescale! > 0)
              _InfoRow(
                label: 'CFG Rescale',
                value: metadata.cfgRescale.toString(),
              ),
            if (metadata.qualityToggle == true)
              _InfoRow(
                label: context.l10n.qualityTags_label,
                value: context.l10n.qualityTags_naiDefault,
              ),
          ],
        ),
        const SizedBox(height: 16),
        // 提示词分组展示
        _buildPromptSections(context),
      ],
    );
  }

  Widget _buildPromptSections(BuildContext context) {
    final resolvedMetadata = matchMetadataFixedTags(
      metadata: metadata,
      positiveEntries: positiveFixedTagEntries,
      negativeEntries: negativeFixedTagEntries,
    );
    final fixedTags = [
      ...resolvedMetadata.fixedPrefixTags,
      ...resolvedMetadata.fixedSuffixTags,
    ];
    final fixedNegativeTags = [
      ...resolvedMetadata.fixedNegativePrefixTags,
      ...resolvedMetadata.fixedNegativeSuffixTags,
    ];
    final characterTags = resolvedMetadata.characterInfos
        .expand((character) => _extractTags(character.prompt))
        .toList();
    final characterNegativeTags = resolvedMetadata.characterInfos
        .expand((character) => _extractTags(character.negativePrompt ?? ''))
        .toList();
    final mainPositiveTags = _extractTags(resolvedMetadata.prompt);
    final mainNegativeTags = _extractTags(
      resolvedMetadata.displayNegativePrompt,
    );
    final positiveTags = [...mainPositiveTags, ...characterTags];
    final negativeTags = [...mainNegativeTags, ...characterNegativeTags];
    final fixedPositiveIndexes = fixedPromptTagIndexes(
      promptTags: mainPositiveTags,
      prefixEntries: resolvedMetadata.fixedPrefixTags,
      suffixEntries: resolvedMetadata.fixedSuffixTags,
    );
    final fixedNegativeIndexes = fixedPromptTagIndexes(
      promptTags: mainNegativeTags,
      prefixEntries: resolvedMetadata.fixedNegativePrefixTags,
      suffixEntries: resolvedMetadata.fixedNegativeSuffixTags,
    );
    final characterPositiveIndexes = {
      for (
        var index = mainPositiveTags.length;
        index < positiveTags.length;
        index++
      )
        index,
    };
    final characterNegativeIndexes = {
      for (
        var index = mainNegativeTags.length;
        index < negativeTags.length;
        index++
      )
        index,
    };
    final positivePrompt = positiveTags.join(', ');
    final negativePrompt = negativeTags.join(', ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PromptSection(
          title: context.l10n.prompt_positivePrompt,
          icon: Icons.add_circle_outline,
          content: positivePrompt,
          tags: positiveTags,
          initiallyExpanded: true,
          showAddToLibrary: positivePrompt.isNotEmpty,
          onAddToLibrary: () =>
              _showAddToLibraryDialog(context, positivePrompt),
          onCopy: () => _copyPositivePrompt(context, resolvedMetadata),
          fixedTags: fixedTags,
          characterTags: characterTags,
          fixedTagIndexes: fixedPositiveIndexes,
          characterTagIndexes: characterPositiveIndexes,
          tagPicks: tagPicks,
          pickSide: DetailTagSide.positive,
        ),
        if (negativePrompt.isNotEmpty) ...[
          const SizedBox(height: 12),
          PromptSection(
            title: context.l10n.prompt_negativePrompt,
            icon: Icons.remove_circle_outline,
            content: negativePrompt,
            tags: negativeTags,
            initiallyExpanded: false,
            showAddToLibrary: true,
            onAddToLibrary: () =>
                _showAddToLibraryDialog(context, negativePrompt),
            fixedTags: fixedNegativeTags,
            characterTags: characterNegativeTags,
            fixedTagIndexes: fixedNegativeIndexes,
            characterTagIndexes: characterNegativeIndexes,
            isNegative: true,
            tagPicks: tagPicks,
            pickSide: DetailTagSide.negative,
          ),
        ],
        if (metadata.vibeReferences.isNotEmpty) ...[
          const SizedBox(height: 12),
          VibeSection(
            vibes: metadata.vibeReferences,
            initiallyExpanded: true,
            onSaveToLibrary: (vibe) => _showSaveVibeDialog(context, vibe),
          ),
        ],
      ],
    );
  }

  /// 从提示词文本提取标签列表
  List<String> _extractTags(String prompt) {
    if (prompt.isEmpty) return [];
    return NaiPromptParser.splitSegments(prompt);
  }

  Future<void> _copyPositivePrompt(
    BuildContext context,
    NaiImageMetadata sourceMetadata,
  ) async {
    final prompt = await PromptCopyDialog.show(
      context,
      metadata: sourceMetadata,
    );
    if (prompt == null || !context.mounted) return;

    await Clipboard.setData(ClipboardData(text: prompt));
    if (context.mounted) {
      AppToast.success(context, context.l10n.gallery_promptCopied);
    }
  }

  /// 显示添加到词库对话框
  Future<void> _showAddToLibraryDialog(
    BuildContext context,
    String content,
  ) async {
    await AddToLibraryDialog.show(
      context,
      content: content,
      sourceTag: 'from_image',
    );
  }

  /// 显示保存 Vibe 对话框
  Future<void> _showSaveVibeDialog(
    BuildContext context,
    VibeReference vibe,
  ) async {
    await SaveVibeDialog.show(
      context,
      vibe: vibe,
      defaultName: vibe.displayName,
    );
  }

  String _formatTime(BuildContext context, DateTime time) {
    final locale = context.timeagoLocaleCode;
    return '${timeago.format(time, locale: locale)} (${time.toString().substring(0, 16)})';
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}

/// 信息区块
class _InfoSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _InfoSection({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 过滤掉空内容
    final validChildren = children
        .whereType<_InfoRow>()
        .where((row) => row.value.isNotEmpty)
        .toList();
    if (validChildren.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: colorScheme.primary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: validChildren
                .map(
                  (child) => Padding(
                    padding: EdgeInsets.only(
                      bottom: child != validChildren.last ? 8 : 0,
                    ),
                    child: child,
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }
}

/// 信息行
class _InfoRow extends StatelessWidget {
  static const _minimumSideBySideWidth = 220.0;

  final String label;
  final String value;
  final Widget? leading;

  const _InfoRow({required this.label, required this.value, this.leading});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final labelWidget = Text(
      label,
      style: theme.textTheme.bodySmall?.copyWith(
        color: colorScheme.onSurfaceVariant,
        fontSize: 11,
      ),
    );
    final selectableValue = SelectionCopyShortcuts(
      child: SelectableText(
        value,
        style: theme.textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w500,
          fontSize: 11,
        ),
      ),
    );
    final valueWidget = leading == null
        ? selectableValue
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              leading!,
              const SizedBox(width: 6),
              Flexible(child: selectableValue),
            ],
          );

    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < _minimumSideBySideWidth ||
            MediaQuery.textScalerOf(context).scale(1) >= 1.5;
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [labelWidget, const SizedBox(height: 2), valueWidget],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 70, child: labelWidget),
            const SizedBox(width: 4),
            Flexible(child: valueWidget),
          ],
        );
      },
    );
  }
}
