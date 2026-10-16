import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/localization_extension.dart';
import '../../../data/models/character/character_library_entry.dart';
import '../../../data/models/character/character_prompt.dart';
import '../../../data/models/gallery/prompt_group_snapshot.dart';
import '../../adaptive/adaptive_presenter.dart';
import '../../adaptive/content_sized_adaptive_form.dart';
import '../../providers/character_library_provider.dart';
import '../../services/character_library_transfer.dart';
import '../../widgets/common/app_toast.dart';
import '../../widgets/common/themed_confirm_dialog.dart';
import 'character_library_editor_screen.dart';

/// Commands shared by the library list, its rows and the editor page.
abstract final class CharacterLibraryActions {
  static Future<void> openEditor(BuildContext context, String entryId) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CharacterLibraryEditorScreen(entryId: entryId),
        ),
      );

  /// Adds an empty character of [gender] and opens it.
  static Future<void> create(
    BuildContext context,
    WidgetRef ref, {
    CharacterGender gender = CharacterGender.female,
  }) {
    final l10n = context.l10n;
    final entry = CharacterLibraryEntry.create(
      name: l10n.characterLibrary_newName,
      gender: gender,
      positiveSections: [
        PromptGroupSectionSnapshot(
          id: '${DateTime.now().microsecondsSinceEpoch}',
          text: switch (gender) {
            CharacterGender.female => 'girl',
            CharacterGender.male => 'boy',
            CharacterGender.other => '',
          },
        ),
      ],
    );
    ref.read(characterLibraryProvider.notifier).add(entry);
    return openEditor(context, entry.id);
  }

  /// Adds [entries] to the character bar and says how many went in.
  static void addToPanel(
    BuildContext context,
    WidgetRef ref,
    List<CharacterLibraryEntry> entries,
  ) {
    if (entries.isEmpty) return;
    final l10n = context.l10n;
    final added = CharacterLibraryTransfer(ref.read).addToPanel(entries);
    if (added < entries.length) {
      AppToast.warning(
        context,
        l10n.characterLibrary_limitReached(entries.length - added),
      );
    } else if (added == 1) {
      AppToast.success(
        context,
        l10n.characterLibrary_added(entries.first.name),
      );
    } else {
      AppToast.success(context, l10n.characterLibrary_addedMany(added));
    }
  }

  static void duplicate(
    BuildContext context,
    WidgetRef ref,
    CharacterLibraryEntry entry,
  ) {
    final copy = ref
        .read(characterLibraryProvider.notifier)
        .duplicate(
          entry.id,
          name: context.l10n.characterLibrary_copyName(entry.name),
        );
    if (copy != null) AppToast.success(context, copy.name);
  }

  /// Asks where a changed character goes: over its library entry (false)
  /// or into a new one (true); null when dismissed.
  static Future<bool?> chooseSaveTarget(
    BuildContext context, {
    required String name,
  }) {
    final l10n = context.l10n;
    return AdaptivePresenter.showForm<bool>(
      context: context,
      title: l10n.characterLibrary_saveToLibrary,
      builder: (context, scrollController) => ContentSizedAdaptiveForm(
        scrollController: scrollController,
        padding: const EdgeInsets.symmetric(vertical: 8),
        content: [
          ListTile(
            key: const ValueKey('character_library_save_update'),
            leading: const Icon(Icons.sync_rounded),
            title: Text(l10n.characterLibrary_updateEntry(name)),
            subtitle: Text(l10n.characterLibrary_updateEntryHint),
            onTap: () => Navigator.of(context).pop(false),
          ),
          ListTile(
            key: const ValueKey('character_library_save_new'),
            leading: const Icon(Icons.add_circle_outline_rounded),
            title: Text(l10n.characterLibrary_saveAsNew),
            subtitle: Text(l10n.characterLibrary_saveAsNewHint(name)),
            onTap: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
  }

  /// Asks first; returns whether the entry was deleted.
  static Future<bool> delete(
    BuildContext context,
    WidgetRef ref,
    CharacterLibraryEntry entry,
  ) async {
    final confirmed = await ThemedConfirmDialog.showDelete(
      context: context,
      itemName: entry.name,
      content: context.l10n.characterLibrary_deleteConfirm(entry.name),
    );
    if (!confirmed) return false;
    ref.read(characterLibraryProvider.notifier).remove(entry.id);
    return true;
  }
}
