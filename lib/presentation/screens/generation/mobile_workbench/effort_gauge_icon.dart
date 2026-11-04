import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/enums/generation_effort.dart';
import '../../../themes/theme_extension.dart';

class EffortGaugeIcon extends StatelessWidget {
  const EffortGaugeIcon({super.key, required this.effort});

  final GenerationEffort effort;

  static const double dimension = 20;
  static const double _rightArcStart = math.pi * 1.77;
  static const double _rightArcSweep = math.pi * 0.23;
  static const double _highAngle =
      _rightArcStart + _rightArcSweep / 2 - math.pi * 1.5;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final target = effort == GenerationEffort.medium ? 0.0 : _highAngle;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: target, end: target),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : theme.appTheme.normalDuration,
      curve: theme.appTheme.standardCurve,
      child: CustomPaint(
        size: const Size.square(dimension),
        painter: _GaugeNeedlePainter(color: colors.onSurface),
      ),
      builder: (context, angle, needle) => SizedBox.square(
        dimension: dimension,
        child: Stack(
          children: [
            CustomPaint(
              size: const Size.square(dimension),
              painter: _GaugeTrackPainter(
                accent: colors.primary,
                track: colors.onSurfaceVariant.withValues(alpha: 0.5),
                standardFraction: angle / _highAngle,
              ),
            ),
            Transform.rotate(
              key: const ValueKey('generation-effort-needle'),
              angle: angle,
              alignment: const FractionalOffset(0.5, 17 / 24),
              child: needle,
            ),
          ],
        ),
      ),
    );
  }
}

class _GaugeTrackPainter extends CustomPainter {
  const _GaugeTrackPainter({
    required this.accent,
    required this.track,
    required this.standardFraction,
  });

  final Color accent;
  final Color track;
  final double standardFraction;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final arc = Rect.fromCircle(center: const Offset(12, 17), radius: 10);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawArc(arc, math.pi, math.pi * 0.23, false, paint);
    paint.color = Color.lerp(accent, track, standardFraction)!;
    canvas.drawArc(arc, math.pi * 1.33, math.pi * 0.34, false, paint);
    paint.color = Color.lerp(track, accent, standardFraction)!;
    canvas.drawArc(
      arc,
      EffortGaugeIcon._rightArcStart,
      EffortGaugeIcon._rightArcSweep,
      false,
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GaugeTrackPainter oldDelegate) =>
      accent != oldDelegate.accent ||
      track != oldDelegate.track ||
      standardFraction != oldDelegate.standardFraction;
}

class _GaugeNeedlePainter extends CustomPainter {
  const _GaugeNeedlePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawLine(const Offset(12, 10), const Offset(12, 14.5), paint);
    canvas.drawCircle(const Offset(12, 17), 2.5, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GaugeNeedlePainter oldDelegate) =>
      color != oldDelegate.color;
}
