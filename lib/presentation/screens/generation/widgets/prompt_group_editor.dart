import 'package:flutter/material.dart';

import '../../../../core/utils/localization_extension.dart';
import 'prompt_group_actions.dart';
import 'prompt_group_controller.dart';
import 'prompt_group_edit_sheet.dart';
import 'prompt_group_grid.dart';
import 'prompt_input_controller.dart';
import 'prompt_input_models.dart';

/// Grouped prompt mode: a grid of section tiles, each edited in its own sheet.
///
/// Every change to the sections is recombined into the generation prompt.
class PromptGroupEditor extends StatelessWidget {
  const PromptGroupEditor({
    super.key,
    required this.controller,
    required this.commands,
    required this.viewData,
  });

  final PromptInputController controller;
  final PromptInputCommands commands;
  final PromptInputViewData viewData;

  @override
  Widget build(BuildContext context) {
    final negative = controller.isNegativeMode;
    final groups = controller.groupsFor(negative);
    final grid = PromptGroupGrid(
      key: ValueKey(
        negative
            ? 'generation_negative_prompt_group_grid'
            : 'generation_positive_prompt_group_grid',
      ),
      groups: groups,
      onOpen: (id) => _open(context, groups, id, negative),
      onShowActions: (id) => _showActions(context, groups, id, negative),
      onToggleEnabled: (id) => _toggle(groups, id, negative),
      onDelete: (id) => _delete(context, groups, id, negative),
      onReordered: () => _commit(negative),
    );
    final listKey = ValueKey(
      negative
          ? 'generation_negative_prompt_groups'
          : 'generation_positive_prompt_groups',
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final bounded =
            constraints.hasBoundedHeight && constraints.maxHeight.isFinite;
        return bounded
            ? SingleChildScrollView(key: listKey, child: grid)
            : KeyedSubtree(key: listKey, child: grid);
      },
    );
  }

  void _commit(bool negative) {
    final prompt = controller.commitGroupedPrompt(negative: negative);
    if (negative) {
      commands.updateNegativePrompt(prompt);
    } else {
      commands.updatePrompt(prompt);
    }
  }

  void _toggle(PromptGroupCollection groups, String id, bool negative) {
    final section = groups.sectionById(id);
    if (section == null) return;
    groups.setEnabled(id, !section.enabled);
    _commit(negative);
  }

  void _duplicate(PromptGroupCollection groups, String id, bool negative) {
    if (groups.duplicate(id) != null) _commit(negative);
  }

  void _moveToFront(PromptGroupCollection groups, String id, bool negative) {
    groups.move(id, 0);
    _commit(negative);
  }

  /// Deletes at once; the snack bar offers undo instead of a confirmation.
  void _delete(
    BuildContext context,
    PromptGroupCollection groups,
    String id,
    bool negative,
  ) {
    final removed = groups.remove(id);
    if (removed == null) return;
    _commit(negative);
    final l10n = context.l10n;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.prompt_groupDeleted(removed.index + 1)),
          action: SnackBarAction(
            label: l10n.common_undo,
            onPressed: () {
              if (!context.mounted) return;
              groups.restoreRemoved(removed);
              _commit(negative);
            },
          ),
        ),
      );
  }

  Future<void> _open(
    BuildContext context,
    PromptGroupCollection groups,
    String id,
    bool negative,
  ) {
    FocusManager.instance.primaryFocus?.unfocus();
    return showPromptGroupEditSheet(
      context,
      groups: groups,
      sectionId: id,
      negative: negative,
      numericEmphasisEnabled: viewData.numericEmphasisEnabled,
      callbacks: PromptGroupEditCallbacks(
        onChanged: () => _commit(negative),
        onToggleEnabled: (id) => _toggle(groups, id, negative),
        onDuplicate: (id) => _duplicate(groups, id, negative),
        onMoveToFront: (id) => _moveToFront(groups, id, negative),
        onDelete: (id) {
          if (context.mounted) _delete(context, groups, id, negative);
        },
        onOpenAssistantSettings: commands.openAssistantSettings,
        onComfyuiImport: negative ? null : commands.importComfyuiPrompt,
      ),
    );
  }

  Future<void> _showActions(
    BuildContext context,
    PromptGroupCollection groups,
    String id,
    bool negative,
  ) async {
    final action = await showPromptGroupActions(
      context,
      groups: groups,
      sectionId: id,
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case PromptGroupAction.toggleEnabled:
        _toggle(groups, id, negative);
      case PromptGroupAction.edit:
        await _open(context, groups, id, negative);
      case PromptGroupAction.duplicate:
        _duplicate(groups, id, negative);
      case PromptGroupAction.moveToFront:
        _moveToFront(groups, id, negative);
      case PromptGroupAction.delete:
        _delete(context, groups, id, negative);
    }
  }
}
