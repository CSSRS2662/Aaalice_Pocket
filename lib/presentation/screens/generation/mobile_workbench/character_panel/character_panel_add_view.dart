import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/utils/localization_extension.dart';
import '../../../../../data/models/character/character_prompt.dart';
import '../../../../providers/character_prompt_provider.dart';
import '../../../../themes/core/layered_surface_style.dart';
import '../../../../themes/theme_extension.dart';
import '../../../../widgets/character/character_library_import.dart';
import '../../../../widgets/character/character_marker.dart';
import 'character_panel_header.dart';

/// Adds a character by gender or from the tag library, then opens it.
class CharacterPanelAddView extends ConsumerStatefulWidget {
  const CharacterPanelAddView({
    super.key,
    required this.onBack,
    required this.onAdded,
  });

  final VoidCallback onBack;
  final ValueChanged<String> onAdded;

  @override
  ConsumerState<CharacterPanelAddView> createState() =>
      _CharacterPanelAddViewState();
}

class _CharacterPanelAddViewState extends ConsumerState<CharacterPanelAddView> {
  void _add(CharacterGender gender) {
    final notifier = ref.read(characterPromptNotifierProvider.notifier);
    final before = ref.read(characterPromptNotifierProvider).characters.length;
    notifier.addCharacter(
      gender,
      name: context.l10n.character_number(before + 1),
    );
    final characters = ref.read(characterPromptNotifierProvider).characters;
    if (characters.length > before) widget.onAdded(characters.last.id);
  }

  Future<void> _addFromLibrary() async {
    final id = await addCharacterFromLibrary(context, ref);
    if (id != null && mounted) widget.onAdded(id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final options = [
      (CharacterGender.female, l10n.characterEditor_genderFemale),
      (CharacterGender.male, l10n.characterEditor_genderMale),
      (CharacterGender.other, l10n.characterEditor_genderOther),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CharacterPanelHeader(
          title: Text(l10n.character_addCharacter),
          onBack: widget.onBack,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    // Three across while each keeps a readable width.
                    final width = constraints.maxWidth;
                    final perRow = width >= 3 * 96 + 16 ? 3 : 1;
                    final itemWidth = perRow == 3 ? (width - 16) / 3 : width;
                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final (gender, label) in options)
                          SizedBox(
                            width: itemWidth,
                            child: _GenderOption(
                              key: ValueKey(
                                'character-panel-add-${gender.name}',
                              ),
                              gender: gender,
                              label: label,
                              onTap: () => _add(gender),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                FilledButton.tonalIcon(
                  key: const ValueKey('character-panel-add-library'),
                  onPressed: _addFromLibrary,
                  icon: const Icon(Icons.library_books_outlined),
                  label: Text(l10n.characterPanel_addFromLibrary),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    textStyle: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _GenderOption extends StatelessWidget {
  const _GenderOption({
    super.key,
    required this.gender,
    required this.label,
    required this.onTap,
  });

  final CharacterGender gender;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: sectionSurfaceColor(theme.colorScheme),
      borderRadius: BorderRadius.circular(theme.appTheme.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 88),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CharacterMarkerDisc(
                  colors: CharacterMarkerPalette.forGender(gender),
                  diameter: 36,
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
