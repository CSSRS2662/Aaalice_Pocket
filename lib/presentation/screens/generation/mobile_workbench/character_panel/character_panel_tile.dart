import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../../../core/utils/localization_extension.dart';
import '../../../../../data/models/character/character_prompt.dart';
import '../../../../themes/core/layered_surface_style.dart';
import '../../../../themes/theme_extension.dart';
import '../../../../widgets/character/character_marker.dart';
import '../../../../widgets/common/reorderable_tile_grid.dart';

/// One character card in the panel grid: the marker disc that includes or
/// leaves it out, the name, a two-tap delete cross, two lines of its prompt
/// and, while positions are manual, where it stands in the picture.
class CharacterPanelTile extends StatelessWidget {
  const CharacterPanelTile({
    super.key,
    required this.character,
    required this.colors,
    required this.position,
    required this.aspectRatio,
    required this.controls,
    required this.onOpen,
    required this.onToggleEnabled,
    this.onMoveEarlier,
    this.onMoveLater,
  });

  static const double controlExtent = 44;
  static const double mapExtent = 40;

  /// Card height: the name row plus two prompt lines, never shorter than the
  /// name row plus the position map.
  static double heightOf(BuildContext context) {
    final lineHeight = MediaQuery.textScalerOf(context).scale(13) * 1.45;
    final nameRow = math.max(
      controlExtent,
      MediaQuery.textScalerOf(context).scale(15) * 1.4 + 8,
    );
    return math
        .max(nameRow + lineHeight * 2 + 14, nameRow + mapExtent + 12)
        .ceilToDouble();
  }

  final CharacterPrompt character;
  final CharacterMarkerColors colors;

  /// Column and row in 0–1 while positions are manual; null hides the map.
  final Offset? position;
  final double aspectRatio;
  final ReorderableTileControls controls;
  final VoidCallback onOpen;
  final VoidCallback onToggleEnabled;
  final VoidCallback? onMoveEarlier;
  final VoidCallback? onMoveLater;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = context.l10n;
    final enabled = character.enabled;
    final prompt = character.prompt.trim();
    final spot = position;
    final faded = enabled ? 1.0 : 0.5;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 160);

    return Material(
      color: sectionSurfaceColor(scheme),
      borderRadius: BorderRadius.circular(theme.appTheme.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        customSemanticsActions: {
          if (onMoveEarlier != null)
            CustomSemanticsAction(label: l10n.characterEditor_moveUp):
                onMoveEarlier!,
          if (onMoveLater != null)
            CustomSemanticsAction(label: l10n.characterEditor_moveDown):
                onMoveLater!,
        },
        child: InkWell(
          key: ValueKey('character_panel_tile_${character.id}'),
          onTap: onOpen,
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: math.max(
                      controlExtent,
                      MediaQuery.textScalerOf(context).scale(15) * 1.4 + 8,
                    ),
                    child: Row(
                      children: [
                        _EnableToggle(
                          key: ValueKey(
                            'character_panel_enabled_${character.id}',
                          ),
                          colors: colors,
                          enabled: enabled,
                          tooltip: enabled
                              ? l10n.characterPanel_leaveOut(character.name)
                              : l10n.characterPanel_include(character.name),
                          onTap: onToggleEnabled,
                        ),
                        Expanded(
                          child: AnimatedOpacity(
                            duration: duration,
                            opacity: faded,
                            child: Text(
                              character.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        ReorderableTileDeleteButton(
                          key: ValueKey(
                            'character_panel_delete_${character.id}',
                          ),
                          armed: controls.deleteArmed,
                          tooltip: controls.deleteArmed
                              ? l10n.characterPanel_deleteAgain(character.name)
                              : l10n.characterPanel_delete(character.name),
                          onTap: controls.onDeleteTap,
                          onTapOutside: controls.onDisarmDelete,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsetsDirectional.only(
                        start: 14,
                        end: spot == null ? 14 : mapExtent + 20,
                        bottom: 12,
                      ),
                      child: AnimatedOpacity(
                        duration: duration,
                        opacity: faded,
                        child: Text(
                          prompt.isEmpty
                              ? l10n.characterPanel_emptyPrompt
                              : prompt,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontSize: 13,
                            height: 1.45,
                            color: prompt.isEmpty
                                ? scheme.onSurfaceVariant.withValues(alpha: 0.6)
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (spot != null)
                PositionedDirectional(
                  end: 10,
                  bottom: 10,
                  child: IgnorePointer(
                    child: CharacterPositionMiniMap(
                      key: ValueKey('character_panel_map_${character.id}'),
                      aspectRatio: aspectRatio,
                      extent: mapExtent,
                      position: spot,
                      color: colors.fill,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EnableToggle extends StatelessWidget {
  const _EnableToggle({
    super.key,
    required this.colors,
    required this.enabled,
    required this.tooltip,
    required this.onTap,
  });

  final CharacterMarkerColors colors;
  final bool enabled;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        toggled: enabled,
        child: InkResponse(
          onTap: onTap,
          radius: 22,
          child: SizedBox(
            width: CharacterPanelTile.controlExtent,
            child: Center(
              child: CharacterMarkerDisc(
                colors: colors,
                diameter: 24,
                outlined: !enabled,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
