import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/app_logger.dart';
import '../../../../core/utils/localization_extension.dart';
import '../../../providers/local_gallery_provider.dart';
import '../../../widgets/common/app_toast.dart';
import '../../../widgets/common/themed_confirm_dialog.dart';
import 'cache_statistics_tile.dart';

/// 图库只放收藏：一键删除旧版本存进图库、但没有收藏的图片。
class GalleryUnfavoritedCleanupTile extends ConsumerStatefulWidget {
  const GalleryUnfavoritedCleanupTile({super.key});

  @override
  ConsumerState<GalleryUnfavoritedCleanupTile> createState() =>
      _GalleryUnfavoritedCleanupTileState();
}

class _GalleryUnfavoritedCleanupTileState
    extends ConsumerState<GalleryUnfavoritedCleanupTile> {
  bool _busy = false;

  Future<void> _clean() async {
    if (_busy) return;
    setState(() => _busy = true);
    final gallery = ref.read(localGalleryNotifierProvider.notifier);
    final l10n = context.l10n;
    try {
      final paths = await gallery.findUnfavoritedImages();
      if (!mounted) return;
      if (paths.isEmpty) {
        AppToast.info(context, l10n.settings_cleanUnfavoritedNone);
        return;
      }
      final confirmed = await ThemedConfirmDialog.show(
        context: context,
        title: l10n.settings_cleanUnfavorited,
        content: l10n.settings_cleanUnfavoritedConfirm(paths.length),
        confirmText: l10n.common_delete,
        cancelText: l10n.common_cancel,
        type: ThemedConfirmDialogType.danger,
        icon: Icons.delete_sweep_outlined,
      );
      if (!confirmed) return;
      final result = await gallery.deleteUnfavoritedImages(paths);
      ref.invalidate(cacheStatisticsProvider);
      if (!mounted) return;
      final deleted = result.deletedPaths.length;
      if (result.failedCount == 0) {
        AppToast.success(context, l10n.settings_cleanUnfavoritedDone(deleted));
      } else {
        AppToast.warning(
          context,
          l10n.settings_cleanUnfavoritedPartial(deleted, result.failedCount),
        );
      }
    } catch (error, stackTrace) {
      AppLogger.e(
        'Cleaning unfavorited images failed',
        error,
        stackTrace,
        'GalleryUnfavoritedCleanupTile',
      );
      if (mounted) {
        AppToast.error(context, l10n.settings_cleanUnfavoritedFailed('$error'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: const ValueKey('settings_clean_unfavorited'),
      leading: const Icon(Icons.delete_sweep_outlined),
      title: Text(context.l10n.settings_cleanUnfavorited),
      subtitle: Text(context.l10n.settings_cleanUnfavoritedSubtitle),
      trailing: _busy
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
      onTap: _busy ? null : _clean,
    );
  }
}
