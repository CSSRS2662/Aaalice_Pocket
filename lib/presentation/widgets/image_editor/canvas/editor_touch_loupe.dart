import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/editor_state.dart';

/// The corner of the canvas the loupe sits in.
enum TouchLoupeCorner { topLeft, topRight, bottomLeft }

/// Where the loupe goes in a canvas of [size] while the finger is at
/// [finger]: it stays in [current] until the finger comes within
/// [clearance] of it, then moves to the other top corner, or to the bottom
/// left when the finger is near both. Staying put until then keeps it from
/// jumping back and forth while the finger moves along the top.
({Rect rect, TouchLoupeCorner corner}) placeTouchLoupe({
  required Size size,
  required Offset finger,
  required TouchLoupeCorner current,
  required double diameter,
  double margin = 12,
  double clearance = 40,
}) {
  Rect rectOf(TouchLoupeCorner corner) => switch (corner) {
    TouchLoupeCorner.topLeft => Rect.fromLTWH(
      margin,
      margin,
      diameter,
      diameter,
    ),
    TouchLoupeCorner.topRight => Rect.fromLTWH(
      size.width - margin - diameter,
      margin,
      diameter,
      diameter,
    ),
    TouchLoupeCorner.bottomLeft => Rect.fromLTWH(
      margin,
      size.height - margin - diameter,
      diameter,
      diameter,
    ),
  };
  bool clear(TouchLoupeCorner corner) =>
      !rectOf(corner).inflate(clearance).contains(finger);

  final order = [
    current,
    if (current == TouchLoupeCorner.topLeft) TouchLoupeCorner.topRight,
    if (current != TouchLoupeCorner.topLeft) TouchLoupeCorner.topLeft,
    if (current == TouchLoupeCorner.bottomLeft) TouchLoupeCorner.topRight,
    if (current != TouchLoupeCorner.bottomLeft) TouchLoupeCorner.bottomLeft,
  ];
  final corner = order.firstWhere(clear, orElse: () => current);
  return (rect: rectOf(corner), corner: corner);
}

/// How much the loupe enlarges: twice, or less for a large brush so its
/// whole ring stays inside, but never below life size.
double touchLoupeScale({required double diameter, double? brushDiameter}) {
  if (brushDiameter == null || brushDiameter <= 0) return 2;
  return (diameter * 0.7 / brushDiameter).clamp(1.0, 2.0);
}

/// While a finger draws, shows what it covers in a round loupe in a top
/// corner of the canvas: the image, the stroke so far and the brush ring,
/// enlarged. It lies over everything else on the canvas and takes no
/// touches.
class EditorTouchLoupe extends StatefulWidget {
  const EditorTouchLoupe({super.key, required this.state});

  final EditorState state;

  static const double maxDiameter = 128;

  @override
  State<EditorTouchLoupe> createState() => _EditorTouchLoupeState();
}

class _EditorTouchLoupeState extends State<EditorTouchLoupe> {
  var _corner = TouchLoupeCorner.topLeft;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ValueListenableBuilder<Offset?>(
        valueListenable: widget.state.touchDrawPoint,
        builder: (context, globalFinger, _) {
          final box = this.context.findRenderObject() as RenderBox?;
          if (globalFinger == null || box == null || !box.hasSize) {
            // Each stroke starts from the usual corner.
            _corner = TouchLoupeCorner.topLeft;
            return const SizedBox.expand();
          }
          return _buildLoupe(box.size, box.globalToLocal(globalFinger));
        },
      ),
    );
  }

  Widget _buildLoupe(Size size, Offset finger) {
    final diameter = math.min(
      EditorTouchLoupe.maxDiameter,
      size.shortestSide * 0.36,
    );
    if (diameter < 64) return const SizedBox.expand();
    final placed = placeTouchLoupe(
      size: size,
      finger: finger,
      current: _corner,
      diameter: diameter,
    );
    _corner = placed.corner;
    final state = widget.state;
    final tool = state.currentTool;
    final paints = tool?.isPaintTool ?? false;
    final scale = touchLoupeScale(
      diameter: diameter,
      brushDiameter: paints
          ? tool!.getCursorRadius(state) * 2 * state.canvasController.scale
          : null,
    );
    return Stack(
      children: [
        Positioned.fromRect(
          rect: placed.rect,
          child: RawMagnifier(
            key: const ValueKey('editor-touch-loupe'),
            size: Size.square(diameter),
            focalPointOffset: finger - placed.rect.center,
            magnificationScale: scale,
            clipBehavior: Clip.hardEdge,
            decoration: const MagnifierDecoration(
              shape: CircleBorder(
                side: BorderSide(color: Colors.white, width: 2),
              ),
              shadows: [
                BoxShadow(
                  color: Color(0x59000000),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            // Paint tools bring their own ring and centre dot; outlines
            // get a crosshair to aim with.
            child: paints
                ? null
                : const CustomPaint(painter: _LoupeCrosshairPainter()),
          ),
        ),
      ],
    );
  }
}

class _LoupeCrosshairPainter extends CustomPainter {
  const _LoupeCrosshairPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    const arm = 7.0;
    for (final (color, width) in [(Colors.white, 3.0), (Colors.black, 1.0)]) {
      final paint = Paint()
        ..color = color
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round;
      canvas
        ..drawLine(
          center - const Offset(arm, 0),
          center + const Offset(arm, 0),
          paint,
        )
        ..drawLine(
          center - const Offset(0, arm),
          center + const Offset(0, arm),
          paint,
        );
    }
  }

  @override
  bool shouldRepaint(_LoupeCrosshairPainter oldDelegate) => false;
}
