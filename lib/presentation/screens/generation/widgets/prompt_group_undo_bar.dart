import 'package:flutter/material.dart';

import '../../../../core/utils/localization_extension.dart';

/// Dark floating capsule offering to undo a section deletion.
///
/// Shown inside the prompt page rather than as a scaffold snack bar: a snack
/// bar with an action no longer times out on its own, and on phones it sat
/// on top of the generate bar.
class PromptGroupUndoBar extends StatelessWidget {
  const PromptGroupUndoBar({
    super.key,
    required this.message,
    required this.onUndo,
  });

  final String message;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      key: const ValueKey('prompt_group_undo_bar'),
      color: colors.inverseSurface,
      elevation: 6,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsetsDirectional.only(start: 20, end: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onInverseSurface,
                  ),
                ),
              ),
              TextButton(
                key: const ValueKey('prompt_group_undo_action'),
                onPressed: onUndo,
                style: TextButton.styleFrom(
                  foregroundColor: colors.inversePrimary,
                  shape: const StadiumBorder(),
                ),
                child: Text(context.l10n.common_undo),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
