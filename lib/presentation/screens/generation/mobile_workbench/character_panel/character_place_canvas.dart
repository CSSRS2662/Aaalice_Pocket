import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/utils/localization_extension.dart';
import '../../../../../data/models/character/character_prompt.dart';
import '../../../../providers/character_place_options_provider.dart';
import '../../../../providers/character_prompt_provider.dart';
import '../../../../providers/composition_guide_provider.dart';
import '../../../../providers/generation/generation_params_selectors.dart';
import '../../../../providers/generation/image_generation_selectors.dart';
import '../../../../providers/image_generation_provider.dart';
import '../../../../widgets/character/character_marker.dart';
import '../../../../widgets/common/composition_guide.dart';
import '../../../../widgets/common/decoded_memory_image.dart';

/// Cell of the legacy 5×5 position grid, such as `B3`.
String characterPositionCell(double column, double row) {
  final x = (column * 5).floor().clamp(0, 4);
  final y = (row * 5).floor().clamp(0, 4);
  return '${'ABCDE'[x]}${y + 1}';
}

/// Centre of the 5×5 cell that [value] falls in.
double snapToCellCentre(double value) =>
    ((value * 5).floor().clamp(0, 4) + 0.5) / 5;

/// The picture in the generation's aspect ratio with a marker per included
/// character. Drag a marker, or tap anywhere to move the selected character
/// there; positions are written when the finger lifts.
class CharacterPlaceCanvas extends ConsumerStatefulWidget {
  const CharacterPlaceCanvas({
    super.key,
    required this.selectedId,
    required this.onSelect,
    required this.onLiveMove,
  });

  /// Room around the picture so markers at its edges stay whole.
  static const double margin = 26;
  static const double markerDiameter = 40;

  final String? selectedId;
  final ValueChanged<String> onSelect;

  /// Column and row of the character under the finger, null once released.
  final void Function(String id, Offset? position) onLiveMove;

  @override
  ConsumerState<CharacterPlaceCanvas> createState() =>
      _CharacterPlaceCanvasState();
}

class _CharacterPlaceCanvasState extends ConsumerState<CharacterPlaceCanvas> {
  String? _dragId;
  Offset _dragPoint = Offset.zero;
  Offset _grab = Offset.zero;
  Size _picture = Size.zero;

  Offset _unit(Offset local) {
    if (_picture.isEmpty) return const Offset(0.5, 0.5);
    return Offset(
      ((local.dx - CharacterPlaceCanvas.margin) / _picture.width).clamp(
        0.0,
        1.0,
      ),
      ((local.dy - CharacterPlaceCanvas.margin) / _picture.height).clamp(
        0.0,
        1.0,
      ),
    );
  }

  Offset _local(Offset unit) => Offset(
    CharacterPlaceCanvas.margin + unit.dx * _picture.width,
    CharacterPlaceCanvas.margin + unit.dy * _picture.height,
  );

  Offset _positionOf(CharacterPromptConfig config, CharacterPrompt character) {
    if (_dragId == character.id) return _dragPoint;
    final position = config.resolvePosition(character);
    return Offset(position.column, position.row);
  }

  /// The included character whose marker is under [local], nearest first.
  CharacterPrompt? _markerAt(CharacterPromptConfig config, Offset local) {
    CharacterPrompt? best;
    var bestDistance = CharacterPlaceCanvas.markerDiameter / 2 + 8;
    for (final character in config.characters) {
      if (!character.enabled) continue;
      final distance =
          (_local(_positionOf(config, character)) - local).distance;
      if (distance <= bestDistance) {
        best = character;
        bestDistance = distance;
      }
    }
    return best;
  }

  CharacterPrompt? _selected(CharacterPromptConfig config) {
    final character = config.findCharacterById(widget.selectedId ?? '');
    return character != null && character.enabled ? character : null;
  }

  void _commit(CharacterPrompt character, Offset unit) {
    final snap = ref.read(characterPlaceOptionsProvider).snap;
    final point = snap
        ? Offset(snapToCellCentre(unit.dx), snapToCellCentre(unit.dy))
        : unit;
    ref
        .read(characterPromptNotifierProvider.notifier)
        .updateCharacter(
          character.copyWith(
            positionMode: CharacterPositionMode.custom,
            customPosition: CharacterPosition(
              mode: CharacterPositionMode.custom,
              row: point.dy,
              column: point.dx,
            ),
          ),
        );
  }

  void _onTapUp(TapUpDetails details) {
    final config = ref.read(characterPromptNotifierProvider);
    final hit = _markerAt(config, details.localPosition);
    if (hit != null) return widget.onSelect(hit.id);
    final selected = _selected(config);
    if (selected != null) _commit(selected, _unit(details.localPosition));
  }

  void _onPanStart(DragStartDetails details) {
    final config = ref.read(characterPromptNotifierProvider);
    final hit = _markerAt(config, details.localPosition);
    final target = hit ?? _selected(config);
    if (target == null) return;
    if (hit != null) widget.onSelect(hit.id);
    // A grabbed marker keeps its offset from the finger; a drag that starts
    // on empty space brings the selected marker under the finger.
    _grab = hit == null
        ? Offset.zero
        : _local(_positionOf(config, hit)) - details.localPosition;
    setState(() {
      _dragId = target.id;
      _dragPoint = _unit(details.localPosition + _grab);
    });
    widget.onLiveMove(target.id, _dragPoint);
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final id = _dragId;
    if (id == null) return;
    setState(() => _dragPoint = _unit(details.localPosition + _grab));
    widget.onLiveMove(id, _dragPoint);
  }

  void _onPanEnd() {
    final id = _dragId;
    if (id == null) return;
    final character = ref
        .read(characterPromptNotifierProvider)
        .findCharacterById(id);
    if (character != null) _commit(character, _dragPoint);
    setState(() => _dragId = null);
    widget.onLiveMove(id, null);
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(characterPromptNotifierProvider);
    final dimensions = ref.watch(
      generationParamsNotifierProvider.select(selectPreviewDimensionsViewData),
    );
    final guide = ref.watch(compositionGuideNotifierProvider);
    final backdrop = ref.watch(
      characterPlaceOptionsProvider.select((options) => options.backdrop),
    );
    final ratio = dimensions.width / dimensions.height;
    final included = [
      for (final character in config.characters)
        if (character.enabled) character,
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const margin = CharacterPlaceCanvas.margin;
        final room = Size(
          math.max(0, constraints.maxWidth - margin * 2),
          math.max(0, constraints.maxHeight - margin * 2),
        );
        _picture = room.isEmpty
            ? Size.zero
            : room.width / room.height > ratio
            ? Size(room.height * ratio, room.height)
            : Size(room.width, room.width / ratio);
        return Center(
          child: SizedBox(
            width: _picture.width + margin * 2,
            height: _picture.height + margin * 2,
            child: Semantics(
              label: context.l10n.characterPanel_canvas,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: margin,
                    top: margin,
                    width: _picture.width,
                    height: _picture.height,
                    child: _Picture(
                      key: const ValueKey('character-place-picture'),
                      ratio: ratio,
                      backdrop: backdrop,
                      guide: guide,
                      empty: included.isEmpty,
                    ),
                  ),
                  Positioned.fill(
                    child: GestureDetector(
                      key: const ValueKey('character-place-gestures'),
                      behavior: HitTestBehavior.opaque,
                      dragStartBehavior: DragStartBehavior.down,
                      onTapUp: _onTapUp,
                      onPanStart: _onPanStart,
                      onPanUpdate: _onPanUpdate,
                      onPanEnd: (_) => _onPanEnd(),
                      onPanCancel: _onPanEnd,
                    ),
                  ),
                  for (final character in included)
                    ..._marker(config, character),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _marker(
    CharacterPromptConfig config,
    CharacterPrompt character,
  ) {
    final center = _local(_positionOf(config, character));
    final selected = character.id == widget.selectedId;
    final dragging = character.id == _dragId;
    final unit = _positionOf(config, character);
    const radius = CharacterPlaceCanvas.markerDiameter / 2;
    final duration = MediaQuery.disableAnimationsOf(context) || dragging
        ? Duration.zero
        : const Duration(milliseconds: 200);
    const curve = Curves.easeOutCubic;
    return [
      AnimatedPositioned(
        key: ValueKey('character-place-marker-${character.id}'),
        duration: duration,
        curve: curve,
        left: center.dx - radius,
        top: center.dy - radius,
        width: radius * 2,
        height: radius * 2,
        child: IgnorePointer(
          child: Semantics(
            selected: selected,
            label: context.l10n.characterPanel_marker(
              character.name,
              (unit.dx * 100).round(),
              (unit.dy * 100).round(),
            ),
            child: AnimatedScale(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 160),
              scale: selected ? 1.12 : 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.32),
                            spreadRadius: 6,
                          ),
                        ]
                      : null,
                ),
                child: CharacterMarkerDisc(
                  colors: CharacterMarkerPalette.of(
                    config.characters,
                    character,
                  ),
                  diameter: CharacterPlaceCanvas.markerDiameter,
                  ringWidth: 3,
                  elevated: true,
                ),
              ),
            ),
          ),
        ),
      ),
      AnimatedPositioned(
        key: ValueKey('character-place-label-${character.id}'),
        duration: duration,
        curve: curve,
        left: center.dx - 64,
        top: center.dy + radius + 6,
        width: 128,
        child: IgnorePointer(
          child: ExcludeSemantics(
            child: Center(child: _NameLabel(name: character.name)),
          ),
        ),
      ),
    ];
  }
}

class _NameLabel extends StatelessWidget {
  const _NameLabel({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x24000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// The picture behind the markers: the latest image when it has the same
/// shape as the next generation, otherwise a quiet surface.
class _Picture extends ConsumerWidget {
  const _Picture({
    super.key,
    required this.ratio,
    required this.backdrop,
    required this.guide,
    required this.empty,
  });

  final double ratio;
  final bool backdrop;
  final CompositionGuideSettings guide;
  final bool empty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final image = backdrop
        ? ref.watch(
            imageGenerationNotifierProvider.select(
              (state) => selectDisplayImages(state).firstOrNull,
            ),
          )
        : null;
    final matching =
        image != null &&
        image.height > 0 &&
        (image.width / image.height - ratio).abs() < 0.01;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x24000000),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: LayoutBuilder(
          builder: (context, constraints) => Stack(
            fit: StackFit.expand,
            children: [
              if (matching) ...[
                DecodedMemoryImage(
                  bytes: image.bytes,
                  fit: BoxFit.cover,
                  maxLogicalWidth: constraints.maxWidth,
                  maxLogicalHeight: constraints.maxHeight,
                  gaplessPlayback: true,
                ),
                const ColoredBox(color: Color(0x26000000)),
              ] else
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        colors.surfaceContainerLow,
                        colors.surfaceContainerHighest,
                      ],
                    ),
                  ),
                ),
              CompositionGuideOverlay(
                mode: guide.mode,
                columns: guide.columns,
                rows: guide.rows,
              ),
              if (empty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      context.l10n.characterPanel_noneIncluded,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
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
