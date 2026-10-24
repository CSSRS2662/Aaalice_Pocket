import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../../core/utils/thumbnail_image_normalizer.dart';
import '../../../widgets/common/app_toast.dart';
import 'thumbnail_gallery_picker_dialog.dart';

/// Where a new preview image comes from.
enum TagLibraryThumbnailSource { device, appGallery }

/// Picking preview images and keeping their files in the app's thumbnail
/// folder, shared by the entry editor and the entry details.
abstract final class TagLibraryThumbnailStore {
  static const folderName = 'tag_library_thumbnails';

  static Future<Directory> directory() async {
    final appDir = await getApplicationDocumentsDirectory();
    return Directory(path.join(appDir.path, folderName));
  }

  /// Asks whether to pick from the device or the app's gallery.
  static Future<TagLibraryThumbnailSource?> pickSource(BuildContext context) {
    return showModalBottomSheet<TagLibraryThumbnailSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(sheetContext.l10n.tagLibrary_selectFromDevice),
              onTap: () =>
                  Navigator.pop(sheetContext, TagLibraryThumbnailSource.device),
            ),
            ListTile(
              leading: const Icon(Icons.collections_outlined),
              title: Text(sheetContext.l10n.tagLibrary_selectFromAppGallery),
              subtitle: Text(sheetContext.l10n.tagLibrary_appGallerySourceHint),
              onTap: () => Navigator.pop(
                sheetContext,
                TagLibraryThumbnailSource.appGallery,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The bytes of an image picked from [source], or null when cancelled or
  /// unreadable; failures are shown as a toast.
  static Future<Uint8List?> readImage(
    BuildContext context,
    TagLibraryThumbnailSource source,
  ) async {
    try {
      switch (source) {
        case TagLibraryThumbnailSource.device:
          final result = await FilePicker.platform.pickFiles(
            type: FileType.custom,
            allowedExtensions: supportedThumbnailImageExtensions,
            allowMultiple: false,
          );
          if (result == null) return null;
          final selected = result.files.single;
          final bytes =
              selected.bytes ??
              (selected.path == null
                  ? null
                  : await File(selected.path!).readAsBytes());
          if (bytes == null) {
            throw const FileSystemException('无法读取所选图像');
          }
          return bytes;
        case TagLibraryThumbnailSource.appGallery:
          final selectedPath = await ThumbnailGalleryPickerDialog.show(context);
          if (selectedPath == null) return null;
          final file = File(selectedPath);
          if (!await file.exists()) {
            throw const FileSystemException('所选图库图片不存在');
          }
          return await file.readAsBytes();
      }
    } catch (error) {
      if (context.mounted) {
        AppToast.error(
          context,
          context.l10n.imagePicker_fileSelectionFailed(error.toString()),
        );
      }
      return null;
    }
  }

  /// Saves [bytes] as a PNG in the thumbnail folder and returns its path.
  /// Converting first lets formats like TIFF or TGA preview everywhere.
  static Future<String> saveImage(Uint8List bytes) async {
    final normalized = await compute(normalizeThumbnailImageToPng, bytes);
    final folder = await directory();
    await folder.create(recursive: true);
    final file = File(path.join(folder.path, '${const Uuid().v4()}.png'));
    await file.writeAsBytes(normalized);
    return file.path;
  }

  /// [thumbnailPath] copied into the thumbnail folder when it lives
  /// elsewhere; null when there is no file.
  static Future<String?> ensureOwned(String? thumbnailPath) async {
    if (thumbnailPath == null || thumbnailPath.isEmpty) return null;
    final folder = await directory();
    if (thumbnailPath.startsWith(folder.path)) return thumbnailPath;
    final source = File(thumbnailPath);
    if (!await source.exists()) return null;
    await folder.create(recursive: true);
    final copy = path.join(
      folder.path,
      '${const Uuid().v4()}${path.extension(thumbnailPath)}',
    );
    await source.copy(copy);
    return copy;
  }

  /// Deletes [thumbnailPath] when it is one of ours; files elsewhere are
  /// never touched. Failures are ignored, a stray file is harmless.
  static Future<void> deleteOwned(String? thumbnailPath) async {
    if (thumbnailPath == null || thumbnailPath.isEmpty) return;
    try {
      final folder = await directory();
      if (!thumbnailPath.startsWith(folder.path)) return;
      final file = File(thumbnailPath);
      if (await file.exists()) await file.delete();
    } catch (error) {
      debugPrint('删除旧缩略图失败: $error');
    }
  }
}
