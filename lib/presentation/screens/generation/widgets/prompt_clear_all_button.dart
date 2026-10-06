import 'package:flutter/material.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../widgets/common/themed_confirm_dialog.dart';
import 'prompt_input_controller.dart';
import 'prompt_input_models.dart';

/// Clears the prompt being edited in one go, after a confirmation that says
/// what goes: every section and, for the positive prompt, the characters.
/// The other prompt can be cleared in the same step.
class PromptClearAllButton extends StatelessWidget {
  const PromptClearAllButton({
    super.key,
    required this.controller,
    required this.commands,
    this.style,
    this.iconSize,
  });

  final PromptInputController controller;
  final PromptInputCommands commands;
  final ButtonStyle? style;
  final double? iconSize;

  Future<void> _confirm(BuildContext context) async {
    final l10n = context.l10n;
    final negative = controller.isNegativeMode;
    final outcome = await ThemedConfirmDialog.showWithOption(
      context: context,
      title: l10n.prompt_clearAll,
      content: negative
          ? l10n.prompt_clearAllNegativeContent
          : l10n.prompt_clearAllPositiveContent,
      optionLabel: negative
          ? l10n.prompt_clearAllAlsoPositive
          : l10n.prompt_clearAllAlsoNegative,
      confirmText: l10n.toolbar_clear,
      cancelText: l10n.common_cancel,
      type: ThemedConfirmDialogType.danger,
      icon: Icons.delete_sweep_outlined,
    );
    if (!outcome.confirmed) return;
    if (!negative || outcome.optionChecked) commands.clearPrompt();
    if (negative || outcome.optionChecked) commands.clearNegativePrompt();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const ValueKey('generation_prompt_clear_all'),
      style: style,
      tooltip: context.l10n.prompt_clearAll,
      onPressed: () => _confirm(context),
      icon: Icon(Icons.delete_sweep_outlined, size: iconSize),
    );
  }
}
