import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../adaptive/window_size_class.dart';
import 'inverse_action_bar.dart';

/// A short notice with one action, shown as an [InverseActionBar] floating
/// near the bottom of the screen: above the page's bottom bar, the system
/// navigation area and the keyboard. It closes on its own after [duration]
/// or when the action is used, and a new notice replaces the current one.
abstract final class ActionNotice {
  static const duration = Duration(seconds: 4);
  static const _gap = 12.0;

  static OverlayEntry? _entry;
  static Timer? _timer;

  static void show(
    BuildContext context, {
    required String message,
    required String actionLabel,
    required VoidCallback onAction,
    Key? actionKey,
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    final bottom = _bottomClearance(context, overlay) + _gap;
    dismiss();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ActionNoticeView(
        bottom: bottom,
        bar: InverseActionBar(
          key: const ValueKey('action_notice'),
          message: message,
          actionLabel: actionLabel,
          actionKey: actionKey,
          onAction: () {
            _remove(entry);
            onAction();
          },
        ),
      ),
    );
    _entry = entry;
    overlay.insert(entry);
    _timer = Timer(duration, () => _remove(entry));
  }

  static void dismiss() {
    final entry = _entry;
    if (entry != null) _remove(entry);
  }

  static void _remove(OverlayEntry entry) {
    if (!identical(_entry, entry)) return;
    _timer?.cancel();
    _timer = null;
    _entry = null;
    // Inserted by [show] and removed only here, so it is still in the
    // overlay even before its first frame.
    entry
      ..remove()
      ..dispose();
  }

  /// How far the page's own bottom chrome reaches up from the bottom of
  /// [overlay]: the bottom bar of any scaffold around [context], the system
  /// navigation area or the keyboard, whichever is taller.
  static double _bottomClearance(BuildContext context, OverlayState overlay) {
    final media = MediaQuery.of(context);
    var clearance = math.max(media.viewPadding.bottom, media.viewInsets.bottom);
    final overlayBox = overlay.context.findRenderObject();
    if (overlayBox is! RenderBox || !overlayBox.hasSize) return clearance;
    for (
      var scaffold = Scaffold.maybeOf(context);
      scaffold != null;
      scaffold = Scaffold.maybeOf(scaffold.context)
    ) {
      final bar = _bottomBar(scaffold);
      if (bar == null) continue;
      final top = overlayBox.globalToLocal(bar.localToGlobal(Offset.zero)).dy;
      clearance = math.max(clearance, overlayBox.size.height - top);
    }
    return clearance;
  }

  /// The laid-out box of [scaffold]'s bottom bar, when it has one. The
  /// scaffold's geometry is only readable while painting, so the bar is
  /// found as the element built from that exact widget.
  static RenderBox? _bottomBar(ScaffoldState scaffold) {
    final bar = scaffold.widget.bottomNavigationBar;
    if (bar == null) return null;
    RenderBox? found;
    void visit(Element element) {
      if (found != null) return;
      if (identical(element.widget, bar)) {
        final box = element.findRenderObject();
        if (box is RenderBox && box.attached && box.hasSize) found = box;
        return;
      }
      element.visitChildElements(visit);
    }

    scaffold.context.visitChildElements(visit);
    return found;
  }
}

class _ActionNoticeView extends StatelessWidget {
  const _ActionNoticeView({required this.bottom, required this.bar});

  final double bottom;
  final Widget bar;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final compact = WindowSizeClass.fromWidth(media.size.width).isCompact;
    final inset = compact ? 12.0 : 16.0;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Positioned(
      left: media.padding.left + inset,
      right: media.padding.right + inset,
      bottom: bottom,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: reduceMotion ? 1 : 0, end: 1),
            duration: const Duration(milliseconds: 180),
            builder: (context, value, child) => Opacity(
              opacity: value,
              child: FractionalTranslation(
                translation: Offset(0, 0.4 * (1 - value)),
                child: child,
              ),
            ),
            child: bar,
          ),
        ),
      ),
    );
  }
}
