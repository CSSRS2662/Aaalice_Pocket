import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../providers/image_generation_provider.dart';
import '../../../widgets/common/app_toast.dart';
import '../../../widgets/common/themed_confirm_dialog.dart';

/// 只在本次运行内有效，不持久化，也不参与云同步。
final generationImageDeleteConfirmSkippedProvider = StateProvider<bool>(
  (ref) => false,
);

/// 删除生成结果的交互入口：确认与结果提示；状态变更由 notifier 完成。
///
/// 只移除生成结果本身，收藏进图库的文件和系统相册里的图都保留。
class GenerationImageDeletion {
  const GenerationImageDeletion({required this.context, required this.ref});

  final BuildContext context;
  final WidgetRef ref;

  Future<void> confirmAndDelete(List<GeneratedImage> images) async {
    if (images.isEmpty) return;
    final l10n = context.l10n;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    final generation = ref.read(imageGenerationNotifierProvider.notifier);
    final skipConfirmation = ref.read(
      generationImageDeleteConfirmSkippedProvider.notifier,
    );

    if (!skipConfirmation.state) {
      final outcome = await ThemedConfirmDialog.showWithOption(
        context: context,
        title: l10n.common_confirmDelete,
        content: images.length == 1
            ? l10n.generation_deleteImageConfirm
            : l10n.generation_deleteImagesConfirm(images.length),
        optionLabel: l10n.generation_deleteConfirmSkipForSession,
        confirmText: l10n.common_delete,
        cancelText: l10n.common_cancel,
        type: ThemedConfirmDialogType.danger,
        icon: Icons.delete_outline,
      );
      if (!outcome.confirmed) return;
      if (outcome.optionChecked) skipConfirmation.state = true;
    }

    final result = await generation.removeImages(
      images.map((image) => image.id),
    );
    if (result.removedCount == 0) return;
    AppToast.successOnOverlay(
      overlay,
      result.removedCount == 1
          ? l10n.localGallery_imageDeleted
          : l10n.localGallery_deletedImages(result.removedCount),
    );
  }
}
