import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Room a one-line field keeps after its text for the caret: the caret
/// width and the gap before it, with a pixel to spare for rounding.
const double oneLineFieldCaretRoom = 4;

/// The width a one-line field needs so that every one of [samples] shows in
/// full: the widest sample in [style] at the current text scale, plus the
/// field's [horizontalPadding] (both sides together), [extra] room for a
/// prefix or suffix, and the caret. A field narrower than this scrolls its
/// text sideways under the finger even though nothing is hidden.
///
/// [style] is merged over the theme's `bodyLarge`, the style text fields use
/// by default.
double oneLineFieldWidth(
  BuildContext context, {
  required Iterable<String> samples,
  TextStyle? style,
  required double horizontalPadding,
  double extra = 0,
  double minWidth = 0,
}) {
  final effective = (Theme.of(context).textTheme.bodyLarge ?? const TextStyle())
      .merge(style);
  final scaler = MediaQuery.textScalerOf(context);
  final direction = Directionality.of(context);
  var widest = 0.0;
  for (final sample in samples) {
    final painter = TextPainter(
      text: TextSpan(text: sample, style: effective),
      textScaler: scaler,
      textDirection: direction,
      maxLines: 1,
    )..layout();
    widest = math.max(widest, painter.width);
    painter.dispose();
  }
  final needed = widest + horizontalPadding + extra + oneLineFieldCaretRoom;
  return math.max(minWidth, needed.ceilToDouble());
}

/// Gives a one-line field at least [minWidth] and otherwise the width its
/// content, padding, decoration and caret need, up to [maxWidth]: a short
/// number always shows whole and never scrolls sideways under the finger.
/// The field must not contain a `LayoutBuilder`.
class ContentWidthField extends StatelessWidget {
  const ContentWidthField({
    super.key,
    required this.minWidth,
    this.maxWidth = double.infinity,
    required this.child,
  });

  final double minWidth;
  final double maxWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(minWidth: minWidth, maxWidth: maxWidth),
    child: IntrinsicWidth(child: child),
  );
}
