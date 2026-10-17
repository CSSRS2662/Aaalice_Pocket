import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/app_logger.dart';
import '../../../../core/utils/localization_extension.dart';
import '../../../providers/image_generation_provider.dart';
import '../../../providers/local_gallery_provider.dart';
import '../../../widgets/common/app_toast.dart';
import 'generated_image_file_link.dart';

final Set<String> _togglesInFlight = {};

/// Toggles a generated image's favorite, saving it to the gallery first when
/// needed. The heart shows the result, so only failures are announced.
Future<void> toggleGeneratedImageFavorite(
  BuildContext context,
  WidgetRef ref,
  GeneratedImage image,
) async {
  if (!_togglesInFlight.add(image.id)) return;
  // 保存期间卡片可能被卸载，句柄在第一个 await 之前取好。
  final gallery = ref.read(localGalleryNotifierProvider.notifier);
  final l10n = context.l10n;
  try {
    final linked = await GeneratedImageFileLink.ensureSaved(
      ref.read,
      image,
      l10n,
    );
    final favorite = await gallery.toggleFavorite(linked.path);
    AppLogger.i(
      '[GeneratedSave] favorite=$favorite for result ${image.id} at '
          '${linked.path}',
      'GeneratedImageFavorite',
    );
  } catch (error) {
    if (context.mounted) {
      AppToast.error(context, l10n.toast_favoriteUpdateFailed('$error'));
    }
  } finally {
    _togglesInFlight.remove(image.id);
  }
}
