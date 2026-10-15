import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/utils/character_prompt_block_parser.dart';
import '../../../../../core/utils/localization_extension.dart';
import '../../../../../data/models/character/character_prompt.dart';
import '../../../../providers/character_prompt_provider.dart';
import '../../../../providers/generation/generation_params_selectors.dart';
import '../../../../providers/image_generation_provider.dart';
import '../../../../themes/core/layered_surface_style.dart';
import '../../../../themes/theme_extension.dart';
import '../../../../widgets/character/add_to_library_dialog.dart';
import '../../../../widgets/character/character_marker.dart';
import '../../../../widgets/character/inline_character_editor.dart';
import '../../../../widgets/common/horizontal_segmented_control.dart';
import 'character_panel_header.dart';
import 'character_place_canvas.dart';

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
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: subtitle,
          trailing: [
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
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _IdentityRow(
                  character: character,
                  onGender: (gender) {
                    // The editor only takes outside changes while unfocused.
                    FocusManager.instance.primaryFocus?.unfocus();
                    notifier.updateCharacter(character.withGender(gender));
                  },
                  onEnabled: (_) =>
                      notifier.toggleCharacterEnabled(character.id),
                ),
                const SizedBox(height: 12),
                CharacterPromptEditor(
                  key: ValueKey('character-panel-editor-${character.id}'),
                  character: character,
                  autofocus: false,
                ),
                const SizedBox(height: 12),
                _PositionCard(
                  config: config,
                  character: character,
                  onPlace: onOpenPlace,
                ),
                const SizedBox(height: 12),
                _EditActions(
                  onSaveToLibrary: () => AddToLibraryDialog.show(
                    context,
                    name: character.name,
                    content: CharacterPromptBlockParser.compose(
                      positivePrompt: character.prompt,
                      negativePrompt: character.negativePrompt,
                    ),
                  ),
                  onDelete: () => onDelete(character),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _IdentityRow extends StatelessWidget {
  const _IdentityRow({
    required this.character,
    required this.onGender,
    required this.onEnabled,
  });

  final CharacterPrompt character;
  final ValueChanged<CharacterGender> onGender;
  final ValueChanged<bool> onEnabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final options = [
      (CharacterGender.female, l10n.characterEditor_addFemale),
      (CharacterGender.male, l10n.characterEditor_addMale),
      (CharacterGender.other, l10n.characterEditor_addOther),
    ];
    final genders = Semantics(
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
    final include = MergeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.characterPanel_includeSwitch,
            style: theme.textTheme.labelLarge,
          ),
          Switch(
            key: const ValueKey('character-panel-include'),
            value: character.enabled,
            onChanged: onEnabled,
          ),
        ],
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        // Large text puts the switch under the genders instead of squeezing.
        if (constraints.maxWidth < 360 ||
            MediaQuery.textScalerOf(context).scale(14) > 20) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              genders,
              const SizedBox(height: 4),
              Align(alignment: AlignmentDirectional.centerEnd, child: include),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: genders),
            const SizedBox(width: 8),
            include,
          ],
        );
      },
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
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 56,
              child: Center(
                child: CharacterPositionMiniMap(
                  aspectRatio: dimensions.width / dimensions.height,
                  extent: 56,
                  position: placed
                      ? Offset(position.column, position.row)
                      : null,
                  color: CharacterMarkerPalette.of(
                    config.characters,
                    character,
                  ).fill,
                  dotDiameter: 12,
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
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
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
              style: FilledButton.styleFrom(minimumSize: const Size(64, 44)),
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
