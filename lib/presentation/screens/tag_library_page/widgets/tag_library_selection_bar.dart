import 'package:flutter/material.dart';

import '../../../../core/utils/localization_extension.dart';

enum _SelectionMore { copy, addAsFixed, delete }

/// The dark floating bar while selecting entries on a phone: send them all to
/// the prompt, favorite, move, and the rest under ⋯.
class TagLibrarySelectionBar extends StatelessWidget {
  const TagLibrarySelectionBar({
    super.key,
    required this.count,
    required this.allFavorite,
    required this.onSend,
    required this.onToggleFavorite,
    required this.onMove,
    required this.onCopy,
    required this.onAddAsFixed,
    required this.onDelete,
  });

  final int count;

  /// Every selected entry is a favorite, so the heart removes them instead.
  final bool allFavorite;
  final VoidCallback onSend;
  final VoidCallback onToggleFavorite;
  final VoidCallback onMove;
  final VoidCallback onCopy;
  final VoidCallback onAddAsFixed;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = context.l10n;
    final enabled = count > 0;
    final iconColor = colors.onInverseSurface;
    return Material(
      key: const ValueKey('tag-library-selection-bar'),
      color: colors.inverseSurface,
      borderRadius: BorderRadius.circular(20),
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                key: const ValueKey('tag-library-selection-send'),
                onPressed: enabled ? onSend : null,
                style: FilledButton.styleFrom(
                  backgroundColor: colors.inversePrimary,
                  foregroundColor: colors.onPrimaryContainer,
                  minimumSize: const Size(0, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.send_rounded, size: 18),
                label: Text(
                  l10n.tagLibrary_sendSelected(count),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              key: const ValueKey('tag-library-selection-favorite'),
              tooltip: allFavorite
                  ? l10n.common_unfavorite
                  : l10n.common_favorite,
              onPressed: enabled ? onToggleFavorite : null,
              color: iconColor,
              icon: Icon(
                allFavorite
                    ? Icons.heart_broken_outlined
                    : Icons.favorite_border_rounded,
              ),
            ),
            IconButton(
              key: const ValueKey('tag-library-selection-move'),
              tooltip: l10n.tagLibrary_moveToCategoryTitle,
              onPressed: enabled ? onMove : null,
              color: iconColor,
              icon: const Icon(Icons.drive_file_move_outline),
            ),
            PopupMenuButton<_SelectionMore>(
              key: const ValueKey('tag-library-selection-more'),
              tooltip: MaterialLocalizations.of(context).moreButtonTooltip,
              enabled: enabled,
              iconColor: iconColor,
              onSelected: (action) => switch (action) {
                _SelectionMore.copy => onCopy(),
                _SelectionMore.addAsFixed => onAddAsFixed(),
                _SelectionMore.delete => onDelete(),
              },
              itemBuilder: (_) => [
                _item(
                  _SelectionMore.copy,
                  Icons.content_copy_rounded,
                  l10n.tagLibrary_copyContent,
                ),
                _item(
                  _SelectionMore.addAsFixed,
                  Icons.push_pin_outlined,
                  l10n.tagLibrary_addAsFixed,
                ),
                const PopupMenuDivider(),
                _item(
                  _SelectionMore.delete,
                  Icons.delete_outline_rounded,
                  l10n.common_delete,
                  color: colors.error,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static PopupMenuItem<_SelectionMore> _item(
    _SelectionMore value,
    IconData icon,
    String label, {
    Color? color,
  }) => PopupMenuItem(
    key: ValueKey('tag-library-selection-${value.name}'),
    value: value,
    child: Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label, style: TextStyle(color: color)),
        ),
      ],
    ),
  );
}
