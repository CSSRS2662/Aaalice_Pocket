import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import '../../../core/services/system_album.dart';
import '../../../core/utils/localization_extension.dart';
import 'app_toast.dart';

/// Confirms a save: the photo album on a phone, the folder it went to
/// elsewhere.
void showAlbumSaved(BuildContext context, SystemAlbum album, String location) {
  final l10n = context.l10n;
  AppToast.success(
    context,
    album.target.isPhotoAlbum
        ? l10n.image_savedToSystemGallery
        : l10n.toast_savedTo(p.dirname(location)),
  );
}
