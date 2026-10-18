import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../../core/platform/platform_capabilities.dart';
import '../../../../core/services/file_export_service.dart';
import '../../../../core/services/system_album.dart';
import '../../../../core/utils/image_save_utils.dart';
import '../../../../core/utils/localization_extension.dart';
import '../../../../core/utils/zip_utils.dart';
import '../../../providers/generation/image_card_selection_provider.dart';
import '../../../providers/image_generation_provider.dart';
import '../../../utils/zip_export_progress.dart';
import '../../../widgets/common/album_save_feedback.dart';
import '../../../widgets/common/app_toast.dart';
import '../../../widgets/common/duplicate_save_notice.dart';
import '../../../widgets/common/image_card_action.dart';
import 'generation_image_deletion.dart';

class GenerationImageBatchActions {
  GenerationImageBatchActions({
    required this.context,
    required this.images,
    required this.album,
    required this.selection,
    required this.deletion,
  });
  final BuildContext context;
  final List<GeneratedImage> images;

  /// Where saving puts the images; the gallery holds favorites only.
  final SystemAlbum album;
  final GenerationImageCardSelection selection;
  final GenerationImageDeletion deletion;

  List<ImageCardAction> build() => [
    ImageCardAction(
      id: ImageCardActionId.export,
      icon: Icons.archive_outlined,
      label: context.l10n.common_pack,
      supportsBatch: true,
      invoke: _packSelectedImages,
    ),
    ImageCardAction(
      id: ImageCardActionId.save,
      icon: Icons.save_alt,
      label: context.l10n.image_save,
      supportsBatch: true,
      isPrimary: true,
      invoke: _saveSelectedImages,
    ),
    ImageCardAction(
      id: ImageCardActionId.delete,
      icon: Icons.delete_outline,
      label: context.l10n.common_delete,
      supportsBatch: true,
      isDanger: true,
      invoke: () => deletion.confirmAndDelete(images),
    ),
  ];
  Future<void> _saveSelectedImages() => _saveImages(images);

  /// 保存只进系统相册；相册里已有的图不保存，底部通知提供“依然保存”，
  /// 只重存这些图。
  Future<void> _saveImages(
    List<GeneratedImage> targets, {
    bool allowDuplicate = false,
  }) async {
    if (targets.isEmpty) return;

    try {
      final duplicates = <GeneratedImage>[];
      String? location;
      for (final image in targets) {
        final saved = await album.save(
          bytes: image.bytes,
          fileName: ImageSaveUtils.albumFileName(
            seed: await ImageSaveUtils.resolveSeed(
              metadata: image.metadata,
              bytes: image.bytes,
            ),
          ),
          source: 'batch-save',
          allowDuplicate: allowDuplicate,
        );
        if (saved.duplicate) {
          duplicates.add(image);
        } else {
          location = saved.location;
        }
      }

      if (!context.mounted) return;
      if (location != null) showAlbumSaved(context, album, location);
      if (duplicates.isNotEmpty) {
        showDuplicateSaveNotice(
          context,
          count: duplicates.length,
          onSaveAnyway: () => _saveImages(duplicates, allowDuplicate: true),
        );
      }
      selection.deselectAll(targets.map((image) => image.id));
    } catch (e) {
      if (context.mounted) {
        AppToast.error(context, context.l10n.image_saveFailed(e.toString()));
      }
    }
  }

  /// 打包选中的图片成压缩包
  Future<void> _packSelectedImages() async {
    if (images.isEmpty) return;

    final defaultName = 'images_${DateTime.now().millisecondsSinceEpoch}';
    final fileName = '$defaultName.zip';
    String? desktopOutputPath;
    if (!PlatformCapabilities.current.supportsDocumentFileExport) {
      final outputPath = await FilePicker.platform.saveFile(
        dialogTitle: context.l10n.localGallery_saveZipArchive,
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );
      if (outputPath == null || !context.mounted) return;
      desktopOutputPath = outputPath.endsWith('.zip')
          ? outputPath
          : '$outputPath.zip';
    }

    final progress = ZipExportProgress(context, images.length);

    Directory? tempDir;
    try {
      // 先将选中的图片保存到临时目录
      tempDir = await Directory.systemTemp.createTemp('nai_pack_');
      final imagePaths = <String>[];

      final selectedImages = images;

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      for (int i = 0; i < selectedImages.length; i++) {
        final imageFileName = 'NAI_${timestamp}_${i + 1}.png';
        final file = File('${tempDir.path}/$imageFileName');
        await file.writeAsBytes(selectedImages[i].bytes);
        imagePaths.add(file.path);
      }

      late ZipCreationResult result;
      String? savedLocation;
      if (PlatformCapabilities.current.supportsDocumentFileExport) {
        savedLocation = await FileExportService.withTemporaryOutput(
          fileName: fileName,
          action: (temporaryPath) async {
            result = await ZipUtils.createZipFromImagesDetailed(
              imagePaths,
              temporaryPath,
              onProgress: progress.update,
            );
            if (!result.succeeded || !context.mounted) return null;
            return FileExportService.saveFileFromPath(
              sourcePath: temporaryPath,
              fileName: fileName,
              dialogTitle: context.l10n.localGallery_saveZipArchive,
              mimeType: 'application/zip',
              allowedExtensions: const ['zip'],
            );
          },
        );
      } else {
        result = await ZipUtils.createZipFromImagesDetailed(
          imagePaths,
          desktopOutputPath!,
          onProgress: progress.update,
        );
        savedLocation = desktopOutputPath;
      }

      if (context.mounted) {
        if (result.succeeded && savedLocation != null) {
          if (result.isPartial) {
            progress.controller.dismiss();
            AppToast.warning(
              context,
              context.l10n.localGallery_packedImagesWithFailures(
                result.exportedCount,
                result.failures.length,
              ),
            );
          } else {
            progress.controller.complete(
              message: context.l10n.localGallery_packedImages(
                result.exportedCount,
              ),
            );
          }
          if (!result.isPartial) {
            selection.deselectAll(images.map((image) => image.id));
          }
        } else if (!result.succeeded) {
          progress.controller.fail(
            message: context.l10n.localGallery_packFailedWithDetails(
              result.error ?? context.l10n.localGallery_packFailed,
            ),
          );
        } else {
          progress.controller.dismiss();
        }
      } else {
        progress.controller.dismiss();
      }
    } catch (e) {
      progress.controller.dismiss();
      if (context.mounted) {
        AppToast.error(
          context,
          context.l10n.toast_packFailedWithError(e.toString()),
        );
      }
    } finally {
      if (tempDir != null && await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  }
}
