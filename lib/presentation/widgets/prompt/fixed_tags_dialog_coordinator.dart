import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/localization_extension.dart';
import '../../../data/models/fixed_tag/fixed_tag_entry.dart';
import '../../../data/models/fixed_tag/fixed_tag_prompt_type.dart';
import '../../../data/models/tag_library/tag_library_entry.dart';
import '../../providers/fixed_tags_provider.dart';
import '../../providers/fixed_tags_sort_provider.dart';
import '../../providers/tag_library_page_provider.dart';
import '../../router/app_routes.dart';
import '../../screens/tag_library_page/widgets/bulk_move_category_dialog.dart';
import '../common/app_toast.dart';
import '../common/sort_options_sheet.dart';
import '../common/themed_confirm_dialog.dart';
import 'fixed_tag_details_sheet.dart';
import 'fixed_tag_edit_dialog.dart';
import 'fixed_tag_library_picker_dialog.dart';
import 'fixed_tags_dialog_models.dart';
import 'fixed_tags_link_manager.dart';

class FixedTagsDialogCoordinator {
  const FixedTagsDialogCoordinator(this.ref);

  final WidgetRef ref;

  FixedTagsDialogCommands commands(BuildContext context) {
    final notifier = ref.read(fixedTagsNotifierProvider.notifier);
    late final FixedTagsDialogCommands commands;
    return commands = FixedTagsDialogCommands(
      close: () => Navigator.of(context).pop(),
      openLibraryPage: () {
        Navigator.of(context).pop();
        context.go(AppRoutes.tagLibraryPage);
      },
      toggleNegativePanel: () {
        final expanded = ref.read(
          fixedTagsNotifierProvider.select(
            (state) => state.negativePanelExpanded,
          ),
        );
        notifier.setNegativePanelExpanded(!expanded);
      },
      undo: notifier.undo,
      redo: notifier.redo,
      setAllEnabled: notifier.setAllEnabled,
      setPromptTypeEnabled: (promptType, enabled) {
        if (promptType == FixedTagPromptType.positive) {
          notifier.setAllPositiveEnabled(enabled);
        } else {
          notifier.setAllNegativeEnabled(enabled);
        }
      },
      toggleEntry: (entry) => notifier.toggleEnabled(entry.id),
      showDetails: (entry) => showFixedTagDetails(
        context: context,
        entry: entry,
        commands: commands,
      ),
      togglePosition: (entry) => notifier.togglePosition(entry.id),
      setWeight: (entry, weight) =>
          notifier.updateEntry(entry.copyWith(weight: weight)),
      moveToCategory: (entry) => _moveToCategory(context, entry),
      reorder: notifier.reorderWithinPromptType,
      editEntry: (entry, initialPromptType) =>
          _editEntry(context, entry, initialPromptType),
      deleteEntry: (entry) => _deleteEntry(context, entry),
      clearAll: () => _clearAll(context),
      pickFromLibrary: (promptType) => _showLibraryPicker(context, promptType),
      // The grid has no drag anchors, so every layout lists link candidates.
      showLinkManager: (entry) => showFixedTagLinkManager(
        context: context,
        ref: ref,
        entry: entry,
        showAllCandidates: true,
      ),
      showSortOptions: () => _showSortOptions(context),
    );
  }

  /// A tag from the library lives in its entry's group, so moving it moves
  /// the entry and the tag follows; other tags just change their own group.
  Future<void> _moveToCategory(
    BuildContext context,
    FixedTagEntry entry,
  ) async {
    final library = ref.read(tagLibraryPageNotifierProvider);
    final linked = library.entries
        .where((item) => item.id == entry.sourceEntryId)
        .firstOrNull;
    final target = await BulkMoveCategoryDialog.show(
      context,
      categories: library.categories,
      currentCategoryId: linked?.categoryId ?? entry.categoryId,
    );
    if (target == null) return;
    final categoryId = target.isEmpty ? null : target;
    if (linked != null) {
      await ref
          .read(tagLibraryPageNotifierProvider.notifier)
          .moveEntryToCategory(linked.id, categoryId);
    } else {
      await ref
          .read(fixedTagsNotifierProvider.notifier)
          .updateEntry(entry.copyWith(categoryId: categoryId));
    }
  }

  void _showSortOptions(BuildContext context) {
    final l10n = context.l10n;
    showSortOptionsSheet<FixedTagsSort>(
      context: context,
      title: l10n.fixedTags_sortTitle,
      specOf: (ref) {
        final prefs = ref.watch(fixedTagsSortProvider);
        final notifier = ref.read(fixedTagsSortProvider.notifier);
        return SortOptionsSpec(
          options: [
            SortOption(
              value: FixedTagsSort.frequent,
              title: l10n.fixedTags_sortFrequent,
              subtitle: l10n.fixedTags_sortFrequentHint,
            ),
            SortOption(
              value: FixedTagsSort.recent,
              title: l10n.fixedTags_sortRecent,
              subtitle: l10n.fixedTags_sortRecentHint,
            ),
            SortOption(
              value: FixedTagsSort.custom,
              title: l10n.fixedTags_sortCustom,
              subtitle: l10n.fixedTags_sortCustomHint,
            ),
            SortOption(
              value: FixedTagsSort.name,
              title: l10n.fixedTags_sortName,
              subtitle: l10n.fixedTags_sortNameHint,
            ),
          ],
          selected: prefs.sort,
          onSelected: notifier.setSort,
          toggle: SortToggle(
            key: const ValueKey('fixed-tags-enabled-first'),
            title: l10n.fixedTags_enabledFirst,
            subtitle: l10n.fixedTags_enabledFirstHint,
            value: prefs.enabledFirst,
            enabled: !prefs.groupsByCategory,
            onChanged: notifier.setEnabledFirst,
          ),
        );
      },
    );
  }

  Future<void> _showLibraryPicker(
    BuildContext context,
    FixedTagPromptType promptType,
  ) async {
    final libraryEntries = ref.read(tagLibraryPageNotifierProvider).entries;
    if (libraryEntries.isEmpty) {
      AppToast.info(context, context.l10n.fixedTags_libraryEmpty);
      return;
    }
    final entries = filterUnlinkedLibraryEntries(
      libraryEntries: libraryEntries,
      fixedEntries: ref.read(fixedTagsNotifierProvider).entries,
    );
    final selected = await FixedTagLibraryPickerDialog.show(
      context: context,
      entries: entries,
    );
    if (selected != null) {
      await _addFromLibrary(selected, promptType);
    }
  }

  Future<void> _addFromLibrary(
    TagLibraryEntry entry,
    FixedTagPromptType promptType,
  ) {
    return ref
        .read(fixedTagsNotifierProvider.notifier)
        .addEntry(
          name: entry.name,
          content: entry.content,
          weight: 1,
          position: FixedTagPosition.prefix,
          enabled: true,
          promptType: promptType,
          sourceEntryId: entry.id,
          categoryId: entry.categoryId,
        );
  }

  Future<void> _editEntry(
    BuildContext context,
    FixedTagEntry? entry,
    FixedTagPromptType initialPromptType,
  ) async {
    final result = await FixedTagEditDialog.show(
      context: context,
      entry: entry,
      initialPromptType: initialPromptType,
    );
    if (result == null) return;
    final notifier = ref.read(fixedTagsNotifierProvider.notifier);
    if (entry == null) {
      await notifier.addEntry(
        name: result.name,
        content: result.content,
        weight: result.weight,
        position: result.position,
        promptType: result.promptType,
        enabled: result.enabled,
        sourceEntryId: result.sourceEntryId,
        categoryId: result.categoryId,
      );
    } else {
      await notifier.updateEntry(result);
    }
  }

  Future<void> _deleteEntry(BuildContext context, FixedTagEntry entry) async {
    final confirmed = await ThemedConfirmDialog.show(
      context: context,
      title: context.l10n.fixedTags_deleteTitle,
      content: context.l10n.fixedTags_deleteConfirm(entry.displayName),
      confirmText: context.l10n.common_delete,
      cancelText: context.l10n.common_cancel,
      type: ThemedConfirmDialogType.danger,
      icon: Icons.delete_outline,
    );
    if (confirmed) {
      await ref.read(fixedTagsNotifierProvider.notifier).deleteEntry(entry.id);
    }
  }

  Future<void> _clearAll(BuildContext context) async {
    final count = ref.read(fixedTagsNotifierProvider).entries.length;
    final confirmed = await ThemedConfirmDialog.show(
      context: context,
      title: context.l10n.fixedTags_clearAllTitle,
      content: context.l10n.fixedTags_clearAllConfirm(count),
      confirmText: context.l10n.fixedTags_clearAll,
      cancelText: context.l10n.common_cancel,
      type: ThemedConfirmDialogType.danger,
      icon: Icons.delete_sweep_outlined,
    );
    if (!confirmed || !context.mounted) return;
    await ref.read(fixedTagsNotifierProvider.notifier).clearAll();
    if (context.mounted) {
      AppToast.success(context, context.l10n.fixedTags_clearedSuccess);
    }
  }
}
