import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/utils/localization_extension.dart';
import '../../../../../data/models/character/character_prompt.dart';
import '../../../../providers/character_library_provider.dart';
import '../../../../providers/character_prompt_provider.dart';
import '../../../../providers/character_workspace_provider.dart';
import '../../../../providers/generation/generation_params_selectors.dart';
import '../../../../providers/image_generation_provider.dart';
import '../../../../themes/core/layered_surface_style.dart';
import '../../../../themes/theme_extension.dart';
import '../../../../widgets/character/character_library_import.dart';
import '../../../../services/character_library_transfer.dart';
import '../../../../widgets/character/character_marker.dart';
import '../../../character_library/character_library_picker.dart';
import '../../widgets/prompt_group_undo_bar.dart';
import 'character_placement_sheet.dart';
import 'character_workspace_row.dart';

/// The characters in place of the main prompt on the phone prompt page.
///
/// Every character is one line; one at a time opens in place for editing, so
/// several characters fit on the screen without opening another page. The
/// positive/negative switch of the prompt page picks the side shown.
class CharacterWorkspace extends ConsumerStatefulWidget {
  const CharacterWorkspace({super.key, required this.negative});

  final bool negative;

  @override
  ConsumerState<CharacterWorkspace> createState() => _CharacterWorkspaceState();
}

/// A character deletion that can still be undone.
typedef _RemovedCharacter = ({CharacterPrompt character, int index});

class _CharacterWorkspaceState extends ConsumerState<CharacterWorkspace> {
  static const Duration _undoDuration = Duration(seconds: 5);

  _RemovedCharacter? _removed;
  Timer? _undoTimer;

  @override
  void dispose() {
    _undoTimer?.cancel();
    super.dispose();
  }

  CharacterPromptNotifier get _notifier =>
      ref.read(characterPromptNotifierProvider.notifier);

  void _remove(CharacterPrompt character) {
    final characters = ref.read(characterPromptNotifierProvider).characters;
    final index = characters.indexWhere((item) => item.id == character.id);
    if (index < 0) return;
    _notifier.removeCharacter(character.id);
    _undoTimer?.cancel();
    _undoTimer = Timer(_undoDuration, _dismissUndo);
    setState(() => _removed = (character: character, index: index));
  }

  void _dismissUndo() {
    _undoTimer?.cancel();
    _undoTimer = null;
    if (mounted && _removed != null) setState(() => _removed = null);
  }

  void _undoRemove() {
    final removed = _removed;
    _dismissUndo();
    if (removed == null) return;
    final current = ref.read(characterPromptNotifierProvider).characters;
    if (current.any((item) => item.id == removed.character.id)) return;
    _notifier.replaceAll([
      ...current.take(removed.index),
      removed.character,
      ...current.skip(removed.index),
    ]);
  }

  void _added(String id) {
    ref.read(characterWorkspaceAddingProvider.notifier).state = false;
    ref.read(characterWorkspaceExpandedProvider.notifier).state = id;
  }

  void _add(CharacterGender gender) {
    final before = ref.read(characterPromptNotifierProvider).characters.length;
    _notifier.addCharacter(
      gender,
      name: context.l10n.character_number(before + 1),
    );
    final characters = ref.read(characterPromptNotifierProvider).characters;
    if (characters.length > before) _added(characters.last.id);
  }

  Future<void> _addFromLibrary() async {
    final id = await addCharacterFromLibrary(context, ref);
    if (id != null && mounted) _added(id);
  }

  Future<void> _addFromCharacterLibrary() async {
    final before = ref.read(characterPromptNotifierProvider).characters.length;
    await showCharacterLibraryPicker(context, ref);
    if (!mounted) return;
    final characters = ref.read(characterPromptNotifierProvider).characters;
    if (characters.length > before) _added(characters.last.id);
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(characterPromptNotifierProvider);
    final expandedId = ref.watch(characterWorkspaceExpandedProvider);
    final adding = ref.watch(characterWorkspaceAddingProvider);
    final limitReached = ref.watch(characterLimitReachedProvider);
    final dimensions = ref.watch(
      generationParamsNotifierProvider.select(selectPreviewDimensionsViewData),
    );
    final characters = config.characters;
    final manual = !config.globalAiChoice;
    final removed = _removed;
    // Rows mark characters from the library, and edits not saved back.
    ref.watch(characterLibraryProvider);
    final library = CharacterLibraryTransfer(ref.read);

    final list = ReorderableListView.builder(
      key: const ValueKey('character-workspace'),
      buildDefaultDragHandles: false,
      padding: EdgeInsets.only(bottom: removed == null ? 12 : 76),
      header: _TopLine(
        manual: manual,
        count: characters.length,
        included: characters.where((item) => item.enabled).length,
        // Manual now: hand the positions back to AI, and the other way.
        onToggleManual: () => _notifier.setGlobalAiChoice(manual),
        onPlace: () => showCharacterPlacement(context),
      ),
      footer: _AddCharacter(
        adding: adding && !limitReached,
        limitReached: limitReached,
        limitText: context.l10n.character_limitReached(
          _notifier.characterLimit.toString(),
        ),
        onStart: () =>
            ref.read(characterWorkspaceAddingProvider.notifier).state = true,
        onCancel: () =>
            ref.read(characterWorkspaceAddingProvider.notifier).state = false,
        onGender: _add,
        onLibrary: _addFromLibrary,
        onCharacterLibrary: _addFromCharacterLibrary,
      ),
      proxyDecorator: (child, index, animation) => Material(
        elevation: 6,
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(
          Theme.of(context).appTheme.cardRadius,
        ),
        child: child,
      ),
      onReorderItem: (oldIndex, newIndex) {
        final ids = [for (final item in characters) item.id];
        ids.insert(newIndex, ids.removeAt(oldIndex));
        _notifier.setCharacterOrder(ids);
      },
      itemCount: characters.length,
      itemBuilder: (context, index) {
        final character = characters[index];
        final position = config.resolvePosition(character);
        return CharacterWorkspaceRow(
          key: ValueKey(character.id),
          index: index,
          character: character,
          colors: CharacterMarkerPalette.of(characters, character),
          expanded: character.id == expandedId,
          negative: widget.negative,
          position: manual && character.enabled
              ? Offset(position.column, position.row)
              : null,
          aspectRatio: dimensions.width / dimensions.height,
          fromLibrary: library.linkedEntryId(character.id) != null,
          unsavedLibraryChanges: library.hasUnsavedChanges(character),
          onToggleExpanded: () =>
              ref.read(characterWorkspaceExpandedProvider.notifier).state =
                  character.id == expandedId ? null : character.id,
          onToggleEnabled: () => _notifier.toggleCharacterEnabled(character.id),
          onDelete: () => _remove(character),
        );
      },
    );

    return Stack(
      children: [
        Positioned.fill(child: list),
        Positioned(
          left: 4,
          right: 4,
          bottom: 12,
          child: removed == null
              ? const SizedBox.shrink()
              : PromptGroupUndoBar(
                  key: const ValueKey('character-workspace-undo'),
                  message: context.l10n.characterPanel_deleted(
                    removed.character.name,
                  ),
                  onUndo: _undoRemove,
                ),
        ),
      ],
    );
  }
}

/// Who places the characters, the way into placing them, and the counts.
class _TopLine extends StatelessWidget {
  const _TopLine({
    required this.manual,
    required this.count,
    required this.included,
    required this.onToggleManual,
    required this.onPlace,
  });

  final bool manual;
  final int count;
  final int included;
  final VoidCallback onToggleManual;
  final VoidCallback onPlace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = context.l10n;
    final radius = BorderRadius.circular(theme.appTheme.controlRadius);
    Widget chip({
      required Key key,
      required Widget child,
      required VoidCallback onTap,
      required bool accent,
    }) => Material(
      color: accent
          ? colors.primaryContainer.withValues(alpha: 0.55)
          : controlSurfaceColor(colors),
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: key,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            // Wraps instead of overflowing with very large text.
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [Flexible(child: child)],
            ),
          ),
        ),
      ),
    );
    final labelStyle = theme.textTheme.labelLarge?.copyWith(
      color: manual ? colors.onPrimaryContainer : colors.onSurface,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          chip(
            key: const ValueKey('character-workspace-position-mode'),
            accent: manual,
            onTap: onToggleManual,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${l10n.characterPanel_position}  ',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  TextSpan(
                    text: manual
                        ? l10n.characterPanel_positionManual
                        : l10n.characterPanel_positionAi,
                  ),
                  const TextSpan(text: '  ⇄'),
                ],
              ),
              style: labelStyle,
            ),
          ),
          if (manual)
            chip(
              key: const ValueKey('character-workspace-place'),
              accent: true,
              onTap: onPlace,
              child: Text(
                '${l10n.characterPanel_place} ›',
                style: labelStyle?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              l10n.characterWorkspace_count(count, included),
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The add row at the end of the list, opening into the gender and library
/// choices in place.
class _AddCharacter extends StatelessWidget {
  const _AddCharacter({
    required this.adding,
    required this.limitReached,
    required this.limitText,
    required this.onStart,
    required this.onCancel,
    required this.onGender,
    required this.onLibrary,
    required this.onCharacterLibrary,
  });

  final bool adding;
  final bool limitReached;
  final String limitText;
  final VoidCallback onStart;
  final VoidCallback onCancel;
  final ValueChanged<CharacterGender> onGender;
  final VoidCallback onLibrary;
  final VoidCallback onCharacterLibrary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = context.l10n;
    final radius = BorderRadius.circular(theme.appTheme.cardRadius);
    if (!adding) {
      return Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Material(
          color: colors.primaryContainer.withValues(
            alpha: limitReached ? 0.25 : 0.55,
          ),
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const ValueKey('character-workspace-add'),
            onTap: limitReached ? null : onStart,
            child: SizedBox(
              height: 48,
              child: Center(
                child: Text(
                  limitReached ? limitText : '＋ ${l10n.character_addCharacter}',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colors.onPrimaryContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    final options = [
      (CharacterGender.female, l10n.characterEditor_addFemale),
      (CharacterGender.male, l10n.characterEditor_addMale),
      (CharacterGender.other, l10n.characterEditor_addOther),
    ];
    Widget option({
      required Key key,
      required Widget child,
      required VoidCallback onTap,
    }) => Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(theme.appTheme.controlRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: key,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(mainAxisSize: MainAxisSize.min, children: [child]),
          ),
        ),
      ),
    );
    return Container(
      key: const ValueKey('character-workspace-add-picker'),
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.55),
        borderRadius: radius,
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          option(
            key: const ValueKey('character-workspace-add-character-library'),
            onTap: onCharacterLibrary,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.people_outline_rounded,
                  size: 20,
                  color: colors.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  l10n.characterLibrary_title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          for (final (gender, label) in options)
            option(
              key: ValueKey('character-workspace-add-${gender.name}'),
              onTap: () => onGender(gender),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CharacterMarkerDisc(
                    colors: CharacterMarkerPalette.forGender(gender),
                    diameter: 22,
                  ),
                  const SizedBox(width: 6),
                  Text(label, style: theme.textTheme.labelLarge),
                ],
              ),
            ),
          option(
            key: const ValueKey('character-workspace-add-library'),
            onTap: onLibrary,
            child: Text(
              l10n.characterEditor_addFromLibrary,
              style: theme.textTheme.labelLarge,
            ),
          ),
          IconButton(
            key: const ValueKey('character-workspace-add-cancel'),
            onPressed: onCancel,
            tooltip: MaterialLocalizations.of(context).cancelButtonLabel,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}
