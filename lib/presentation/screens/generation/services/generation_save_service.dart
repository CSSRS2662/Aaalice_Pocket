import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/system_album.dart';
import '../../../../core/utils/localization_extension.dart';
import '../../../../core/utils/image_save_utils.dart';
import '../../../../data/models/gallery/nai_image_metadata.dart';
import '../../../../data/services/image_metadata_service.dart';
import '../../../providers/image_generation_provider.dart';
import '../../../utils/image_detail_opener.dart';
import '../../../providers/system_album_provider.dart';
import '../../../widgets/common/album_save_feedback.dart';
import '../../../widgets/common/app_toast.dart';
import '../../../widgets/common/duplicate_save_notice.dart';
import '../../../widgets/common/image_detail/file_image_detail_data.dart';
import '../../../widgets/common/image_detail/image_detail_data.dart';
import '../../../widgets/common/image_detail/image_detail_viewer.dart';
import 'generated_image_favorite.dart';

/// 图像保存服务类
///
/// 负责处理图像保存、全屏预览等功能
/// 从 desktop_layout.dart 中提取，减少文件职责
class GenerationSaveService {
  GenerationSaveService._();

  /// 显示全屏预览
  ///
  /// 简化逻辑：统一使用 FileImageDetailData 从 PNG 文件解析元数据
  /// - 如果图像已保存（有 filePath），直接使用
  /// - 如果图像未保存，先保存到磁盘再使用
  /// - 元数据异步加载，详情页先显示，解析中显示转圈
  static void showFullscreenPreview(
    BuildContext context,
    WidgetRef ref,
    List<GeneratedImage> images,
  ) {
    // 立即构建基础数据（使用 FileImageDetailData 从文件解析）
    final allImages = images.map((img) {
      // 如果图像已保存，直接使用 filePath
      // 如果未保存，使用临时字节（这种情况在 auto-save 开启时应该很少）
      if (img.filePath != null && img.filePath!.isNotEmpty) {
        // 加入预加载队列（如果尚未解析）
        ImageMetadataService().enqueuePreload(
          taskId: img.id,
          filePath: img.filePath,
        );
        return FileImageDetailData(
          filePath: img.filePath!,
          cachedBytes: img.bytes,
          id: img.id,
          initialMetadata: img.metadata,
          showCopyButton: img.canSave,
        );
      }

      // 未保存的图像：使用 GeneratedImageDetailData 作为 fallback
      // 这种情况只应在 auto-save 关闭且用户未手动保存时发生
      return GeneratedImageDetailData(
        imageBytes: img.bytes,
        metadata: img.metadata,
        id: img.id,
        showSaveButton: img.canSave,
        showCopyButton: img.canSave,
        preserveOriginalBytesOnSave: img.preserveOriginalBytesOnSave,
        fixedTagUsageSnapshot: img.fixedTagUsageSnapshot,
      );
    }).toList();
    GeneratedImage? sourceForDetail(ImageDetailData detail) =>
        images.cast<GeneratedImage?>().firstWhere(
          (image) => image?.id == detail.identifier,
          orElse: () => null,
        );

    // 使用 ImageDetailOpener 打开详情页（带防重复点击）
    // 使用 'generation_desktop' key 避免与本地图库的 'default' key 冲突
    ImageDetailOpener.showMultipleImmediate(
      context,
      images: allImages,
      initialIndex: 0,
      showMetadataPanel: true,
      showThumbnails: allImages.length > 1,
      callbacks: ImageDetailCallbacks(
        onSave: (image) async {
          await saveImageFromDetail(context, ref, image);
        },
        onReuseSeed: (detail) async {
          final image = sourceForDetail(detail);
          final seed = image?.metadata?.seed;
          if (seed == null) {
            if (context.mounted) {
              AppToast.warning(context, context.l10n.toast_imageHasNoMetadata);
            }
            return;
          }
          ref.read(generationParamsNotifierProvider.notifier).updateSeed(seed);
        },
        onFavoriteToggle: (detail) {
          final image = sourceForDetail(detail);
          if (image != null) {
            unawaited(toggleGeneratedImageFavorite(context, ref, image));
          }
        },
      ),
    );
  }

  /// 从详情页保存图像
  ///
  /// 保存只进系统相册，并用 [ImageSaveUtils] 确保元数据完整嵌入。相册里已有
  /// 这张图时不保存，底部通知提供“依然保存”。
  static Future<void> saveImageFromDetail(
    BuildContext context,
    WidgetRef ref,
    ImageDetailData image,
  ) => _saveFromDetail(
    context,
    // 详情页可能在保存期间关闭，句柄在第一个 await 之前取好。
    ref.read(systemAlbumProvider),
    image,
    allowDuplicate: false,
  );

  static Future<void> _saveFromDetail(
    BuildContext context,
    SystemAlbum album,
    ImageDetailData image, {
    required bool allowDuplicate,
  }) async {
    try {
      final imageBytes = await image.getImageBytes();

      // 获取已有元数据（如果图像已包含）
      final existingMetadata = image.metadata;
      final fixedTagUsageSnapshot = image is GeneratedImageDetailData
          ? image.fixedTagUsageSnapshot
          : existingMetadata?.fixedTagUsageSnapshot;
      final bytes = await ImageSaveUtils.resultBytesForSave(
        imageBytes: imageBytes,
        preserveOriginalBytes: image.preserveOriginalBytesOnSave,
        fixedTagUsageSnapshot: fixedTagUsageSnapshot,
        rebuild: () async => existingMetadata == null
            ? imageBytes
            : ImageSaveUtils.buildPrebuiltMetadataBytes(
                imageBytes: imageBytes,
                metadata: {
                  'Description': existingMetadata.prompt,
                  'Software': 'NovelAI',
                  'Source': existingMetadata.source ?? 'NovelAI Diffusion',
                  'Comment': jsonEncode(
                    buildCommentJsonFromMetadata(existingMetadata),
                  ),
                },
              ),
      );
      final saved = await album.save(
        bytes: bytes,
        identity: imageBytes,
        fileName: ImageSaveUtils.albumFileName(
          seed: await ImageSaveUtils.resolveSeed(
            metadata: existingMetadata,
            bytes: imageBytes,
          ),
        ),
        source: 'detail-save',
        allowDuplicate: allowDuplicate,
      );
      if (!context.mounted) return;
      if (saved.duplicate) {
        showDuplicateSaveNotice(
          context,
          onSaveAnyway: () =>
              _saveFromDetail(context, album, image, allowDuplicate: true),
        );
        return;
      }
      showAlbumSaved(context, album, saved.location);
    } catch (e) {
      if (context.mounted) {
        AppToast.error(context, context.l10n.image_saveFailed(e.toString()));
      }
    }
  }

  /// 从元数据构建 Comment JSON
  static Map<String, dynamic> buildCommentJsonFromMetadata(
    NaiImageMetadata metadata,
  ) {
    final commentJson = <String, dynamic>{
      'prompt': metadata.prompt,
      'uc': metadata.negativePrompt,
      'seed': metadata.seed ?? -1,
      'steps': metadata.steps ?? 28,
      'width': metadata.width ?? 832,
      'height': metadata.height ?? 1216,
      'scale': metadata.scale ?? 5.0,
      'uncond_scale': 0.0,
      'cfg_rescale': metadata.cfgRescale ?? 0.0,
      'n_samples': 1,
      'noise_schedule': metadata.noiseSchedule ?? 'native',
      'sampler': metadata.sampler ?? 'k_euler_ancestral',
      'sm': metadata.smea ?? false,
      'sm_dyn': metadata.smeaDyn ?? false,
    };

    // 添加 Vibe 数据
    if (metadata.vibeReferences.isNotEmpty) {
      commentJson['reference_image_multiple'] = metadata.vibeReferences
          .where((v) => v.vibeEncoding.isNotEmpty)
          .map((v) => v.vibeEncoding)
          .toList();
      commentJson['reference_strength_multiple'] = metadata.vibeReferences
          .map((v) => v.strength)
          .toList();
      commentJson['reference_information_extracted_multiple'] = metadata
          .vibeReferences
          .map((v) => v.infoExtracted)
          .toList();
    }

    return commentJson;
  }
}
