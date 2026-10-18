import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/file_explorer_utils.dart';
import '../../../../core/utils/image_save_utils.dart';
import '../../../../core/utils/localization_extension.dart';
import '../../../providers/image_generation_provider.dart';
import '../../../providers/system_album_provider.dart';
import '../../../widgets/common/album_save_feedback.dart';
import '../../../widgets/common/app_toast.dart';

/// 在文件夹中定位生成结果（桌面端）。收藏过的定位图库里的文件；没收藏的先
/// 存进保存文件夹再定位，不会为此往只放收藏的图库里写文件。
Future<void> revealGeneratedImage(
  BuildContext context,
  WidgetRef ref,
  GeneratedImage image,
) async {
  final l10n = context.l10n;
  final album = ref.read(systemAlbumProvider);
  // 卡片持有的是构建时的快照，收藏可能已在之后写入路径。
  final current =
      ref.read(imageGenerationNotifierProvider).findImageById(image.id) ??
      image;
  try {
    final linked = current.filePath;
    if (linked != null && linked.isNotEmpty && await File(linked).exists()) {
      await FileExplorerUtils.revealFile(linked);
      return;
    }
    final saved = await album.save(
      bytes: current.bytes,
      fileName: ImageSaveUtils.albumFileName(
        seed: await ImageSaveUtils.resolveSeed(
          metadata: current.metadata,
          bytes: current.bytes,
        ),
      ),
      source: 'reveal',
    );
    if (!album.target.isPhotoAlbum) {
      await FileExplorerUtils.revealFile(saved.location);
    }
    if (!saved.duplicate && context.mounted) {
      showAlbumSaved(context, album, saved.location);
    }
  } catch (e) {
    if (context.mounted) AppToast.error(context, l10n.image_saveFailed('$e'));
  }
}
