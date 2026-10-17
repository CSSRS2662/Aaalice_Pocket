import 'package:flutter/material.dart';

import '../../../core/utils/localization_extension.dart';
import 'action_notice.dart';

/// Tells the user that the gallery already has the [count] images this save
/// skipped, with "Save anyway" to write them again.
void showDuplicateSaveNotice(
  BuildContext context, {
  required VoidCallback onSaveAnyway,
  int count = 1,
}) {
  final l10n = context.l10n;
  ActionNotice.show(
    context,
    message: count > 1
        ? l10n.image_duplicatesNotSaved(count)
        : l10n.image_duplicateNotSaved,
    actionLabel: l10n.image_saveAnyway,
    actionKey: const ValueKey('duplicate_save_anyway'),
    onAction: onSaveAnyway,
  );
}
