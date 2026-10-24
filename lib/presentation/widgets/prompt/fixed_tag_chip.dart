import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/utils/localization_extension.dart';
import '../../../data/models/fixed_tag/fixed_tag_entry.dart';
import '../../adaptive/interaction_policy.dart';
import '../../themes/core/layered_surface_style.dart';

/// One fixed tag in the management grid: its name, and under it what sets it
/// apart (suffix position, weight, links).
///
/// Tapping toggles whether the tag is applied; an applied tag sits on the
/// light theme color inside a theme-colored outline. Everything else lives in
/// the details opened by long-press on touch or right-click with a mouse.
class FixedTagChip extends StatefulWidget {
  const FixedTagChip({
    super.key,
    required this.entry,
    required this.onToggle,
    required this.onShowDetails,
    this.linkCount = 0,
  });

  final FixedTagEntry entry;
  final VoidCallback onToggle;
  final VoidCallback onShowDetails;

  /// Linked tags switch together, so the chip marks that a tap affects more.
  final int linkCount;

  /// The height that fits a name and a line of markers at [textScaler].
  static double extentFor(
    BuildContext context, {
    required TextScaler textScaler,
  }) {
    final theme = Theme.of(context);
    final name = textScaler.scale(theme.textTheme.bodyMedium?.fontSize ?? 14);
    final markers = textScaler.scale(
      theme.textTheme.labelSmall?.fontSize ?? 11,
    );
    // A chip shows a name with markers under it, or a name on two lines.
    final content = math.max(
      name * _nameLineHeight * 2,
      name * _nameLineHeight + markers * _markerLineHeight,
    );
    return math.max(
      content + 16,
      context.interactionPolicy.minimumControlExtent,
    );
  }

  @override
  State<FixedTagChip> createState() => _FixedTagChipState();
}

class _FixedTagChipState extends State<FixedTagChip> {
  bool _hovering = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final entry = widget.entry;
    final selected = entry.enabled;
    final base = selected
        ? colors.primaryContainer
        : controlSurfaceColor(colors);
    final background = _hovering
        ? Color.alphaBlend(colors.onSurface.withValues(alpha: 0.05), base)
        : base;
    final borderColor = selected
        ? colors.primary
        : _focused
        ? colors.outline
        : Colors.transparent;
    final radius = BorderRadius.circular(12);
    final markers = _markers(context);
    final linked = widget.linkCount > 0;
    final showMarkers = markers.isNotEmpty || linked;
    return Semantics(
      selected: selected,
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          key: ValueKey('fixed-tag-entry-${entry.id}'),
          borderRadius: radius,
          mouseCursor: SystemMouseCursors.click,
          hoverColor: Colors.transparent,
          focusColor: Colors.transparent,
          highlightColor: Colors.transparent,
          splashColor: colors.primary.withValues(alpha: 0.12),
          onTap: widget.onToggle,
          onLongPress: () {
            HapticFeedback.mediumImpact();
            widget.onShowDetails();
          },
          onSecondaryTapUp: (_) => widget.onShowDetails(),
          onHover: context.interactionPolicy.precisePointerAvailable
              ? (value) => setState(() => _hovering = value)
              : null,
          onFocusChange: (value) => setState(() => _focused = value),
          child: Ink(
            decoration: BoxDecoration(
              color: background,
              borderRadius: radius,
              border: Border.all(color: borderColor, width: 1.5),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.displayName,
                  maxLines: showMarkers ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    height: _nameLineHeight,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected
                        ? colors.onPrimaryContainer
                        : colors.onSurface,
                  ),
                ),
                if (showMarkers)
                  _MarkersLine(
                    entryId: entry.id,
                    labels: markers,
                    linked: linked,
                    color: selected
                        ? colors.onPrimaryContainer.withValues(alpha: 0.72)
                        : colors.onSurfaceVariant,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Text markers; a link shows as an icon after them.
  List<String> _markers(BuildContext context) {
    final entry = widget.entry;
    return [
      if (entry.position == FixedTagPosition.suffix)
        context.l10n.fixedTags_suffix,
      if ((entry.weight - 1).abs() > 0.001) '×${_weightLabel(entry.weight)}',
    ];
  }

  static String _weightLabel(double weight) {
    final fixed = weight.toStringAsFixed(2);
    return fixed
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
}

class _MarkersLine extends StatelessWidget {
  const _MarkersLine({
    required this.entryId,
    required this.labels,
    required this.linked,
    required this.color,
  });

  final String entryId;
  final List<String> labels;
  final bool linked;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.labelSmall?.copyWith(color: color, height: _markerLineHeight);
    final text = labels.join(' · ');
    return Row(
      children: [
        if (text.isNotEmpty)
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        if (linked) ...[
          if (text.isNotEmpty) Text(' · ', style: style),
          Icon(
            Icons.link_rounded,
            key: ValueKey('fixed-tag-link-mark-$entryId'),
            size: (style?.fontSize ?? 11) + 2,
            color: color,
          ),
        ],
      ],
    );
  }
}

const double _nameLineHeight = 1.25;
const double _markerLineHeight = 1.35;
