import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/constants/api_constants.dart';
import '../../../../../core/storage/local_storage_service.dart';
import '../../../../../core/utils/character_prompt_block_parser.dart';
import '../../../../../core/utils/localization_extension.dart';
import '../../../../../data/models/character/character_prompt.dart';
import '../../../../prompt_assistant/providers/prompt_assistant_history_provider.dart';
import '../../../../prompt_assistant/widgets/prompt_assistant_quick_settings.dart';
import '../../../../providers/character_prompt_provider.dart';
import '../../../../providers/character_workspace_provider.dart';
import '../../../../providers/image_generation_provider.dart';
import '../../../../themes/core/layered_surface_style.dart';
import '../../../../themes/theme_extension.dart';
import '../../../../widgets/character/add_to_library_dialog.dart';
import '../../../../widgets/character/character_marker.dart';
import '../../../../widgets/character/inline_character_editor.dart';
import '../../widgets/prompt_group_edit_sheet.dart';
import '../../widgets/prompt_group_editor.dart';
import 'character_prompt_groups.dart';

/// The open part of a character row: name and gender, its prompt of the
/// current side as section cards (or as one text in single mode), and the
/// library and delete actions.
///
/// It owns the character's sections, so the row keys it by character.
class CharacterWorkspaceEditor extends ConsumerStatefulWidget {
  const CharacterWorkspaceEditor({
    super.key,
    required this.character,
    required this.negative,
    required this.onDelete,
  });

  final CharacterPrompt character;
  final bool negative;
  final VoidCallback onDelete;

  @override
  ConsumerState<CharacterWorkspaceEditor> createState() =>
      _CharacterWorkspaceEditorState();
}

class _CharacterWorkspaceEditorState
    extends ConsumerState<CharacterWorkspaceEditor> {
  late final CharacterPromptNotifier _notifier = ref.read(
    characterPromptNotifierProvider.notifier,
  );
  late final CharacterPromptGroups _groups = CharacterPromptGroups.load(
    ref.read(localStorageServiceProvider),
    widget.character,
  );

  @override
  void dispose() {
    _groups.dispose();
    super.dispose();
  }

  CharacterPrompt? get _current => ref
      .read(characterPromptNotifierProvider)
      .findCharacterById(widget.character.id);

  String get _sessionId => widget.negative
      ? PromptHistorySessionIds.characterNegative(widget.character.id)
      : PromptHistorySessionIds.characterPrompt(widget.character.id);

  void _save(CharacterPrompt character) {
    final ids = {
      for (final item in ref.read(characterPromptNotifierProvider).characters)
        item.id,
    };
    _groups.save(character, liveIds: ids);
  }

  /// Writes the included sections back as the character's prompt.
  void _commit(bool negative) {
    final character = _current;
    if (character == null) return;
    final text = _groups.groupsFor(negative).effectiveText;
    final next = negative
        ? character.copyWith(negativePrompt: text)
        : character.copyWith(prompt: text);
    _notifier.updateCharacter(next);
    _save(next);
  }

  void _setGender(CharacterGender gender) {
    FocusManager.instance.primaryFocus?.unfocus();
    final character = _current;
    if (character == null) return;
    if (!ref.read(characterPromptsGroupedProvider)) {
      _notifier.updateCharacter(character.withGender(gender));
      return;
    }
    // The first included section starts the prompt, so its first tag is the
    // one that sets the gender; rewriting it keeps the other sections.
    _groups.align(character);
    final sections = _groups.positive.sections;
    final first =
        sections
            .where((s) => s.enabled && s.controller.text.trim().isNotEmpty)
            .firstOrNull ??
        sections.first;
    first.controller.text = CharacterPrompt(
      id: character.id,
      name: character.name,
      prompt: first.controller.text,
    ).withGender(gender).prompt;
    _groups.positive.setEnabled(first.id, true);
    _commit(false);
    final current = _current;
    if (current != null) {
      _notifier.updateCharacter(current.copyWith(gender: gender));
    }
  }

  /// Single mode edits the whole prompt of the side as one section.
  Future<void> _openWhole() {
    final negative = widget.negative;
    final character = _current;
    if (character == null) return Future.value();
    final prompt = negative ? character.negativePrompt : character.prompt;
    final groups = _groups.groupsFor(negative);
    if (groups.sections.length != 1 || !groups.matchesPrompt(prompt)) {
      groups.replaceWith(prompt);
    }
    FocusManager.instance.primaryFocus?.unfocus();
    return showPromptGroupEditSheet(
      context,
      groups: groups,
      sectionId: groups.sections.first.id,
      negative: negative,
      numericEmphasisEnabled: _numericEmphasis,
      modeSessionId: _sessionId,
      excludeFixedTags: false,
      callbacks: PromptGroupEditCallbacks(
        onChanged: () => _commit(negative),
        onToggleEnabled: (id) {
          final section = groups.sectionById(id);
          if (section == null) return;
          groups.setEnabled(id, !section.enabled);
          _commit(negative);
        },
        onDuplicate: (id) {
          if (groups.duplicate(id) != null) _commit(negative);
        },
        onMoveToFront: (id) {
          groups.move(id, 0);
          _commit(negative);
        },
        onDelete: (id) {
          if (groups.remove(id) != null) _commit(negative);
        },
        onOpenAssistantSettings: () =>
            PromptAssistantQuickSettings.show(context),
      ),
    );
  }

  bool get _numericEmphasis =>
      ImageModels.isV4Model(ref.read(generationParamsNotifierProvider).model);

  @override
  Widget build(BuildContext context) {
    final character = widget.character;
    final negative = widget.negative;
    // A prompt changed elsewhere (agent, import) regroups into one section.
    ref.listen(
      characterPromptNotifierProvider.select(
        (config) => config.findCharacterById(character.id),
      ),
      (_, next) {
        if (next != null) _groups.align(next);
      },
    );
    final grouped = ref.watch(characterPromptsGroupedProvider);
    final highlight = ref.watch(highlightEmphasisSettingsProvider);
    final numericEmphasis = ImageModels.isV4Model(
      ref.watch(
        generationParamsNotifierProvider.select((params) => params.model),
      ),
    );
    for (final groups in [_groups.positive, _groups.negative]) {
      groups.configureHighlighting(
        enabled: highlight,
        numericEmphasisEnabled: numericEmphasis,
      );
    }
    final prompt = negative ? character.negativePrompt : character.prompt;

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _IdentityLine(character: character, onGender: _setGender),
          const SizedBox(height: 8),
          if (grouped)
            PromptGroupBoard(
              groups: _groups.groupsFor(negative),
              negative: negative,
              gridKey: ValueKey(
                negative
                    ? 'character_negative_prompt_group_grid'
                    : 'character_positive_prompt_group_grid',
              ),
              listKey: ValueKey(
                negative
                    ? 'character_negative_prompt_groups'
                    : 'character_positive_prompt_groups',
              ),
              numericEmphasisEnabled: numericEmphasis,
              summaryLines: 1,
              onCommit: _commit,
              onOpenAssistantSettings: () =>
                  PromptAssistantQuickSettings.show(context),
              modeSessionId: _sessionId,
              excludeFixedTags: false,
            )
          else
            _WholePrompt(
              key: const ValueKey('character-workspace-whole'),
              text: prompt,
              negative: negative,
              onTap: _openWhole,
            ),
          const SizedBox(height: 4),
          _Actions(
            onSaveToLibrary: () => AddToLibraryDialog.show(
              context,
              name: character.name,
              content: CharacterPromptBlockParser.compose(
                positivePrompt: character.prompt,
                negativePrompt: character.negativePrompt,
              ),
            ),
            onDelete: widget.onDelete,
          ),
        ],
      ),
    );
  }
}

/// The name, typed in place and saved as it changes, beside three gender
/// buttons carrying the gender symbols.
class _IdentityLine extends StatelessWidget {
  const _IdentityLine({required this.character, required this.onGender});

  final CharacterPrompt character;
  final ValueChanged<CharacterGender> onGender;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final options = [
      (CharacterGender.female, l10n.characterEditor_genderFemale),
      (CharacterGender.male, l10n.characterEditor_genderMale),
      (CharacterGender.other, l10n.characterEditor_genderOther),
    ];
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 44,
            alignment: AlignmentDirectional.centerStart,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: controlSurfaceColor(theme.colorScheme),
              borderRadius: BorderRadius.circular(theme.appTheme.controlRadius),
            ),
            child: CharacterNameField(
              key: ValueKey('character-workspace-name-${character.id}'),
              character: character,
              commitWhileTyping: true,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        for (final (gender, label) in options) ...[
          _GenderButton(
            key: ValueKey('character-workspace-gender-${gender.name}'),
            gender: gender,
            label: label,
            selected: character.effectiveGender == gender,
            onTap: () => onGender(gender),
          ),
          if (gender != CharacterGender.other) const SizedBox(width: 4),
        ],
      ],
    );
  }
}

class _GenderButton extends StatelessWidget {
  const _GenderButton({
    super.key,
    required this.gender,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final CharacterGender gender;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final radius = BorderRadius.circular(theme.appTheme.controlRadius);
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        excludeSemantics: true,
        child: Material(
          color: selected
              ? colors.primaryContainer.withValues(alpha: 0.6)
              : controlSurfaceColor(colors),
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: selected
                ? BorderSide(color: colors.primary, width: 2)
                : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox.square(
              dimension: 44,
              child: Center(
                child: Opacity(
                  opacity: selected ? 1 : 0.45,
                  child: CharacterMarkerDisc(
                    colors: CharacterMarkerPalette.forGender(gender),
                    diameter: 24,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Single mode: the whole prompt of the side, opened in the section editor.
class _WholePrompt extends StatelessWidget {
  const _WholePrompt({
    super.key,
    required this.text,
    required this.negative,
    required this.onTap,
  });

  final String text;
  final bool negative;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = context.l10n;
    final empty = text.trim().isEmpty;
    return Material(
      color: sectionSurfaceColor(colors),
      borderRadius: BorderRadius.circular(theme.appTheme.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Align(
              alignment: AlignmentDirectional.topStart,
              child: Text(
                empty
                    ? (negative
                          ? l10n.characterEditor_negativePromptHint
                          : l10n.characterEditor_promptHint)
                    : text,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 13,
                  height: 1.45,
                  color: empty ? colors.onSurfaceVariant : colors.onSurface,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.onSaveToLibrary, required this.onDelete});

  final VoidCallback onSaveToLibrary;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final style = TextButton.styleFrom(
      minimumSize: const Size(0, 44),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      visualDensity: VisualDensity.compact,
    );
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 4,
      children: [
        TextButton.icon(
          key: const ValueKey('character-workspace-save-library'),
          onPressed: onSaveToLibrary,
          style: style,
          icon: const Icon(Icons.library_add_outlined, size: 18),
          label: Text(l10n.tagLibrary_addToLibrary),
        ),
        TextButton.icon(
          key: const ValueKey('character-workspace-delete'),
          onPressed: onDelete,
          style: style.copyWith(
            foregroundColor: WidgetStatePropertyAll(colors.error),
          ),
          icon: const Icon(Icons.delete_outline_rounded, size: 18),
          label: Text(l10n.characterPanel_deleteCharacter),
        ),
      ],
    );
  }
}
