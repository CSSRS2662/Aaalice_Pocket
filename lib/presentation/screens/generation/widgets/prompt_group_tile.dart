import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../../core/utils/prompt_edit_document.dart';
import '../../../themes/core/layered_surface_style.dart';
import '../../../themes/theme_extension.dart';
import 'prompt_group_controller.dart';
import 'prompt_group_summary.dart';

/// Geometry shared by the grid layout and its tiles.
class PromptGroupTileMetrics {
  const PromptGroupTileMetrics._(this.textStyle, this.height);

  /// Width of the dot and the cross at the two ends of a tile, and the least
  /// height of their touch targets.
  static const double controlExtent = 44;
  static const double verticalPadding = 9;

  /// A tile is as tall as its two summary lines.
  factory PromptGroupTileMetrics.of(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.bodyMedium!.copyWith(fontSize: 13, height: 1.45);
    final lineHeight =
        MediaQuery.textScalerOf(context).scale(style.fontSize!) * style.height!;
    final textHeight =
        PromptGroupSummary.maxLines * lineHeight + 2 * verticalPadding;
    return PromptGroupTileMetrics._(
      style,
      math.max(controlExtent, textHeight).ceilToDouble(),
    );
  }

  final TextStyle textStyle;
  final double height;
}

/// One prompt section in the grid, two summary lines tall: the enable dot at
/// the start, the summary, and a two-tap delete cross at the end. Gestures
/// for opening, menus and dragging belong to the grid.
class PromptGroupTile extends StatelessWidget {
  const PromptGroupTile({
    super.key,
    required this.section,
    required this.index,
    required this.metrics,
    required this.deleteArmed,
    required this.onOpen,
    required this.onToggleEnabled,
    required this.onDeleteTap,
    required this.onDisarmDelete,
    required this.onShowActions,
  });

  final PromptGroupSection section;
  final int index;
  final PromptGroupTileMetrics metrics;
  final bool deleteArmed;
  final VoidCallback onOpen;
  final VoidCallback onToggleEnabled;
  final VoidCallback onDeleteTap;
  final VoidCallback onDisarmDelete;
  final VoidCallback onShowActions;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final enabled = section.enabled;
    final label = l10n.prompt_groupLabel(index + 1);
    final plainText = PromptEditDocument.parse(
      section.controller.text,
    ).map((item) => item.text).join(', ');

    return Material(
      color: sectionSurfaceColor(colors),
      borderRadius: BorderRadius.circular(
        Theme.of(context).appTheme.cardRadius,
      ),
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        customSemanticsActions: {
          CustomSemanticsAction(label: l10n.common_moreActions): onShowActions,
        },
        child: InkWell(
          key: ValueKey('prompt_group_tile_${section.id}'),
          onTap: onOpen,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _EnableDot(
                key: ValueKey('prompt_group_enabled_${section.id}'),
                enabled: enabled,
                tooltip: enabled
                    ? l10n.prompt_groupDisable
                    : l10n.prompt_groupEnable,
                onTap: onToggleEnabled,
              ),
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 160),
                    opacity: enabled ? 1 : 0.5,
                    child: Semantics(
                      label: [
                        label,
                        if (!enabled) l10n.prompt_groupOff,
                        plainText.isEmpty ? l10n.prompt_emptyGroup : plainText,
                      ].join('，'),
                      excludeSemantics: true,
                      child: PromptGroupSummary(
                        text: section.controller.text,
                        style: metrics.textStyle.copyWith(
                          color: colors.onSurface,
                        ),
                        emptyLabel: l10n.prompt_groupEmptyHint,
                      ),
                    ),
                  ),
                ),
              ),
              _DeleteCross(
                key: ValueKey('prompt_group_delete_${section.id}'),
                armed: deleteArmed,
                tooltip: deleteArmed
                    ? l10n.prompt_groupDeleteAgain
                    : l10n.prompt_deleteGroup,
                onTap: onDeleteTap,
                onTapOutside: onDisarmDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Empty slot left behind while its tile is being dragged.
class PromptGroupTilePlaceholder extends StatelessWidget {
  const PromptGroupTilePlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(
          Theme.of(context).appTheme.cardRadius,
        ),
        border: Border.all(color: colors.outlineVariant, width: 1.5),
      ),
    );
  }
}

class _EnableDot extends StatelessWidget {
  const _EnableDot({
    super.key,
    required this.enabled,
    required this.tooltip,
    required this.onTap,
  });

  final bool enabled;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        toggled: enabled,
        child: InkResponse(
          onTap: onTap,
          radius: 22,
          child: SizedBox(
            width: PromptGroupTileMetrics.controlExtent,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 18,
                height: 18,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: enabled ? colors.primary : colors.outline,
                    width: 2,
                  ),
                ),
                child: enabled
                    ? DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const SizedBox.square(dimension: 8),
                      )
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A bare cross; the first tap arms it as a red circle, the second deletes.
class _DeleteCross extends StatelessWidget {
  const _DeleteCross({
    super.key,
    required this.armed,
    required this.tooltip,
    required this.onTap,
    required this.onTapOutside,
  });

  final bool armed;
  final String tooltip;
  final VoidCallback onTap;
  final VoidCallback onTapOutside;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return TapRegion(
      onTapOutside: armed ? (_) => onTapOutside() : null,
      child: Tooltip(
        message: tooltip,
        child: Semantics(
          button: true,
          child: InkResponse(
            onTap: onTap,
            radius: 22,
            child: SizedBox(
              width: PromptGroupTileMetrics.controlExtent,
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: armed ? colors.error : Colors.transparent,
                  ),
                  child: Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: armed ? colors.onError : colors.onSurfaceVariant,
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
