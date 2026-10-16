import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../../data/models/fixed_tag/fixed_tag_entry.dart';
import '../../../providers/fixed_tags_provider.dart';
import '../../../providers/tag_library_page_provider.dart';
import '../../../widgets/character/fixed_tag_reference_picker.dart';
import '../../tag_library_page/widgets/entry_add_dialog.dart';
import 'prompt_group_actions.dart';
import 'prompt_group_controller.dart';
import 'prompt_group_edit_sheet.dart';
import 'prompt_group_fixed_tags.dart';
import 'prompt_group_grid.dart';
import 'prompt_group_undo_bar.dart';
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
    return PromptGroupBoard(
      groups: controller.groupsFor(negative),
      negative: negative,
      gridKey: ValueKey(
        negative
            ? 'generation_negative_prompt_group_grid'
            : 'generation_positive_prompt_group_grid',
      ),
      listKey: ValueKey(
        negative
            ? 'generation_negative_prompt_groups'
            : 'generation_positive_prompt_groups',
      ),
      numericEmphasisEnabled: viewData.numericEmphasisEnabled,
      onCommit: (negative) {
        final prompt = controller.commitGroupedPrompt(negative: negative);
        if (negative) {
          commands.updateNegativePrompt(prompt);
        } else {
          commands.updatePrompt(prompt);
        }
      },
      onOpenAssistantSettings: commands.openAssistantSettings,
      onComfyuiImport: negative ? null : commands.importComfyuiPrompt,
    );
  }
}

/// The section grid of one prompt with everything around it: the section
/// editor sheet, the long-press menu and delete with undo.
///
/// [onCommit] recombines the prompt after any change. [modeSessionId] and
/// [excludeFixedTags] describe whose prompt this is, see
/// [showPromptGroupEditSheet].
class PromptGroupBoard extends ConsumerStatefulWidget {
  const PromptGroupBoard({
    super.key,
    required this.groups,
    required this.negative,
    required this.gridKey,
    required this.listKey,
    required this.numericEmphasisEnabled,
    required this.onCommit,
    required this.onOpenAssistantSettings,
    this.onComfyuiImport,
    this.modeSessionId,
    this.excludeFixedTags = true,
    this.minTileWidth = PromptGroupGrid.defaultMinTileWidth,
    this.allowFixedTags = false,
  });

  final PromptGroupCollection groups;
  final double minTileWidth;

  /// A character's sections: fixed tags can be placed among them, and the
  /// tags they take from the main prompt are named below the grid.
  final bool allowFixedTags;
  final bool negative;
  final Key gridKey;
  final Key listKey;
  final bool numericEmphasisEnabled;
  final ValueChanged<bool> onCommit;
  final VoidCallback onOpenAssistantSettings;
  final PromptImportCallback? onComfyuiImport;
  final String? modeSessionId;
  final bool excludeFixedTags;

  @override
  ConsumerState<PromptGroupBoard> createState() => _PromptGroupBoardState();
}

/// A deletion that can still be undone from the floating bar.
class _PendingUndo {
  const _PendingUndo(this.groups, this.removed, this.negative);

  final PromptGroupCollection groups;
  final RemovedPromptGroup removed;
  final bool negative;
}

class _PromptGroupBoardState extends ConsumerState<PromptGroupBoard> {
  static const Duration _undoDuration = Duration(seconds: 4);
  static const double _undoBarSpace = 72;

  _PendingUndo? _undo;
  Timer? _undoTimer;

  @override
  void dispose() {
    _undoTimer?.cancel();
    super.dispose();
  }

  Map<String, FixedTagEntry> _fixedTagsById = const {};

  PromptGroupFixedTagInfo? _fixedTagInfo(PromptGroupSection section) {
    final id = section.fixedTagId;
    if (id == null) return null;
    final entry = _fixedTagsById[id];
    return PromptGroupFixedTagInfo(
      name: entry?.displayName,
      claimed:
          entry != null &&
          entry.enabled &&
          section.enabled &&
          !section.keepInMain,
    );
  }

  @override
  Widget build(BuildContext context) {
    final negative = widget.negative;
    final groups = widget.groups;
    final showsFixedTags = widget.allowFixedTags || groups.hasFixedTags;
    if (showsFixedTags) {
      _fixedTagsById = {
        for (final entry in ref.watch(
          fixedTagsNotifierProvider.select((state) => state.entries),
        ))
          entry.id: entry,
      };
    }
    final grid = PromptGroupGrid(
      key: widget.gridKey,
      groups: groups,
      onOpen: (id) => _open(groups, id, negative),
      onShowActions: (id) => _showActions(groups, id, negative),
      onToggleEnabled: (id) => _toggle(groups, id, negative),
      onDelete: (id) => _delete(groups, id, negative),
      onReordered: () => widget.onCommit(negative),
      minTileWidth: widget.minTileWidth,
      fixedTagInfoOf: showsFixedTags ? _fixedTagInfo : null,
    );
    final body = widget.allowFixedTags
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              grid,
              PromptGroupFixedTagBar(
                claimedNames: [
                  for (final section in groups.sections)
                    if (_fixedTagInfo(section) case final info?
                        when info.claimed)
                      ?info.name,
                ],
                onAdd: () => _addFixedTag(groups, negative),
              ),
            ],
          )
        : grid;
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
              KeyedSubtree(key: widget.listKey, child: body),
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
                key: widget.listKey,
                padding: EdgeInsets.only(
                  bottom: undo == null ? 0 : _undoBarSpace,
                ),
                child: body,
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

  void _toggle(PromptGroupCollection groups, String id, bool negative) {
    final section = groups.sectionById(id);
    if (section == null) return;
    groups.setEnabled(id, !section.enabled);
    widget.onCommit(negative);
  }

  void _duplicate(PromptGroupCollection groups, String id, bool negative) {
    if (groups.duplicate(id) != null) widget.onCommit(negative);
  }

  void _moveToFront(PromptGroupCollection groups, String id, bool negative) {
    groups.move(id, 0);
    widget.onCommit(negative);
  }

  /// Deletes at once; the floating bar offers undo for a few seconds instead
  /// of asking for confirmation.
  void _delete(PromptGroupCollection groups, String id, bool negative) {
    final removed = groups.remove(id);
    if (removed == null) return;
    widget.onCommit(negative);
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
    widget.onCommit(undo.negative);
  }

  /// Places a fixed tag among the sections, at the start for a prefix tag.
  Future<void> _addFixedTag(PromptGroupCollection groups, bool negative) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final picked = await showFixedTagReferencePicker(
      context,
      entries: ref.read(fixedTagsNotifierProvider).entries,
      negative: negative,
      placedIds: {for (final section in groups.sections) ?section.fixedTagId},
    );
    if (picked == null || !mounted) return;
    groups.addFixedTag(
      picked.id,
      picked.weightedContent,
      atStart: picked.position == FixedTagPosition.prefix,
    );
    widget.onCommit(negative);
  }

  Future<void> _openFixedTag(
    PromptGroupCollection groups,
    String id,
    bool negative,
  ) async {
    final section = groups.sectionById(id);
    if (section == null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final action = await showFixedTagSectionMenu(
      context,
      name: _fixedTagInfo(section)?.name,
      keepInMain: section.keepInMain,
    );
    if (action == null || !mounted) return;
    switch (action) {
      case FixedTagSectionAction.toggleKeepInMain:
        groups.setKeepInMain(id, !section.keepInMain);
        widget.onCommit(negative);
      case FixedTagSectionAction.detach:
        groups.detachFixedTag(id);
        widget.onCommit(negative);
      case FixedTagSectionAction.remove:
        _delete(groups, id, negative);
    }
  }

  Future<void> _open(PromptGroupCollection groups, String id, bool negative) {
    if (groups.sectionById(id)?.isFixedTag ?? false) {
      return _openFixedTag(groups, id, negative);
    }
    FocusManager.instance.primaryFocus?.unfocus();
    return showPromptGroupEditSheet(
      context,
      groups: groups,
      sectionId: id,
      negative: negative,
      numericEmphasisEnabled: widget.numericEmphasisEnabled,
      modeSessionId: widget.modeSessionId,
      excludeFixedTags: widget.excludeFixedTags,
      callbacks: PromptGroupEditCallbacks(
        onChanged: () => widget.onCommit(negative),
        onToggleEnabled: (id) => _toggle(groups, id, negative),
        onDuplicate: (id) => _duplicate(groups, id, negative),
        onMoveToFront: (id) => _moveToFront(groups, id, negative),
        onDelete: (id) {
          if (mounted) _delete(groups, id, negative);
        },
        onOpenAssistantSettings: widget.onOpenAssistantSettings,
        onComfyuiImport: widget.onComfyuiImport,
      ),
    );
  }

  /// Opens the library's entry form with the section's prompt; the title,
  /// category and preview image are filled in there before saving.
  Future<void> _saveToLibrary(PromptGroupCollection groups, String id) async {
    final text = groups.sectionById(id)?.controller.text.trim() ?? '';
    if (text.isEmpty) return;
    await EntryAddDialog.show(
      context,
      categories: ref.read(tagLibraryPageCategoriesProvider),
      initialContent: text,
    );
  }

  Future<void> _showActions(
    PromptGroupCollection groups,
    String id,
    bool negative,
  ) async {
    if (groups.sectionById(id)?.isFixedTag ?? false) {
      return _openFixedTag(groups, id, negative);
    }
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
      case PromptGroupAction.saveToLibrary:
        await _saveToLibrary(groups, id);
      case PromptGroupAction.delete:
        _delete(groups, id, negative);
    }
  }
}
