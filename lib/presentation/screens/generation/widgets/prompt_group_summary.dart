import 'package:flutter/material.dart';

import '../../../../core/utils/prompt_edit_document.dart';

/// Two-line preview of a prompt section: whole tags only, then `+N` for the
/// tags that did not fit instead of an ellipsis.
class PromptGroupSummary extends StatelessWidget {
  const PromptGroupSummary({
    super.key,
    required this.text,
    required this.style,
    required this.emptyLabel,
  });

  static const int maxLines = 2;

  final String text;
  final TextStyle style;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final items = PromptEditDocument.parse(text);
    if (items.isEmpty) {
      return Text(
        emptyLabel,
        style: style.copyWith(color: colors.onSurfaceVariant),
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScaler = MediaQuery.textScalerOf(context);
        final direction = Directionality.of(context);
        TextSpan build(int shown) =>
            summarySpan(items, shown, style: style, colors: colors);
        final shown = fitShownCount(
          itemCount: items.length,
          build: build,
          maxWidth: constraints.maxWidth,
          textScaler: textScaler,
          textDirection: direction,
        );
        return Text.rich(
          build(shown),
          maxLines: maxLines,
          overflow: TextOverflow.clip,
        );
      },
    );
  }

  /// The largest number of leading items whose preview, including the `+N`
  /// remainder, still fits in [maxLines]. At least one item is always shown.
  @visibleForTesting
  static int fitShownCount({
    required int itemCount,
    required TextSpan Function(int shown) build,
    required double maxWidth,
    required TextScaler textScaler,
    required TextDirection textDirection,
  }) {
    bool fits(int shown) {
      final painter = TextPainter(
        text: build(shown),
        maxLines: maxLines,
        textScaler: textScaler,
        textDirection: textDirection,
      )..layout(maxWidth: maxWidth);
      final exceeded = painter.didExceedMaxLines;
      painter.dispose();
      return !exceeded;
    }

    if (itemCount <= 1 || fits(itemCount)) return itemCount;
    var low = 1;
    var high = itemCount - 1;
    while (low < high) {
      final mid = (low + high + 1) ~/ 2;
      if (fits(mid)) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return low;
  }

  /// Raw prompt text of the first [shown] items, weight syntax dimmed and
  /// disabled tags struck through, followed by the hidden tag count.
  static TextSpan summarySpan(
    List<PromptEditSpan> items,
    int shown, {
    required TextStyle style,
    required ColorScheme colors,
  }) {
    final dim = TextStyle(color: colors.onSurfaceVariant);
    final children = <InlineSpan>[];
    for (var index = 0; index < shown && index < items.length; index++) {
      if (index > 0) children.add(const TextSpan(text: ', '));
      final item = items[index];
      if (item.disabled) {
        children.add(
          TextSpan(
            text: item.text,
            style: dim.copyWith(decoration: TextDecoration.lineThrough),
          ),
        );
      } else if (item.prefix.isNotEmpty || item.suffix.isNotEmpty) {
        children.addAll([
          TextSpan(text: item.prefix, style: dim),
          TextSpan(text: item.label),
          TextSpan(text: item.suffix, style: dim),
        ]);
      } else {
        children.add(TextSpan(text: item.raw));
      }
    }
    final hidden = hiddenTagCount(items, shown);
    if (hidden > 0) {
      children.add(
        TextSpan(
          text: ' +$hidden',
          style: TextStyle(color: colors.primary, fontWeight: FontWeight.w700),
        ),
      );
    }
    return TextSpan(style: style, children: children);
  }

  /// Tags left out of the preview; a weighted group counts each of its tags.
  static int hiddenTagCount(List<PromptEditSpan> items, int shown) {
    var count = 0;
    for (final item in items.skip(shown)) {
      count += item.disabled ? 1 : item.leaves.length;
    }
    return count;
  }
}
