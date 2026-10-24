import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/character_prompt_block_parser.dart';
import '../../../core/utils/comfyui_prompt_parser/pipe_parser.dart';
import '../../../core/utils/localization_extension.dart';
import '../../../core/utils/sd_to_nai_converter.dart';
import '../../../data/models/tag_library/tag_library_entry.dart';
import '../../providers/fixed_tags_provider.dart';
import '../../providers/pending_prompt_provider.dart';
import '../../providers/tag_library_page_provider.dart';
import '../../providers/tag_library_selection_provider.dart';
import '../../router/app_routes.dart';
import '../../widgets/common/action_notice.dart';
import '../../widgets/common/app_toast.dart';
import '../../widgets/common/context_menu_anchor.dart';
import '../../widgets/common/sort_options_sheet.dart';
import '../../widgets/common/themed_confirm_dialog.dart';
import 'widgets/bulk_move_category_dialog.dart';
import 'widgets/entry_add_dialog.dart';
import 'widgets/export_dialog.dart';
import 'widgets/import_dialog.dart';
import 'widgets/send_to_home_dialog.dart';
import 'widgets/tag_library_entry_sheet.dart';
import 'widgets/tag_library_group_manager.dart';
import 'widgets/tag_library_thumbnail_store.dart';
import 'widgets/thumbnail_crop_dialog.dart';

enum _EntryMenuAction { send, edit, favorite, move, copy, delete }

/// What the library page can do with entries and groups. Sending keeps the
/// user in the library and offers 去生成 in a notice.
class TagLibraryActions {
  const TagLibraryActions(this.ref, this.context);

  final WidgetRef ref;
  final BuildContext context;

  TagLibraryPageNotifier get _library =>
      ref.read(tagLibraryPageNotifierProvider.notifier);

  TagLibrarySelectionNotifier get _selection =>
      ref.read(tagLibrarySelectionNotifierProvider.notifier);

  TagLibraryEntryCommands get entryCommands => TagLibraryEntryCommands(
    sendToPrompt: (entry) => sendToPrompt([entry]),
    showSendTargets: showSendTargets,
    toggleFavorite: (entry) => _library.toggleFavorite(entry.id),
    edit: edit,
    copy: (entry) => copy([entry]),
    moveToGroup: (entry) => moveToGroup([entry.id]),
    pickPreview: pickPreview,
    removePreview: removePreview,
    delete: (entry) => confirmDelete([entry]),
  );

  /// The entries with [ids]: those on screen in their shown order, then any
  /// picked before the filter changed.
  List<TagLibraryEntry> entriesOf(Iterable<String> ids) {
    final wanted = ids.toSet();
    final state = ref.read(tagLibraryPageNotifierProvider);
    final shown = [
      for (final entry in state.filteredEntries)
        if (wanted.contains(entry.id)) entry,
    ];
    final shownIds = {for (final entry in shown) entry.id};
    return [
      ...shown,
      for (final entry in state.entries)
        if (wanted.contains(entry.id) && !shownIds.contains(entry.id)) entry,
    ];
  }

  void openEntry(TagLibraryEntry entry) => showTagLibraryEntrySheet(
    context: context,
    entry: entry,
    commands: entryCommands,
  );

  // ==================== 发送 ====================

  /// Adds the entries' positive prompts after the current prompt.
  Future<void> sendToPrompt(List<TagLibraryEntry> entries) async {
    final content = entries
        .map((entry) => CharacterPromptBlockParser.parse(entry.content))
        .map((parsed) => parsed.positivePrompt.trim())
        .where((prompt) => prompt.isNotEmpty)
        .join(', ');
    if (content.isEmpty) return;
    ref
        .read(pendingPromptNotifierProvider.notifier)
        .appendToMainPrompt(content);
    _selection.exit();
    final message = entries.length == 1
        ? context.l10n.tagLibrary_addedToPrompt
        : context.l10n.tagLibrary_addedEntriesToPrompt(entries.length);
    _showGoGenerate(message);
    await _library.recordUsages(entries.map((entry) => entry.id));
  }

  /// The other targets: characters, smart split, fixed tags.
  Future<void> showSendTargets(TagLibraryEntry entry) async {
    final options = await SendToHomeDialog.show(context, entry: entry);
    if (options == null || !context.mounted) return;
    if (options.targetType == SendTargetType.fixedTag) {
      await addAsFixed([entry], alias: options.sendAsAlias);
      return;
    }
    final parsed = CharacterPromptBlockParser.parse(entry.content);
    final content = _contentFor(entry, options);
    final pending = ref.read(pendingPromptNotifierProvider.notifier);
    if (options.targetType == SendTargetType.mainPrompt) {
      pending.appendToMainPrompt(content);
    } else {
      pending.set(
        prompt: content,
        negativePrompt: parsed.hasNegativeBlock ? parsed.negativePrompt : null,
        targetType: options.targetType,
      );
    }
    final l10n = context.l10n;
    _showGoGenerate(switch (options.targetType) {
      SendTargetType.mainPrompt => l10n.tagLibrary_addedToPrompt,
      SendTargetType.smartDecompose => switch (PipeParser.parse(
        content,
      ).characters.length) {
        0 => l10n.prompt_appliedToMainPrompt,
        final count => l10n.prompt_smartDecomposedWithCharacters(count),
      },
      SendTargetType.replaceCharacter =>
        l10n.sendToHome_successReplaceCharacter,
      SendTargetType.appendCharacter => l10n.sendToHome_successAppendCharacter,
      SendTargetType.fixedTag => l10n.toast_addedToFixedTags,
    });
    await _library.recordUsage(entry.id);
  }

  String _contentFor(TagLibraryEntry entry, SendOptions options) {
    if (options.sendAsAlias) return '<${entry.name}>';
    final positive = CharacterPromptBlockParser.parse(
      entry.content,
    ).positivePrompt;
    final toCharacter =
        options.targetType == SendTargetType.replaceCharacter ||
        options.targetType == SendTargetType.appendCharacter;
    if (toCharacter && PipeParser.isPipeFormat(positive)) {
      final characters = PipeParser.parse(positive).characters;
      if (characters.isNotEmpty) {
        return characters.map((c) => c.prompt).join('\n| ');
      }
    }
    return positive;
  }

  void _showGoGenerate(String message) {
    if (!context.mounted) return;
    final router = GoRouter.of(context);
    ActionNotice.show(
      context,
      message: message,
      actionLabel: context.l10n.tagLibrary_goGenerate,
      actionKey: const ValueKey('tag-library-go-generate'),
      onAction: () => router.go(AppRoutes.home),
    );
  }

  /// Adds entries that are not fixed tags yet, linked so both stay in sync.
  Future<void> addAsFixed(
    List<TagLibraryEntry> entries, {
    bool alias = false,
  }) async {
    final linked = {
      for (final tag in ref.read(fixedTagsNotifierProvider).entries)
        if (tag.sourceEntryId != null) tag.sourceEntryId!,
    };
    final adding = entries.where((entry) => !linked.contains(entry.id));
    final notifier = ref.read(fixedTagsNotifierProvider.notifier);
    var added = 0;
    for (final entry in adding) {
      await notifier.addEntry(
        name: entry.name,
        content: alias
            ? '<${entry.name}>'
            : SdToNaiConverter.convert(
                CharacterPromptBlockParser.parse(entry.content).positivePrompt,
              ),
        sourceEntryId: entry.id,
        categoryId: entry.categoryId,
      );
      added++;
    }
    _selection.exit();
    if (!context.mounted) return;
    AppToast.success(
      context,
      added == 0
          ? context.l10n.tagLibrary_alreadyFixed
          : context.l10n.tagLibrary_addedAsFixed(added),
    );
  }

  // ==================== 编辑 ====================

  void addEntry(String? categoryId) => EntryAddDialog.show(
    context,
    categories: ref.read(tagLibraryPageNotifierProvider).categories,
    initialCategoryId: categoryId,
  );

  void edit(TagLibraryEntry entry) => EntryAddDialog.show(
    context,
    categories: ref.read(tagLibraryPageNotifierProvider).categories,
    entry: entry,
  );

  Future<void> copy(List<TagLibraryEntry> entries) async {
    if (entries.isEmpty) return;
    await Clipboard.setData(
      ClipboardData(text: entries.map((entry) => entry.content).join(', ')),
    );
    _selection.exit();
    if (!context.mounted) return;
    AppToast.success(
      context,
      entries.length == 1
          ? context.l10n.common_copied
          : context.l10n.tagLibrary_copiedEntriesContent(entries.length),
    );
  }

  Future<void> moveToGroup(List<String> entryIds) async {
    if (entryIds.isEmpty) return;
    final state = ref.read(tagLibraryPageNotifierProvider);
    final current = entryIds.length == 1
        ? state.entries.where((e) => e.id == entryIds.single).firstOrNull
        : null;
    final target = await BulkMoveCategoryDialog.show(
      context,
      categories: state.categories,
      currentCategoryId: current?.categoryId,
    );
    if (target == null) return;
    await _library.moveEntriesToCategory(
      entryIds,
      target.isEmpty ? null : target,
    );
    _selection.exit();
    if (!context.mounted) return;
    AppToast.success(
      context,
      context.l10n.tagLibrary_movedEntries(entryIds.length),
    );
  }

  /// Favorites them all, or un-favorites them when all already are.
  Future<void> toggleFavorites(List<TagLibraryEntry> entries) async {
    if (entries.isEmpty) return;
    final allFavorite = entries.every((entry) => entry.isFavorite);
    await _library.setFavorite(entries.map((e) => e.id), !allFavorite);
    _selection.exit();
    if (!context.mounted) return;
    AppToast.success(
      context,
      allFavorite
          ? context.l10n.tagLibrary_unfavoritedEntries(entries.length)
          : context.l10n.tagLibrary_favoritedEntries(entries.length),
    );
  }

  Future<void> confirmDelete(List<TagLibraryEntry> entries) async {
    if (entries.isEmpty) return;
    final l10n = context.l10n;
    final confirmed = await ThemedConfirmDialog.show(
      context: context,
      title: entries.length == 1
          ? l10n.tagLibrary_deleteEntryTitle
          : l10n.common_confirmDelete,
      content: entries.length == 1
          ? l10n.tagLibrary_deleteEntryConfirm(entries.single.displayName)
          : l10n.tagLibrary_confirmDeleteSelectedEntries(entries.length),
      confirmText: l10n.common_delete,
      cancelText: l10n.common_cancel,
      type: ThemedConfirmDialogType.danger,
      icon: Icons.delete_outline_rounded,
    );
    if (!confirmed) return;
    await _library.deleteEntries(entries.map((entry) => entry.id).toList());
    _selection.exit();
    if (entries.length > 1 && context.mounted) {
      AppToast.success(context, l10n.tagLibrary_deletedEntries(entries.length));
    }
  }

  // ==================== 预览图 ====================

  Future<void> pickPreview(TagLibraryEntry entry) async {
    final source = await TagLibraryThumbnailStore.pickSource(context);
    if (source == null || !context.mounted) return;
    final bytes = await TagLibraryThumbnailStore.readImage(context, source);
    if (bytes == null || !context.mounted) return;
    final saved = await TagLibraryThumbnailStore.saveImage(bytes);
    if (!context.mounted) {
      await TagLibraryThumbnailStore.deleteOwned(saved);
      return;
    }
    ThumbnailCropResult? crop;
    await showThumbnailCropDialog(
      context: context,
      imagePath: saved,
      onConfirm: (result) => crop = result,
    );
    final result = crop;
    if (result == null) {
      await TagLibraryThumbnailStore.deleteOwned(saved);
      return;
    }
    final current = _library.getEntry(entry.id) ?? entry;
    await _library.updateEntry(
      current.copyWith(
        thumbnail: saved,
        thumbnailOffsetX: result.offsetX,
        thumbnailOffsetY: result.offsetY,
        thumbnailScale: result.scale,
        updatedAt: DateTime.now(),
      ),
    );
    if (current.thumbnail != saved) {
      await TagLibraryThumbnailStore.deleteOwned(current.thumbnail);
    }
  }

  Future<void> removePreview(TagLibraryEntry entry) async {
    final current = _library.getEntry(entry.id) ?? entry;
    if (!current.hasThumbnail) return;
    await _library.updateEntry(
      current.copyWith(
        thumbnail: null,
        thumbnailOffsetX: 0,
        thumbnailOffsetY: 0,
        thumbnailScale: 1,
        updatedAt: DateTime.now(),
      ),
    );
    await TagLibraryThumbnailStore.deleteOwned(current.thumbnail);
  }

  // ==================== 分组与页面 ====================

  void showSort() {
    final l10n = context.l10n;
    showSortOptionsSheet<TagLibrarySortBy>(
      context: context,
      title: l10n.tagLibrary_sortTitle,
      specOf: (ref) {
        final state = ref.watch(tagLibraryPageNotifierProvider);
        final notifier = ref.read(tagLibraryPageNotifierProvider.notifier);
        return SortOptionsSpec(
          options: [
            SortOption(
              value: TagLibrarySortBy.order,
              title: l10n.tagLibrary_sortCustom,
              subtitle: l10n.tagLibrary_sortCustomHint,
            ),
            SortOption(
              value: TagLibrarySortBy.frequent,
              title: l10n.tagLibrary_sortFrequent,
              subtitle: l10n.tagLibrary_sortFrequentHint,
            ),
            SortOption(
              value: TagLibrarySortBy.recentlyUsed,
              title: l10n.tagLibrary_sortRecent,
              subtitle: l10n.tagLibrary_sortRecentHint,
            ),
            SortOption(
              value: TagLibrarySortBy.name,
              title: l10n.tagLibrary_sortName,
              subtitle: l10n.tagLibrary_sortNameHint,
            ),
          ],
          selected: state.sortBy,
          onSelected: notifier.setSortBy,
          toggle: SortToggle(
            key: const ValueKey('tag-library-favorites-first'),
            title: l10n.tagLibrary_favoritesFirst,
            subtitle: l10n.tagLibrary_favoritesFirstHint,
            value: state.favoritesFirst,
            onChanged: notifier.setFavoritesFirst,
          ),
        );
      },
    );
  }

  void showGroupManager() => showTagLibraryGroupManager(
    context: context,
    onDelete: confirmDeleteGroup,
  );

  Future<void> confirmDeleteGroup(String categoryId) async {
    final state = ref.read(tagLibraryPageNotifierProvider);
    final category = state.categories
        .where((c) => c.id == categoryId)
        .firstOrNull;
    if (category == null) return;
    final l10n = context.l10n;
    final confirmed = await ThemedConfirmDialog.show(
      context: context,
      title: l10n.tagLibrary_deleteCategoryTitle,
      content: l10n.tagLibrary_deleteCategoryConfirm(
        category.displayName,
        state.getCategoryEntryCount(categoryId).toString(),
      ),
      confirmText: l10n.common_delete,
      cancelText: l10n.common_cancel,
      type: ThemedConfirmDialogType.danger,
      icon: Icons.delete_outline_rounded,
    );
    if (!confirmed) return;
    await _library.deleteCategory(categoryId);
  }

  void import() => ImportDialog.show(context);

  void export() {
    final state = ref.read(tagLibraryPageNotifierProvider);
    ExportDialog.show(
      context,
      entries: state.entries,
      categories: state.categories,
    );
  }

  /// Right-click on an entry with a mouse.
  Future<void> showEntryMenu(TagLibraryEntry entry, Offset position) async {
    final l10n = context.l10n;
    final error = Theme.of(context).colorScheme.error;
    PopupMenuItem<_EntryMenuAction> item(
      _EntryMenuAction value,
      IconData icon,
      String label, {
      Color? color,
    }) => PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(color: color)),
        ],
      ),
    );
    final action = await showMenu<_EntryMenuAction>(
      context: context,
      position: contextMenuAnchorAt(context, position),
      items: [
        item(
          _EntryMenuAction.send,
          Icons.send_rounded,
          l10n.tagLibrary_sendToPrompt,
        ),
        item(_EntryMenuAction.edit, Icons.edit_outlined, l10n.common_edit),
        item(
          _EntryMenuAction.favorite,
          entry.isFavorite
              ? Icons.favorite_rounded
              : Icons.favorite_border_rounded,
          entry.isFavorite ? l10n.common_unfavorite : l10n.common_favorite,
        ),
        item(
          _EntryMenuAction.move,
          Icons.drive_file_move_outline,
          l10n.tagLibrary_moveToCategoryTitle,
        ),
        item(
          _EntryMenuAction.copy,
          Icons.content_copy_rounded,
          l10n.tagLibrary_copyContent,
        ),
        item(
          _EntryMenuAction.delete,
          Icons.delete_outline_rounded,
          l10n.common_delete,
          color: error,
        ),
      ],
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case _EntryMenuAction.send:
        await sendToPrompt([entry]);
      case _EntryMenuAction.edit:
        edit(entry);
      case _EntryMenuAction.favorite:
        await _library.toggleFavorite(entry.id);
      case _EntryMenuAction.move:
        await moveToGroup([entry.id]);
      case _EntryMenuAction.copy:
        await copy([entry]);
      case _EntryMenuAction.delete:
        await confirmDelete([entry]);
    }
  }
}
