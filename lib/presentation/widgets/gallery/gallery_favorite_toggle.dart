import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../core/utils/localization_extension.dart';
import '../../providers/local_gallery_provider.dart';
import '../common/action_notice.dart';

/// Toggles [filePath]'s favorite. The gallery holds favorites only, so
/// unfavoriting removes the image: the notice offers Undo while the file
/// is kept for [LocalGalleryNotifier.unfavoriteRemovalDelay].
Future<bool> toggleGalleryFavorite(
  BuildContext context,
  LocalGalleryNotifier gallery,
  String filePath,
) async {
  final favorite = await gallery.toggleFavorite(filePath);
  if (!favorite && gallery.isRemovalPending(filePath) && context.mounted) {
    final l10n = context.l10n;
    ActionNotice.show(
      context,
      message: l10n.localGallery_unfavoriteRemoved,
      actionLabel: l10n.common_undo,
      actionKey: const ValueKey('gallery_unfavorite_undo'),
      onAction: () => unawaited(gallery.toggleFavorite(filePath)),
    );
  }
  return favorite;
}
