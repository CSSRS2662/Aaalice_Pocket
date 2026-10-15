import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/utils/localization_extension.dart';
import '../../../../../data/models/character/character_prompt.dart';
import '../../../../providers/character_prompt_provider.dart';
import '../../../../providers/generation/generation_params_selectors.dart';
import '../../../../providers/image_generation_provider.dart';
import '../../../../themes/core/layered_surface_style.dart';
import '../../../../themes/theme_extension.dart';
import '../../../../widgets/character/character_marker.dart';
import '../../../../widgets/common/horizontal_segmented_control.dart';
import '../../../../widgets/common/reorderable_tile_grid.dart';
import '../../widgets/prompt_group_tile.dart';
import 'character_panel_header.dart';
import 'character_panel_tile.dart';

/// The panel's first page: whether AI or the user places characters, and a
/// grid of character cards ending in an add card.
class CharacterPanelGridView extends ConsumerWidget {
  const CharacterPanelGridView({
    super.key,
    required this.onClose,
    required this.onOpenAdd,
    required this.onOpenEdit,
    required this.onOpenPlace,
    required this.onDelete,
    required this.onMessage,
  });

  final VoidCallback onClose;
  final VoidCallback onOpenAdd;
  final ValueChanged<String> onOpenEdit;
  final VoidCallback onOpenPlace;
  final ValueChanged<CharacterPrompt> onDelete;
  final ValueChanged<String> onMessage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final config = ref.watch(characterPromptNotifierProvider);
    final notifier = ref.read(characterPromptNotifierProvider.notifier);
    final dimensions = ref.watch(
      generationParamsNotifierProvider.select(selectPreviewDimensionsViewData),
    );
    final limitReached = ref.watch(characterLimitReachedProvider);
    final characters = config.characters;
    final manual = !config.globalAiChoice;
    final aspectRatio = dimensions.width / dimensions.height;
    final ids = [for (final character in characters) character.id];

    void move(String id, int index) {
      final order = List<String>.of(ids)
        ..remove(id)
        ..insert(index, id);
      notifier.setCharacterOrder(order);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CharacterPanelHeader(
          title: Row(
            children: [
              Flexible(child: Text(l10n.characterPanel_title)),
              const SizedBox(width: 8),
              _CountBadge(count: characters.length),
            ],
          ),
          trailing: [
            IconButton(
              key: const ValueKey('character-panel-close'),
              onPressed: onClose,
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _PositionModeRow(
                  manual: manual,
                  onAi: () => notifier.setGlobalAiChoice(true),
                  onManual: onOpenPlace,
                ),
                const SizedBox(height: 14),
                ReorderableTileGrid(
                  ids: ids,
                  tileHeight: CharacterPanelTile.heightOf(context),
                  minTileWidth: 150,
                  maxColumns: 3,
                  slotKeyPrefix: 'character_panel_slot_',
                  placeholder: const PromptGroupTilePlaceholder(),
                  trailing: _AddCharacterTile(
                    limitReached: limitReached,
                    onTap: limitReached
                        ? () => onMessage(
                            l10n.character_limitReached(
                              notifier.characterLimit.toString(),
                            ),
                          )
                        : onOpenAdd,
                  ),
                  onMove: move,
                  onDelete: (id) {
                    final character = config.findCharacterById(id);
                    if (character != null) onDelete(character);
                  },
                  tileBuilder: (context, id, controls) {
                    final index = ids.indexOf(id);
                    final character = config.findCharacterById(id);
                    if (character == null) return const SizedBox.shrink();
                    final position = config.resolvePosition(character);
                    return CharacterPanelTile(
                      character: character,
                      colors: CharacterMarkerPalette.of(characters, character),
                      position: manual && character.enabled
                          ? Offset(position.column, position.row)
                          : null,
                      aspectRatio: aspectRatio,
                      controls: controls,
                      onOpen: () => onOpenEdit(id),
                      onToggleEnabled: () =>
                          notifier.toggleCharacterEnabled(id),
                      onMoveEarlier: index > 0
                          ? () => move(id, index - 1)
                          : null,
                      onMoveLater: index < ids.length - 1
                          ? () => move(id, index + 1)
                          : null,
                    );
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.characterPanel_gridHint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.5,
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

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 26),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$count',
        textAlign: TextAlign.center,
        style: theme.textTheme.labelLarge?.copyWith(
          color: colors.onPrimaryContainer,
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// AI decides every position, or the user places them; choosing manual opens
/// the placement page, which "Adjust" reopens later.
class _PositionModeRow extends StatelessWidget {
  const _PositionModeRow({
    required this.manual,
    required this.onAi,
    required this.onManual,
  });

  final bool manual;
  final VoidCallback onAi;
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final segments = HorizontalSegmentedControl(
      child: SegmentedButton<bool>(
        key: const ValueKey('character-panel-position-mode'),
        segments: [
          ButtonSegment(
            value: false,
            label: Text(l10n.characterPanel_positionAi),
          ),
          ButtonSegment(
            value: true,
            label: Text(l10n.characterPanel_positionManual),
          ),
        ],
        selected: {manual},
        showSelectedIcon: false,
        onSelectionChanged: (selection) =>
            selection.single ? onManual() : onAi(),
      ),
    );
    // The label and Adjust share a line so both segments always get the
    // full width, even on narrow phones and with long translations.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.characterPanel_position,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (manual)
                FilledButton.tonalIcon(
                  key: const ValueKey('character-panel-adjust'),
                  onPressed: onManual,
                  iconAlignment: IconAlignment.end,
                  icon: const Icon(Icons.chevron_right_rounded, size: 20),
                  label: Text(l10n.characterPanel_adjust),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsetsDirectional.only(
                      start: 14,
                      end: 8,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        segments,
      ],
    );
  }
}

class _AddCharacterTile extends StatelessWidget {
  const _AddCharacterTile({required this.limitReached, required this.onTap});

  final bool limitReached;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Opacity(
      opacity: limitReached ? 0.5 : 1,
      child: Material(
        color: controlSurfaceColor(colors),
        borderRadius: BorderRadius.circular(theme.appTheme.cardRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const ValueKey('character_panel_add_tile'),
          onTap: onTap,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_rounded, color: colors.primary),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      context.l10n.character_addCharacter,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: colors.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
