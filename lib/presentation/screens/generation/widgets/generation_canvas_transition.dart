import 'package:flutter/material.dart';

import '../../../themes/theme_extension.dart';
import '../../../widgets/common/generation_visual_transition.dart';

class GenerationCanvasTransition extends StatefulWidget {
  const GenerationCanvasTransition({
    super.key,
    required this.generating,
    required this.hasImage,
    required this.child,
  });

  final bool generating;
  final bool hasImage;
  final Widget child;

  @override
  State<GenerationCanvasTransition> createState() =>
      _GenerationCanvasTransitionState();
}

class _GenerationCanvasTransitionState extends State<GenerationCanvasTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _opacity =
      AnimationController(vsync: this, value: 1)..addStatusListener((status) {
        if (status == AnimationStatus.dismissed && _outgoing != null) {
          setState(_clearOutgoing);
          _opacity.forward();
        }
      });
  Widget? _outgoing;
  int _contentVersion = 0;

  @override
  void didUpdateWidget(covariant GenerationCanvasTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.generating &&
        !oldWidget.generating &&
        oldWidget.hasImage &&
        _outgoing == null) {
      if (MediaQuery.disableAnimationsOf(context)) return;
      _outgoing = oldWidget.child;
      final motion = Theme.of(context).appTheme;
      _opacity
        ..duration = motion.fastDuration
        ..reverseDuration = motion.normalDuration
        ..reverse();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      if (_outgoing != null) _clearOutgoing();
      _opacity.value = 1;
    }
  }

  void _clearOutgoing() {
    _outgoing = null;
    _contentVersion++;
  }

  @override
  void dispose() {
    _opacity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final exiting = _outgoing != null;
    return FadeTransition(
      opacity: _opacity,
      child: IgnorePointer(
        ignoring: exiting,
        child: ExcludeSemantics(
          excluding: exiting,
          child: GenerationVisualTransition(
            key: ValueKey(_contentVersion),
            stage: widget.generating && !exiting,
            child: _outgoing ?? widget.child,
          ),
        ),
      ),
    );
  }
}
