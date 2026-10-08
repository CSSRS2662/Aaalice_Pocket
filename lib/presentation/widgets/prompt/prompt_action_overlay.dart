import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../themes/core/layered_surface_style.dart';

/// A thin boundary keeps the floating editor identifiable over similar neutral
/// surfaces without adding outlines to its individual controls. Given less
/// height than its content needs, the content scrolls inside the boundary.
class PromptActionSurface extends StatelessWidget {
  const PromptActionSurface({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: overlaySurfaceColor(colors),
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(child: child),
    );
  }
}

/// Measures the real action content before positioning it. Translation length,
/// text scaling and the keyboard therefore cannot invalidate a fixed height.
///
/// The actions sit above [anchor] when they fit there, otherwise below it, so
/// they never cover the text they act on; when neither side has room they
/// shrink to the roomier one and scroll.
class PromptActionOverlay extends StatelessWidget {
  const PromptActionOverlay({
    super.key,
    required this.anchor,
    required this.overlaySize,
    required this.child,
    this.gap = 6,
    this.gapBelow,
  });
  final Rect anchor;
  final Size overlaySize;
  final Widget child;

  /// Space between [anchor] and the actions above it.
  final double gap;

  /// Space between [anchor] and the actions below it, defaulting to [gap].
  /// Touch selections hang their handles below the text.
  final double? gapBelow;

  /// Edges covered by system bars or the keyboard. A Scaffold or a sheet may
  /// already have removed them for the field, yet they still cover the
  /// overlay the actions are laid out in, so take the widest of each source.
  static EdgeInsets _coveredEdges(BuildContext context) {
    var edges = EdgeInsets.zero;
    for (final media in [
      MediaQuery.maybeOf(context),
      for (final source in [
        Scaffold.maybeOf(context)?.context,
        Overlay.maybeOf(context)?.context,
      ])
        source?.getInheritedWidgetOfExactType<MediaQuery>()?.data,
    ]) {
      if (media == null) continue;
      edges = EdgeInsets.fromLTRB(
        math.max(edges.left, media.padding.left),
        math.max(edges.top, media.padding.top),
        math.max(edges.right, media.padding.right),
        math.max(
          edges.bottom,
          math.max(media.padding.bottom, media.viewInsets.bottom),
        ),
      );
    }
    return edges;
  }

  @override
  Widget build(BuildContext context) {
    final edges = _coveredEdges(context);
    final left = edges.left + 8;
    final top = edges.top + 8;
    final right = math.max(left, overlaySize.width - edges.right - 8);
    final bottom = math.max(top, overlaySize.height - edges.bottom - 8);
    return Positioned.fill(
      child: CustomSingleChildLayout(
        delegate: _PromptActionLayout(
          anchor,
          Rect.fromLTRB(left, top, right, bottom),
          gap: gap,
          gapBelow: gapBelow ?? gap,
        ),
        // The surface inside scrolls when the height is capped.
        child: KeyedSubtree(
          key: const ValueKey('prompt-action-viewport'),
          child: child,
        ),
      ),
    );
  }
}

class _PromptActionLayout extends SingleChildLayoutDelegate {
  const _PromptActionLayout(
    this.anchor,
    this.bounds, {
    required this.gap,
    required this.gapBelow,
  });
  final Rect anchor;
  final Rect bounds;
  final double gap;
  final double gapBelow;

  /// The least height worth scrolling in. With less room on both sides the
  /// actions keep their size and cover part of the anchor instead.
  static const double minScrollableHeight = 96;

  double get _roomAbove => anchor.top - gap - bounds.top;
  double get _roomBelow => bounds.bottom - anchor.bottom - gapBelow;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    // Too tall for either side (large text): shrink to the roomier side and
    // scroll, rather than cover what the actions act on.
    final room = math.max(_roomAbove, _roomBelow);
    return BoxConstraints(
      maxWidth: math.min(420, bounds.width),
      maxHeight: room >= minScrollableHeight
          ? math.min(room, bounds.height)
          : bounds.height,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final above = anchor.top - gap - childSize.height;
    final below = anchor.bottom + gapBelow;
    final double y;
    if (childSize.height <= _roomAbove) {
      y = above;
    } else if (childSize.height <= _roomBelow) {
      y = below;
    } else {
      y = _roomAbove >= _roomBelow ? above : below;
    }
    return Offset(
      anchor.left.clamp(
        bounds.left,
        math.max(bounds.left, bounds.right - childSize.width),
      ),
      y.clamp(
        bounds.top,
        math.max(bounds.top, bounds.bottom - childSize.height),
      ),
    );
  }

  @override
  bool shouldRelayout(_PromptActionLayout oldDelegate) =>
      anchor != oldDelegate.anchor ||
      bounds != oldDelegate.bounds ||
      gap != oldDelegate.gap ||
      gapBelow != oldDelegate.gapBelow;
}
