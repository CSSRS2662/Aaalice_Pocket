import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/localization_extension.dart';
import '../../../data/models/character/character_library_entry.dart';
import '../../adaptive/adaptive_presenter.dart';
import '../../adaptive/content_sized_adaptive_form.dart';
import '../../providers/character_library_provider.dart';
import '../../router/app_routes.dart';
import '../../widgets/character/character_marker.dart';
import '../dictionary/dictionary_tab_provider.dart';
import 'character_library_actions.dart';

/// Adds a character from the library to the character bar, the most
/// recently used first. "Manage" opens the library page.
Future<void> showCharacterLibraryPicker(
  BuildContext context,
  WidgetRef ref,
) async {
  final l10n = context.l10n;
  final picked = await AdaptivePresenter.showForm<_Pick>(
    context: context,
    title: l10n.characterLibrary_pickerTitle,
    builder: (context, scrollController) =>
        _PickerBody(scrollController: scrollController),
  );
  if (picked == null || !context.mounted) return;
  switch (picked) {
    case _PickEntry(:final entry):
      CharacterLibraryActions.addToPanel(context, ref, [entry]);
    case _PickManage():
      ref.read(dictionaryTabProvider.notifier).state = DictionaryTab.characters;
      context.go(AppRoutes.tagLibraryPage);
  }
}

sealed class _Pick {
  const _Pick();
}

class _PickEntry extends _Pick {
  const _PickEntry(this.entry);
  final CharacterLibraryEntry entry;
}

class _PickManage extends _Pick {
  const _PickManage();
}

class _PickerBody extends ConsumerStatefulWidget {
  const _PickerBody({required this.scrollController});

  final ScrollController? scrollController;

  @override
  ConsumerState<_PickerBody> createState() => _PickerBodyState();
}

class _PickerBodyState extends ConsumerState<_PickerBody> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final query = _query.trim().toLowerCase();
    DateTime at(CharacterLibraryEntry entry) =>
        entry.lastUsedAt ?? entry.updatedAt;
    final entries = [
      for (final entry in ref.watch(characterLibraryProvider))
        if (query.isEmpty ||
            entry.name.toLowerCase().contains(query) ||
            entry.prompt.toLowerCase().contains(query))
          entry,
    ]..sort((a, b) => at(b).compareTo(at(a)));
    return ContentSizedAdaptiveForm(
      scrollController: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      content: [
        TextField(
          key: const ValueKey('character_library_picker_search'),
          onChanged: (value) => setState(() => _query = value),
          decoration: InputDecoration(
            hintText: l10n.characterLibrary_searchHint,
            prefixIcon: const Icon(Icons.search_rounded),
            isDense: true,
            filled: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              ref.read(characterLibraryProvider).isEmpty
                  ? l10n.characterLibrary_emptyHint
                  : l10n.characterLibrary_noMatch,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        for (final entry in entries)
          ListTile(
            key: ValueKey('character_library_pick_${entry.id}'),
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            leading: CharacterMarkerDisc(
              colors: CharacterMarkerPalette.forGender(entry.gender),
              diameter: 32,
            ),
            title: Text(
              entry.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            subtitle: Text(
              entry.prompt,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => Navigator.of(context).pop(_PickEntry(entry)),
          ),
        const SizedBox(height: 4),
        TextButton.icon(
          key: const ValueKey('character_library_picker_manage'),
          onPressed: () => Navigator.of(context).pop(const _PickManage()),
          style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
          icon: const Icon(Icons.people_outline_rounded),
          label: Text(l10n.characterLibrary_manage),
        ),
      ],
    );
  }
}
