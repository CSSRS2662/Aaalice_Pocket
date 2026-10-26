import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Keeps explanations available without turning every parameter into a paragraph.
class DlssParameterRow extends StatefulWidget {
  const DlssParameterRow({
    super.key,
    required this.label,
    required this.description,
    this.trailing,
    this.trailingWidth,
    this.error,
    this.valueLabel,
  });
  final String label;
  final String description;
  final Widget? trailing;

  /// The width [trailing] needs, such as a number field sized to its value.
  /// When the row cannot give it that much beside the label, it goes under
  /// the label instead of being squeezed. Null keeps a compact width that
  /// grows a little with the text.
  final double? trailingWidth;
  final String? error;
  final String? valueLabel;

  @override
  State<DlssParameterRow> createState() => _DlssParameterRowState();
}

class _DlssParameterRowState extends State<DlssParameterRow> {
  bool _showHelp = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final trailing = widget.trailing;
            final wanted = widget.trailingWidth;
            final labelStyle = theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            );
            // A sized trailing stays beside the label only while the label
            // still fits on one line next to it; otherwise it goes below.
            final room = wanted == null
                ? constraints.maxWidth * 0.42
                : math.min(
                    constraints.maxWidth * 0.42,
                    constraints.maxWidth -
                        52 -
                        _labelWidth(context, widget.label, labelStyle),
                  );
            final title = Row(
              children: [
                Expanded(child: Text(widget.label, style: labelStyle)),
                IconButton(
                  key: ValueKey('dlss-help-${widget.label}'),
                  tooltip: widget.label,
                  isSelected: _showHelp,
                  onPressed: () => setState(() => _showHelp = !_showHelp),
                  icon: const Icon(Icons.info_outline, size: 17),
                  selectedIcon: const Icon(Icons.info, size: 17),
                  color: theme.colorScheme.onSurfaceVariant,
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                ),
                if (trailing != null && (wanted == null || wanted <= room)) ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    width:
                        wanted ??
                        math.min(
                          room,
                          96 *
                              math.sqrt(
                                MediaQuery.textScalerOf(context).scale(1),
                              ),
                        ),
                    child: trailing,
                  ),
                ],
              ],
            );
            if (trailing == null || wanted == null || wanted <= room) {
              return title;
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                title,
                SizedBox(
                  width: math.min(wanted, constraints.maxWidth),
                  child: trailing,
                ),
              ],
            );
          },
        ),
        if (widget.valueLabel != null)
          Text(
            widget.valueLabel!,
            textAlign: TextAlign.end,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        if (_showHelp)
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 8),
            child: Text(
              widget.description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w400,
                height: 1.5,
              ),
            ),
          ),
        if (widget.error != null)
          Text(
            widget.error!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
      ],
    );
  }
}

InputDecoration dlssNumberDecoration(BuildContext context) {
  final colors = Theme.of(context).colorScheme;
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: BorderSide.none,
  );
  return InputDecoration(
    filled: true,
    fillColor: colors.surfaceContainerHighest,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: border,
    enabledBorder: border,
    disabledBorder: border,
    focusedBorder: border.copyWith(
      borderSide: BorderSide(color: colors.primary),
    ),
  );
}

double _labelWidth(BuildContext context, String text, TextStyle? style) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: DefaultTextStyle.of(context).style.merge(style),
    ),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final width = painter.width.ceilToDouble();
  painter.dispose();
  return width;
}
