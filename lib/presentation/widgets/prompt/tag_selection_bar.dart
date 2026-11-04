import 'package:flutter/material.dart';

import '../../../core/utils/localization_extension.dart';
import '../../themes/core/layered_surface_style.dart';

class TagSelectionBar extends StatelessWidget {
  const TagSelectionBar({
    super.key,
    required this.count,
    required this.onClose,
    required this.onCopy,
    required this.onSelectAll,
    this.onMove,
  });

  final int count;
  final VoidCallback onClose;
  final VoidCallback onCopy;
  final VoidCallback onSelectAll;
  final VoidCallback? onMove;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Material(
      color: controlSurfaceColor(Theme.of(context).colorScheme),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          children: [
            IconButton(
              tooltip: l10n.common_cancel,
              onPressed: onClose,
              icon: const Icon(Icons.close),
            ),
            Text(l10n.tagLibrary_selectedCount(count)),
            IconButton(
              tooltip: l10n.common_selectAll,
              onPressed: onSelectAll,
              icon: const Icon(Icons.select_all),
            ),
            TextButton.icon(
              key: const ValueKey('tag-selection-copy'),
              onPressed: onCopy,
              icon: const Icon(Icons.content_copy, size: 18),
              label: Text(l10n.common_copy),
            ),
            if (onMove != null)
              TextButton.icon(
                key: const ValueKey('tag-selection-move'),
                onPressed: onMove,
                icon: const Icon(Icons.drive_file_move_outline, size: 18),
                label: Text(l10n.common_move),
              ),
          ],
        ),
      ),
    );
  }
}
