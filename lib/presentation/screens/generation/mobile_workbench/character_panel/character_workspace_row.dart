import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../../core/utils/localization_extension.dart';
import '../../../../../data/models/character/character_prompt.dart';
import '../../../../themes/core/layered_surface_style.dart';
import '../../../../themes/theme_extension.dart';
import '../../../../widgets/character/character_marker.dart';
import 'character_workspace_editor.dart';

/// One character in the workspace list: a single line while closed (marker,
/// name, prompt summary, position), the editor below it while open. Long
/// press on the line drags the character to a new place.
class CharacterWorkspaceRow extends StatelessWidget {
  const CharacterWorkspaceRow({
    super.key,
    required this.index,
    required this.character,
    required this.colors,
    required this.expanded,
    required this.negative,
    required this.position,
    required this.aspectRatio,
    required this.onToggleExpanded,
    required this.onToggleEnabled,
    required this.onDelete,
    this.fromLibrary = false,
    this.unsavedLibraryChanges = false,
  });

  final int index;

  /// Added from or saved to the character library.
  final bool fromLibrary;

  /// Changed since it last matched its library entry.
  final bool unsavedLibraryChanges;
  final CharacterPrompt character;
  final CharacterMarkerColors colors;
  final bool expanded;
  final bool negative;

  /// Column and row in 0–1 while positions are manual; null hides the map.
  final Offset? position;
  final double aspectRatio;
  final VoidCallback onToggleExpanded;
  final VoidCallback onToggleEnabled;
  final VoidCallback onDelete;

  static const double mapExtent = 26;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = context.l10n;
    final prompt = (negative ? character.negativePrompt : character.prompt)
        .trim();
    final enabled = character.enabled;
    final radius = BorderRadius.circular(theme.appTheme.cardRadius);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : theme.appTheme.fastDuration;
    final lineHeight = math.max(
      48.0,
      MediaQuery.textScalerOf(context).scale(14) * 1.4 + 18,
    );

    final head = Semantics(
      expanded: expanded,
      child: InkWell(
        key: ValueKey('character_workspace_row_${character.id}'),
        onTap: onToggleExpanded,
        borderRadius: radius,
        child: SizedBox(
          height: lineHeight,
          child: Row(
            children: [
              _EnableToggle(
                key: ValueKey('character_workspace_enabled_${character.id}'),
                colors: colors,
                enabled: enabled,
                tooltip: enabled
                    ? l10n.characterPanel_leaveOut(character.name)
                    : l10n.characterPanel_include(character.name),
                onTap: onToggleEnabled,
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: Opacity(
                  opacity: enabled ? 1 : 0.45,
                  child: Text(
                    character.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              if (fromLibrary) ...[
                const SizedBox(width: 4),
                Tooltip(
                  message: l10n.characterLibrary_fromLibrary,
                  child: Icon(
                    Icons.people_outline_rounded,
                    key: ValueKey('character_workspace_linked_${character.id}'),
                    size: 16,
                    color: scheme.primary,
                    semanticLabel: l10n.characterLibrary_fromLibrary,
                  ),
                ),
              ],
              if (unsavedLibraryChanges) ...[
                const SizedBox(width: 4),
                Semantics(
                  label: l10n.characterLibrary_unsaved,
                  child: Container(
                    key: ValueKey(
                      'character_workspace_unsaved_${character.id}',
                    ),
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFFC77700),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              Expanded(
                child: AnimatedOpacity(
                  duration: duration,
                  // The open row shows the full prompt below instead.
                  opacity: expanded ? 0 : (enabled ? 1 : 0.45),
                  child: Text(
                    prompt.isEmpty ? l10n.characterPanel_emptyPrompt : prompt,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              if (position case final spot?) ...[
                const SizedBox(width: 8),
                CharacterPositionMiniMap(
                  key: ValueKey('character_workspace_map_${character.id}'),
                  aspectRatio: aspectRatio,
                  extent: mapExtent,
                  position: spot,
                  color: colors.fill,
                  dotDiameter: 6,
                ),
              ],
              AnimatedRotation(
                duration: duration,
                turns: expanded ? 0.5 : 0,
                child: SizedBox(
                  width: 36,
                  child: Icon(
                    Icons.expand_more_rounded,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: AnimatedContainer(
        duration: duration,
        curve: theme.appTheme.standardCurve,
        decoration: BoxDecoration(
          color: expanded ? scheme.surface : sectionSurfaceColor(scheme),
          borderRadius: radius,
          border: expanded
              ? Border.all(color: scheme.primaryContainer, width: 1.5)
              : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ReorderableDelayedDragStartListener(index: index, child: head),
              AnimatedSize(
                duration: duration,
                curve: theme.appTheme.standardCurve,
                alignment: Alignment.topCenter,
                child: expanded
                    ? CharacterWorkspaceEditor(
                        key: ValueKey(
                          'character-workspace-editor-${character.id}',
                        ),
                        character: character,
                        negative: negative,
                        onDelete: onDelete,
                      )
                    : const SizedBox(width: double.infinity),
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
            width: 48,
            height: 48,
            child: Center(
              child: CharacterMarkerDisc(
                colors: colors,
                diameter: 28,
                outlined: !enabled,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
