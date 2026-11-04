import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

class GenerationDotField extends StatefulWidget {
  const GenerationDotField({super.key});

  static const double spacing = 16;
  static const double maxDotRadius = 3;
  static const double edgeInset = 12;

  @override
  State<GenerationDotField> createState() => _GenerationDotFieldState();
}

class _GenerationDotFieldState extends State<GenerationDotField>
    with SingleTickerProviderStateMixin {
  late final _motion = DotFieldMotion(math.Random());
  late final _clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 60),
  );
  bool _reducedMotion = true;
  double _elapsed = 0;

  double get _seconds =>
      _elapsed +
      (_clock.isAnimating
          ? (_clock.lastElapsedDuration?.inMicroseconds ?? 0) / 1000000
          : 0);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (reduced == _reducedMotion) return;
    _reducedMotion = reduced;
    if (reduced) {
      _elapsed = _seconds;
      _clock.stop();
    } else {
      _clock.repeat();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: AppLocalizations.of(context)?.generation_generating,
    child: RepaintBoundary(
      key: const ValueKey('generation-dot-field'),
      child: CustomPaint(
        painter: _DotFieldPainter(
          clock: _clock,
          seconds: () => _seconds,
          motion: _motion,
          color: Theme.of(context).colorScheme.primary,
          reducedMotion: _reducedMotion,
        ),
        child: const SizedBox.expand(),
      ),
    ),
  );
}

/// Closed cubic paths keep both moving foci inside the normalized canvas.
class DotFieldMotion {
  DotFieldMotion(math.Random random)
    : _paths = List.generate(2, (_) => _FocusPath(random));

  final List<_FocusPath> _paths;

  Offset focusAt(int index, double seconds) =>
      _paths[index].at(seconds / (index == 0 ? 8 : 10));
}

class _FocusPath {
  _FocusPath(math.Random random) {
    for (var i = 0; i < 6; i++) {
      final point = Offset(random.nextDouble(), random.nextDouble());
      final reach =
          [point.dx, 1 - point.dx, point.dy, 1 - point.dy].reduce(math.min) *
          0.8;
      final angle = random.nextDouble() * math.pi * 2;
      _points.add(point);
      _tangents.add(Offset(math.cos(angle), math.sin(angle)) * reach);
    }
  }

  final List<Offset> _points = [];
  final List<Offset> _tangents = [];

  Offset at(double phase) {
    final position = (phase % 1) * _points.length;
    final index = position.floor();
    final next = (index + 1) % _points.length;
    final t = position - index;
    final u = 1 - t;
    return _points[index] * (u * u * u) +
        (_points[index] + _tangents[index]) * (3 * u * u * t) +
        (_points[next] - _tangents[next]) * (3 * u * t * t) +
        _points[next] * (t * t * t);
  }
}

class _DotFieldPainter extends CustomPainter {
  _DotFieldPainter({
    required Animation<double> clock,
    required this.seconds,
    required this.motion,
    required this.color,
    required this.reducedMotion,
  }) : super(repaint: clock);

  final double Function() seconds;
  final DotFieldMotion motion;
  final Color color;
  final bool reducedMotion;

  @override
  void paint(Canvas canvas, Size size) {
    const spacing = GenerationDotField.spacing;
    const inset = GenerationDotField.edgeInset;
    if (size.shortestSide < inset * 2) return;

    final time = seconds();
    final foci = List.generate(2, (index) {
      final point = motion.focusAt(index, time);
      return Offset(point.dx * size.width, point.dy * size.height);
    });
    final strength = reducedMotion
        ? 1.0
        : Curves.easeOut.transform((time / 0.25).clamp(0.0, 1.0));
    final spread = math.max(1.0, size.shortestSide * 0.25);
    final columns = ((size.width - inset * 2) / spacing).floor() + 1;
    final rows = ((size.height - inset * 2) / spacing).floor() + 1;
    final startX = (size.width - (columns - 1) * spacing) / 2;
    final startY = (size.height - (rows - 1) * spacing) / 2;
    final paint = Paint();
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < columns; x++) {
        final point = Offset(startX + x * spacing, startY + y * spacing);
        final distance = math.min(
          (point - foci[0]).distanceSquared,
          (point - foci[1]).distanceSquared,
        );
        final influence =
            math.exp(-distance / (2 * spread * spread)) * strength;
        paint.color = color.withValues(alpha: 0.16 + influence * 0.44);
        const minRadius = 1.05;
        canvas.drawCircle(
          point,
          minRadius + influence * (GenerationDotField.maxDotRadius - minRadius),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_DotFieldPainter oldDelegate) =>
      color != oldDelegate.color ||
      reducedMotion != oldDelegate.reducedMotion ||
      motion != oldDelegate.motion;
}
