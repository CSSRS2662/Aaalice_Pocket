import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Grid geometry for the library list: two columns on a phone, more on wider
/// panes, one when large text leaves too little room.
@immutable
class TagLibraryGridLayout {
  const TagLibraryGridLayout({
    required this.columns,
    required this.mainAxisExtent,
    required this.padding,
  });

  static const double spacing = 8;
  static const int preferredColumns = 2;
  static const double maxCellWidth = 320;

  final int columns;
  final double mainAxisExtent;
  final double padding;

  SliverGridDelegate get delegate => SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: columns,
    mainAxisExtent: mainAxisExtent,
    mainAxisSpacing: spacing,
    crossAxisSpacing: spacing,
  );
}

/// The layout for [availableWidth] with cards [cardExtent] tall.
TagLibraryGridLayout computeTagLibraryGridLayout(
  double availableWidth,
  double textScale, {
  required double cardExtent,
}) {
  final padding = availableWidth < 600 ? 12.0 : 16.0;
  final width = math.max(0.0, availableWidth - padding * 2);
  const spacing = TagLibraryGridLayout.spacing;
  final minCell = 140 * textScale.clamp(1.0, 3.0);
  final fitting = math.max(
    1,
    ((width + spacing) / (minCell + spacing)).floor(),
  );
  // Cards stop growing at maxCellWidth; wider panes add columns instead.
  final needed =
      ((width + spacing) / (TagLibraryGridLayout.maxCellWidth + spacing))
          .ceil();
  final columns = math.min(
    fitting,
    math.max(TagLibraryGridLayout.preferredColumns, needed),
  );
  return TagLibraryGridLayout(
    columns: columns,
    mainAxisExtent: cardExtent,
    padding: padding,
  );
}
