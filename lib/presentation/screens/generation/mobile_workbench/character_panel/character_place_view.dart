import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/utils/localization_extension.dart';
import '../../../../../data/models/character/character_prompt.dart';
import '../../../../providers/character_place_options_provider.dart';
import '../../../../providers/character_prompt_provider.dart';
import '../../../../providers/composition_guide_provider.dart';
import '../../../../providers/generation/generation_params_selectors.dart';
import '../../../../providers/image_generation_provider.dart';
import '../../../../themes/core/layered_surface_style.dart';
import '../../../../widgets/character/character_marker.dart';
import '../../../../widgets/common/composition_guide.dart';
import '../../../../widgets/common/horizontal_segmented_control.dart';
import '../mobile_generation_header.dart';
import 'character_panel_header.dart';
import 'character_place_canvas.dart';

/// Ratio name shown next to the size when the size is close to a common one.
String? commonAspectRatioLabel(int width, int height) {
  const ratios = [
    (1, 1),
    (2, 3),
    (3, 2),
    (3, 4),
    (4, 3),
    (9, 16),
    (16, 9),
    (1, 2),
    (2, 1),
  ];
  final value = width / height;
  for (final (w, h) in ratios) {
    if ((value / (w / h) - 1).abs() <= 0.03) return '$w:$h';
  }
  return null;
}

/// Full-height page for placing characters by hand. The canvas always has the
/// next generation's aspect ratio and follows size changes made here or
/// anywhere else.
class CharacterPlaceView extends ConsumerStatefulWidget {
  const CharacterPlaceView({
    super.key,
    this.initialSelection,
    required this.onDone,
    required this.onHandToAi,
    required this.onMessage,
  });

  final String? initialSelection;
  final VoidCallback onDone;
  final VoidCallback onHandToAi;
  final ValueChanged<String> onMessage;

  @override
  ConsumerState<CharacterPlaceView> createState() => _CharacterPlaceViewState();
}

class _CharacterPlaceViewState extends ConsumerState<CharacterPlaceView> {
  late String? _selected = widget.initialSelection;
  ({String id, Offset position})? _live;

  String? _selection(List<CharacterPrompt> characters) {
    for (final character in characters) {
      if (character.id == _selected && character.enabled) return character.id;
    }
    for (final character in characters) {
      if (character.enabled) return character.id;
    }
    return null;
  }

  void _spread(List<CharacterPrompt> characters) {
    final included = [
      for (final character in characters)
        if (character.enabled) character.id,
    ];
    final count = included.length;
    ref.read(characterPromptNotifierProvider.notifier).replaceAll([
      for (final character in characters)
        if (included.indexOf(character.id) case final index when index >= 0)
          character.copyWith(
            positionMode: CharacterPositionMode.custom,
            customPosition: CharacterPosition(
              mode: CharacterPositionMode.custom,
              row: 0.5,
              column: (index + 1) / (count + 1),
            ),
          )
        else
          character,
    ]);
  }

  String _readout(CharacterPromptConfig config, CharacterPrompt? selected) {
    final l10n = context.l10n;
    if (selected == null) return l10n.characterPanel_noneIncluded;
    final live = _live;
    final resolved = config.resolvePosition(selected);
    final position = live != null && live.id == selected.id
        ? live.position
        : Offset(resolved.column, resolved.row);
    return l10n.characterPanel_placeReadout(
      selected.name,
      characterPositionCell(position.dx, position.dy),
      (position.dx * 100).round(),
      (position.dy * 100).round(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final config = ref.watch(characterPromptNotifierProvider);
    final characters = config.characters;
    final selectedId = _selection(characters);
    final selected = config.findCharacterById(selectedId ?? '');
    final dimensions = ref.watch(
      generationParamsNotifierProvider.select(selectPreviewDimensionsViewData),
    );
    final ratio = commonAspectRatioLabel(dimensions.width, dimensions.height);
    final size = MobileGenerationHeader.sizeLabel(
      dimensions.width,
      dimensions.height,
    );

    final header = CharacterPanelHeader(
      onBack: widget.onDone,
      title: Text(l10n.characterPanel_placeTitle),
      subtitle: _readout(config, selected),
    );
    final tools = _PlaceTools(
      sizeLabel: ratio == null ? size : '$size · $ratio',
    );
    final canvas = CharacterPlaceCanvas(
      selectedId: selectedId,
      onSelect: (id) => setState(() => _selected = id),
      onLiveMove: (id, position) => setState(
        () => _live = position == null ? null : (id: id, position: position),
      ),
    );
    _CharacterStrip strip({required bool wrap}) => _CharacterStrip(
      characters: characters,
      selectedId: selectedId,
      wrap: wrap,
      onSelect: (character) {
        if (!character.enabled) {
          return widget.onMessage(
            l10n.characterPanel_includeFirst(character.name),
          );
        }
        setState(() => _selected = character.id);
      },
      onSpread: () => _spread(characters),
    );
    final footer = Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.tonal(
              key: const ValueKey('character-place-hand-to-ai'),
              onPressed: widget.onHandToAi,
              style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
              child: Text(l10n.characterPanel_handToAi),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton(
              key: const ValueKey('character-place-done'),
              onPressed: widget.onDone,
              style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
              child: Text(l10n.common_done),
            ),
          ),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Short landscape space puts the controls beside the canvas, which
        // would otherwise be squeezed to a sliver between them.
        final beside =
            constraints.maxHeight < 560 &&
            constraints.maxWidth > constraints.maxHeight * 1.2;
        if (!beside) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              tools,
              Expanded(child: canvas),
              strip(wrap: false),
              footer,
            ],
          );
        }
        final side = (constraints.maxWidth * 0.42).clamp(260.0, 360.0);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: canvas),
            SizedBox(
              width: side,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  header,
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [tools, strip(wrap: true)],
                      ),
                    ),
                  ),
                  footer,
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The generation size, composition guides, and the snap and backdrop
/// toggles in one row that scrolls sideways when it runs out of room.
class _PlaceTools extends ConsumerWidget {
  const _PlaceTools({required this.sizeLabel});

  final String sizeLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final guide = ref.watch(compositionGuideNotifierProvider);
    final options = ref.watch(characterPlaceOptionsProvider);
    void setOptions(CharacterPlaceOptions next) =>
        ref.read(characterPlaceOptionsProvider.notifier).state = next;
    final guides = [
      (CompositionGuideMode.none, l10n.characterCanvas_guideNone),
      (CompositionGuideMode.thirds, l10n.characterCanvas_guideThirds),
      (CompositionGuideMode.phi, l10n.characterCanvas_guidePhi),
      (CompositionGuideMode.grid, l10n.characterCanvas_guideGrid),
    ];
    // Two rows so every tool is in view on a phone; each row still scrolls
    // sideways instead of clipping with very large text.
    return Padding(
      key: const ValueKey('character-place-tools'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HorizontalSegmentedControl(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Same pill and text limit as the generation page header.
                MediaQuery.withClampedTextScaling(
                  maxScaleFactor: MobileGenerationHeader.maxTextScale,
                  child: MobileSizeMenu(label: sizeLabel),
                ),
                const SizedBox(width: 12),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilterChip(
                      key: const ValueKey('character-place-snap'),
                      label: Text(l10n.characterPanel_snap),
                      selected: options.snap,
                      showCheckmark: false,
                      onSelected: (value) =>
                          setOptions((snap: value, backdrop: options.backdrop)),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      key: const ValueKey('character-place-backdrop'),
                      label: Text(l10n.characterPanel_backdrop),
                      selected: options.backdrop,
                      showCheckmark: false,
                      onSelected: (value) =>
                          setOptions((snap: options.snap, backdrop: value)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          HorizontalSegmentedControl(
            child: SegmentedButton<CompositionGuideMode>(
              key: const ValueKey('character-place-guides'),
              segments: [
                for (final (mode, label) in guides)
                  ButtonSegment(value: mode, label: Text(label)),
              ],
              selected: {guide.mode},
              showSelectedIcon: false,
              onSelectionChanged: (selection) => ref
                  .read(compositionGuideNotifierProvider.notifier)
                  .setMode(selection.single),
            ),
          ),
        ],
      ),
    );
  }
}

/// Every character as a chip to pick which one the canvas moves; characters
/// left out of the generation stay listed but greyed.
class _CharacterStrip extends StatelessWidget {
  const _CharacterStrip({
    required this.characters,
    required this.selectedId,
    required this.wrap,
    required this.onSelect,
    required this.onSpread,
  });

  final List<CharacterPrompt> characters;
  final String? selectedId;

  /// Flows onto more lines instead of scrolling sideways.
  final bool wrap;
  final ValueChanged<CharacterPrompt> onSelect;
  final VoidCallback onSpread;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final children = [
      for (final character in characters)
        _StripChip(
          character: character,
          markerColors: CharacterMarkerPalette.of(characters, character),
          selected: character.id == selectedId,
          onTap: () => onSelect(character),
        ),
      TextButton.icon(
        key: const ValueKey('character-place-spread'),
        onPressed: characters.any((item) => item.enabled) ? onSpread : null,
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 44),
          backgroundColor: controlSurfaceColor(colors),
        ),
        icon: const Icon(Icons.view_column_rounded, size: 18),
        label: Text(context.l10n.characterPanel_spread),
      ),
    ];
    if (wrap) {
      return Padding(
        key: const ValueKey('character-place-strip'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Wrap(spacing: 8, runSpacing: 8, children: children),
      );
    }
    return SingleChildScrollView(
      key: const ValueKey('character-place-strip'),
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          for (final (index, child) in children.indexed) ...[
            if (index > 0) const SizedBox(width: 8),
            child,
          ],
        ],
      ),
    );
  }
}

class _StripChip extends StatelessWidget {
  const _StripChip({
    required this.character,
    required this.markerColors,
    required this.selected,
    required this.onTap,
  });

  final CharacterPrompt character;
  final CharacterMarkerColors markerColors;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final foreground = selected ? colors.onInverseSurface : colors.onSurface;
    return Opacity(
      opacity: character.enabled ? 1 : 0.5,
      child: Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: selected ? colors.inverseSurface : controlSurfaceColor(colors),
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('character-place-chip-${character.id}'),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44, maxWidth: 200),
              child: Padding(
                padding: const EdgeInsetsDirectional.only(start: 6, end: 14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CharacterMarkerDisc(
                      colors: markerColors,
                      diameter: 30,
                      outlined: !character.enabled,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        character.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: foreground,
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
      ),
    );
  }
}
