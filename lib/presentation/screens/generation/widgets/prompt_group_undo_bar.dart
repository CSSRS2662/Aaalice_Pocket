import 'package:flutter/material.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../widgets/common/inverse_action_bar.dart';

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
  Widget build(BuildContext context) => InverseActionBar(
    key: const ValueKey('prompt_group_undo_bar'),
    message: message,
    actionLabel: context.l10n.common_undo,
    actionKey: const ValueKey('prompt_group_undo_action'),
    onAction: onUndo,
  );
}
