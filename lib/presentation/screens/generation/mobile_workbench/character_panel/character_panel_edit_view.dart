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
import '../../../../providers/generation/generation_params_selectors.dart';
import '../../../../providers/image_generation_provider.dart';
import '../../../../themes/core/layered_surface_style.dart';
import '../../../../themes/theme_extension.dart';
import '../../../../widgets/character/add_to_library_dialog.dart';
import '../../../../widgets/character/character_marker.dart';
import '../../../../widgets/character/inline_character_editor.dart';
import '../../../../widgets/common/horizontal_segmented_control.dart';
import '../../widgets/prompt_editor_mode_switch.dart';
import '../../widgets/prompt_group_controller.dart';
import '../../widgets/prompt_group_editor.dart';
import 'character_panel_header.dart';
import 'character_place_canvas.dart';
import 'character_prompt_groups.dart';

/// Edits one character inside the panel: name, gender, whether it takes part,
/// its prompts and where it stands.
class CharacterPanelEditView extends ConsumerWidget {
  const CharacterPanelEditView({
    super.key,
    required this.characterId,
    required this.onBack,
    required this.onOpenEdit,
    required this.onOpenPlace,
    required this.onDelete,
  });

  final String characterId;
  final VoidCallback onBack;
  final ValueChanged<String> onOpenEdit;
  final VoidCallback onOpenPlace;
  final ValueChanged<CharacterPrompt> onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final config = ref.watch(characterPromptNotifierProvider);
    final characters = config.characters;
    final index = characters.indexWhere((item) => item.id == characterId);
    if (index < 0) return const SizedBox.shrink();
    final character = characters[index];
    final notifier = ref.read(characterPromptNotifierProvider.notifier);
    final subtitle = [
      l10n.characterPanel_editIndex(index + 1, characters.length),
      if (!character.enabled) l10n.characterPanel_notIncluded,
    ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CharacterPanelHeader(
          onBack: onBack,
          title: CharacterNameField(
            key: ValueKey('character-panel-name-${character.id}'),
            character: character,
            commitWhileTyping: true,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: subtitle,
          trailing: [
            _IncludeSwitch(
              character: character,
              onChanged: (_) => notifier.toggleCharacterEnabled(character.id),
            ),
            IconButton(
              key: const ValueKey('character-panel-previous'),
              onPressed: index > 0
                  ? () => onOpenEdit(characters[index - 1].id)
                  : null,
              tooltip: l10n.characterPanel_previous,
              icon: const Icon(Icons.keyboard_arrow_up_rounded),
            ),
            IconButton(
              key: const ValueKey('character-panel-next'),
              onPressed: index < characters.length - 1
                  ? () => onOpenEdit(characters[index + 1].id)
                  : null,
              tooltip: l10n.characterPanel_next,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
            ),
          ],
        ),
        Expanded(
          child: _EditBody(
            key: ValueKey('character-panel-body-${character.id}'),
            character: character,
            config: config,
            onOpenPlace: onOpenPlace,
            onDelete: onDelete,
          ),
        ),
      ],
    );
  }
}

/// Everything below the header for one character. It owns the character's
/// prompt sections, so it is keyed by character and rebuilt when switching.
class _EditBody extends ConsumerStatefulWidget {
  const _EditBody({
    super.key,
    required this.character,
    required this.config,
    required this.onOpenPlace,
    required this.onDelete,
  });

  final CharacterPrompt character;
  final CharacterPromptConfig config;
  final VoidCallback onOpenPlace;
  final ValueChanged<CharacterPrompt> onDelete;

  @override
  ConsumerState<_EditBody> createState() => _EditBodyState();
}

class _EditBodyState extends ConsumerState<_EditBody> {
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

  void _setMode(PromptEditorMode mode) {
    final character = _current;
    if (character == null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      if (mode == PromptEditorMode.grouped) _groups.align(character);
      _groups.grouped = mode == PromptEditorMode.grouped;
    });
    _save(character);
  }

  void _setGender(CharacterGender gender) {
    // The text editor only takes outside changes while unfocused.
    FocusManager.instance.primaryFocus?.unfocus();
    final character = _current;
    if (character == null) return;
    if (!_groups.grouped) {
      _notifier.updateCharacter(character.withGender(gender));
      return;
    }
    // The first included section starts the prompt, so its first tag is the
    // one that sets the gender; rewriting it keeps the other sections.
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

  Widget _groupedBody(BuildContext context, bool negative) {
    final id = widget.character.id;
    return PromptGroupBoard(
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
      numericEmphasisEnabled: ImageModels.isV4Model(
        ref.read(generationParamsNotifierProvider).model,
      ),
      onCommit: _commit,
      onOpenAssistantSettings: () => PromptAssistantQuickSettings.show(context),
      modeSessionId: negative
          ? PromptHistorySessionIds.characterNegative(id)
          : PromptHistorySessionIds.characterPrompt(id),
      excludeFixedTags: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final character = widget.character;
    // A prompt changed elsewhere (agent, import) regroups into one section.
    ref.listen(
      characterPromptNotifierProvider.select(
        (config) => config.findCharacterById(character.id),
      ),
      (_, next) {
        if (next != null && _groups.grouped) _groups.align(next);
      },
    );
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
    final grouped = _groups.grouped;
    // The keyboard needs the room; the pinned part comes back once it closes.
    final typing = MediaQuery.viewInsetsOf(context).bottom > 0;
    final editor = SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _GenderRow(character: character, onGender: _setGender),
          const SizedBox(height: 12),
          CharacterPromptEditor(
            key: ValueKey('character-panel-editor-${character.id}'),
            character: character,
            autofocus: false,
            modeSwitch: PromptEditorModeButton(
              buttonKey: const ValueKey('character-panel-editor-mode'),
              grouped: grouped,
              iconOnly: true,
              onSelected: _setMode,
            ),
            groupedBody: grouped ? _groupedBody : null,
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: editor),
        if (!typing)
          Padding(
            key: const ValueKey('character-panel-edit-footer'),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _PositionCard(
                  config: widget.config,
                  character: character,
                  onPlace: widget.onOpenPlace,
                ),
                const SizedBox(height: 4),
                _EditActions(
                  onSaveToLibrary: () => AddToLibraryDialog.show(
                    context,
                    name: character.name,
                    content: CharacterPromptBlockParser.compose(
                      positivePrompt: character.prompt,
                      negativePrompt: character.negativePrompt,
                    ),
                  ),
                  onDelete: () => widget.onDelete(character),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Whether the character takes part in the generation, as a bare switch in
/// the header; its name says what it is to screen readers and on hover.
class _IncludeSwitch extends StatelessWidget {
  const _IncludeSwitch({required this.character, required this.onChanged});

  final CharacterPrompt character;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Tooltip(
      message: character.enabled
          ? l10n.characterPanel_leaveOut(character.name)
          : l10n.characterPanel_include(character.name),
      child: Semantics(
        label: l10n.characterPanel_includeSwitch,
        child: Switch(
          key: const ValueKey('character-panel-include'),
          value: character.enabled,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _GenderRow extends StatelessWidget {
  const _GenderRow({required this.character, required this.onGender});

  final CharacterPrompt character;
  final ValueChanged<CharacterGender> onGender;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final options = [
      (CharacterGender.female, l10n.characterEditor_addFemale),
      (CharacterGender.male, l10n.characterEditor_addMale),
      (CharacterGender.other, l10n.characterEditor_addOther),
    ];
    return Semantics(
      label: l10n.characterPanel_gender,
      child: HorizontalSegmentedControl(
        child: SegmentedButton<CharacterGender>(
          key: const ValueKey('character-panel-gender'),
          segments: [
            for (final (gender, label) in options)
              ButtonSegment(
                value: gender,
                icon: CharacterMarkerDisc(
                  colors: CharacterMarkerPalette.forGender(gender),
                  diameter: 20,
                ),
                label: Text(label),
              ),
          ],
          selected: {character.effectiveGender},
          showSelectedIcon: false,
          onSelectionChanged: (selection) => onGender(selection.single),
        ),
      ),
    );
  }
}

class _PositionCard extends ConsumerWidget {
  const _PositionCard({
    required this.config,
    required this.character,
    required this.onPlace,
  });

  final CharacterPromptConfig config;
  final CharacterPrompt character;
  final VoidCallback onPlace;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final dimensions = ref.watch(
      generationParamsNotifierProvider.select(selectPreviewDimensionsViewData),
    );
    final position = config.resolvePosition(character);
    final placed = character.enabled && !config.globalAiChoice;
    final description = !character.enabled
        ? l10n.characterPanel_positionNotIncluded
        : config.globalAiChoice
        ? l10n.characterPanel_positionAiValue
        : l10n.characterPanel_positionValue(
            characterPositionCell(position.column, position.row),
            (position.column * 100).round(),
            (position.row * 100).round(),
          );
    return Material(
      color: sectionSurfaceColor(theme.colorScheme),
      borderRadius: BorderRadius.circular(theme.appTheme.cardRadius),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 40,
              child: Center(
                child: CharacterPositionMiniMap(
                  aspectRatio: dimensions.width / dimensions.height,
                  extent: 40,
                  position: placed
                      ? Offset(position.column, position.row)
                      : null,
                  color: CharacterMarkerPalette.of(
                    config.characters,
                    character,
                  ).fill,
                  dotDiameter: 10,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.characterPanel_position,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              key: const ValueKey('character-panel-place'),
              onPressed: character.enabled ? onPlace : null,
              style: FilledButton.styleFrom(minimumSize: const Size(56, 44)),
              child: Text(l10n.characterPanel_place),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditActions extends StatelessWidget {
  const _EditActions({required this.onSaveToLibrary, required this.onDelete});

  final VoidCallback onSaveToLibrary;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final style = TextButton.styleFrom(minimumSize: const Size(0, 48));
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      spacing: 8,
      children: [
        TextButton.icon(
          key: const ValueKey('character-panel-save-library'),
          onPressed: onSaveToLibrary,
          style: style,
          icon: const Icon(Icons.library_add_outlined),
          label: Text(l10n.tagLibrary_addToLibrary),
        ),
        TextButton.icon(
          key: const ValueKey('character-panel-delete'),
          onPressed: onDelete,
          style: style.copyWith(
            foregroundColor: WidgetStatePropertyAll(colors.error),
          ),
          icon: const Icon(Icons.delete_outline_rounded),
          label: Text(l10n.characterPanel_deleteCharacter),
        ),
      ],
    );
  }
}
