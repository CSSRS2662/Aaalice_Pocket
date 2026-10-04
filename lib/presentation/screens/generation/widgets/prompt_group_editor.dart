import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/utils/localization_extension.dart';
import 'prompt_group_actions.dart';
import 'prompt_group_controller.dart';
import 'prompt_group_edit_sheet.dart';
import 'prompt_group_grid.dart';
import 'prompt_group_undo_bar.dart';
import 'prompt_input_controller.dart';
import 'prompt_input_models.dart';

/// Grouped prompt mode: a grid of section tiles, each edited in its own sheet.
///
/// Every change to the sections is recombined into the generation prompt.
class PromptGroupEditor extends StatefulWidget {
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
  State<PromptGroupEditor> createState() => _PromptGroupEditorState();
}

/// A deletion that can still be undone from the floating bar.
class _PendingUndo {
  const _PendingUndo(this.groups, this.removed, this.negative);

  final PromptGroupCollection groups;
  final RemovedPromptGroup removed;
  final bool negative;
}

class _PromptGroupEditorState extends State<PromptGroupEditor> {
  static const Duration _undoDuration = Duration(seconds: 4);
  static const double _undoBarSpace = 72;

  _PendingUndo? _undo;
  Timer? _undoTimer;

  PromptInputController get controller => widget.controller;
  PromptInputCommands get commands => widget.commands;

  @override
  void dispose() {
    _undoTimer?.cancel();
    super.dispose();
  }

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
      onOpen: (id) => _open(groups, id, negative),
      onShowActions: (id) => _showActions(groups, id, negative),
      onToggleEnabled: (id) => _toggle(groups, id, negative),
      onDelete: (id) => _delete(groups, id, negative),
      onReordered: () => _commit(negative),
    );
    final listKey = ValueKey(
      negative
          ? 'generation_negative_prompt_groups'
          : 'generation_positive_prompt_groups',
    );
    final undo = _undo != null && identical(_undo!.groups, groups)
        ? _undo
        : null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final bounded =
            constraints.hasBoundedHeight && constraints.maxHeight.isFinite;
        if (!bounded) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KeyedSubtree(key: listKey, child: grid),
              _undoBar(undo, top: 12),
            ],
          );
        }
        // The bar floats over the bottom of the sections; extra scroll space
        // keeps the last row reachable while it shows.
        return Stack(
          children: [
            Positioned.fill(
              child: SingleChildScrollView(
                key: listKey,
                padding: EdgeInsets.only(
                  bottom: undo == null ? 0 : _undoBarSpace,
                ),
                child: grid,
              ),
            ),
            Positioned(left: 4, right: 4, bottom: 12, child: _undoBar(undo)),
          ],
        );
      },
    );
  }

  Widget _undoBar(_PendingUndo? undo, {double top = 0}) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final bar = undo == null
        ? const SizedBox.shrink(key: ValueKey('prompt_group_undo_none'))
        : Padding(
            key: ValueKey(undo.removed.snapshot.id),
            padding: EdgeInsets.only(top: top),
            child: PromptGroupUndoBar(
              message: context.l10n.prompt_groupDeleted(undo.removed.index + 1),
              onUndo: _undoDelete,
            ),
          );
    if (reduceMotion) return bar;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.4),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: bar,
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

  /// Deletes at once; the floating bar offers undo for a few seconds instead
  /// of asking for confirmation.
  void _delete(PromptGroupCollection groups, String id, bool negative) {
    final removed = groups.remove(id);
    if (removed == null) return;
    _commit(negative);
    if (!mounted) return;
    _undoTimer?.cancel();
    _undoTimer = Timer(_undoDuration, _dismissUndo);
    setState(() => _undo = _PendingUndo(groups, removed, negative));
  }

  void _dismissUndo() {
    _undoTimer?.cancel();
    _undoTimer = null;
    if (mounted && _undo != null) setState(() => _undo = null);
  }

  void _undoDelete() {
    final undo = _undo;
    _dismissUndo();
    if (undo == null) return;
    undo.groups.restoreRemoved(undo.removed);
    _commit(undo.negative);
  }

  Future<void> _open(PromptGroupCollection groups, String id, bool negative) {
    FocusManager.instance.primaryFocus?.unfocus();
    return showPromptGroupEditSheet(
      context,
      groups: groups,
      sectionId: id,
      negative: negative,
      numericEmphasisEnabled: widget.viewData.numericEmphasisEnabled,
      callbacks: PromptGroupEditCallbacks(
        onChanged: () => _commit(negative),
        onToggleEnabled: (id) => _toggle(groups, id, negative),
        onDuplicate: (id) => _duplicate(groups, id, negative),
        onMoveToFront: (id) => _moveToFront(groups, id, negative),
        onDelete: (id) {
          if (mounted) _delete(groups, id, negative);
        },
        onOpenAssistantSettings: commands.openAssistantSettings,
        onComfyuiImport: negative ? null : commands.importComfyuiPrompt,
      ),
    );
  }

  Future<void> _showActions(
    PromptGroupCollection groups,
    String id,
    bool negative,
  ) async {
    final action = await showPromptGroupActions(
      context,
      groups: groups,
      sectionId: id,
    );
    if (action == null || !mounted) return;
    switch (action) {
      case PromptGroupAction.toggleEnabled:
        _toggle(groups, id, negative);
      case PromptGroupAction.edit:
        await _open(groups, id, negative);
      case PromptGroupAction.duplicate:
        _duplicate(groups, id, negative);
      case PromptGroupAction.moveToFront:
        _moveToFront(groups, id, negative);
      case PromptGroupAction.delete:
        _delete(groups, id, negative);
    }
  }
}
