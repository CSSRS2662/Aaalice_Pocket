import 'dart:io';

import '../../../../core/utils/image_save_utils.dart';
import '../../../../data/repositories/gallery_folder_repository.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../providers/image_generation_provider.dart';
import '../../../providers/local_gallery_provider.dart';
import '../../../utils/prompt_preset_import_utils.dart' show ProviderReader;

/// [newlySavedRoot] 仅在本次新写入文件时给出图库根目录。
typedef LinkedGeneratedImageFile = ({String path, String? newlySavedRoot});

/// 需要一个真实文件的操作（收藏、定位文件夹）共用的保存入口。
///
/// 保存后把路径记回这条生成结果：重复操作复用同一个文件，删除历史时也能连带删除它。
class GeneratedImageFileLink {
  const GeneratedImageFileLink._();

  static Future<LinkedGeneratedImageFile> ensureSaved(
    ProviderReader read,
    GeneratedImage image,
    AppLocalizations l10n,
  ) {
    // 保存期间卡片可能被卸载，句柄必须在第一个 await 之前取好。
    final generation = read(imageGenerationNotifierProvider.notifier);
    final gallery = read(localGalleryNotifierProvider.notifier);
    // 自动保存还在写这张图时先等它写完，再沿用它的文件。
    return generation.queueImageSave(
      image.id,
      () => _linkOrSave(generation, gallery, image, l10n),
    );
  }

  static Future<LinkedGeneratedImageFile> _linkOrSave(
    ImageGenerationNotifier generation,
    LocalGalleryNotifier gallery,
    GeneratedImage image,
    AppLocalizations l10n,
  ) async {
    // 卡片持有的是构建时的快照，自动保存可能已在之后写入路径。
    final current = generation.findImageById(image.id) ?? image;
    final existingPath = current.filePath;
    if (existingPath != null &&
        existingPath.isNotEmpty &&
        await File(existingPath).exists()) {
      return (path: existingPath, newlySavedRoot: null);
    }

    final rootPath = await GalleryFolderRepository.instance.getRootPath();
    if (rootPath == null || rootPath.isEmpty) {
      throw StateError(l10n.localGallery_saveDirectoryNotSet);
    }

    // 这份文件之后就是这张图唯一的副本，与自动保存一样记下固定词使用记录。
    final saved = await ImageSaveUtils.saveResultImage(
      rootPath: rootPath,
      imageBytes: current.bytes,
      preserveOriginalBytes: current.preserveOriginalBytesOnSave,
      source: 'file-link',
      fixedTagUsageSnapshot: current.fixedTagUsageSnapshot,
      // 这里拿不到生成参数，缺元数据的字节只能原样保存。
      rebuild: () async => current.bytes,
      seed: await ImageSaveUtils.resolveSeed(
        metadata: current.metadata,
        bytes: current.bytes,
      ),
    );
    final filePath = saved.path;
    generation.updateImageFilePath(current.id, filePath);
    await gallery.addNewlySavedImages([filePath]);
    return (path: filePath, newlySavedRoot: rootPath);
  }
}
