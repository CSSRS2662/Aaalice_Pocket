import 'dart:async';

import 'package:flutter/widgets.dart';

/// Pads [child] by the keyboard height without following the keyboard's
/// slide.
///
/// Following the inset frame by frame relays out the whole panel on every
/// frame of the system animation, which stutters. Here the padding jumps up
/// once the keyboard has finished opening and drops at once when it starts
/// to close. Descendants see no bottom view inset, so they do not rebuild
/// while the keyboard moves.
class KeyboardSettledPadding extends StatefulWidget {
  const KeyboardSettledPadding({
    super.key,
    required this.child,
    this.settleDelay = const Duration(milliseconds: 80),
  });

  final Widget child;

  /// How long the inset must stay unchanged before it counts as settled.
  final Duration settleDelay;

  @override
  State<KeyboardSettledPadding> createState() => _KeyboardSettledPaddingState();
}

class _KeyboardSettledPaddingState extends State<KeyboardSettledPadding> {
  double _target = 0;
  double _applied = 0;
  Timer? _settle;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    // A menu or dialog above this route owns the keyboard.
    final target = route != null && !route.isCurrent
        ? 0.0
        : MediaQuery.viewInsetsOf(context).bottom;
    if (target == _target) return;
    _target = target;
    _settle?.cancel();
    // Closing: drop the padding at once instead of trailing the keyboard.
    if (target < _applied) _applied = 0;
    if (_applied == target) return;
    _settle = Timer(widget.settleDelay, () {
      if (mounted && _applied != _target) setState(() => _applied = _target);
    });
  }

  @override
  void dispose() {
    _settle?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: _applied),
      child: MediaQuery.removeViewInsets(
        context: context,
        removeBottom: true,
        child: widget.child,
      ),
    );
  }
}
