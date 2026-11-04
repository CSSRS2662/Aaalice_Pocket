import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/presentation/widgets/common/generation_dot_field.dart';
import 'package:nai_launcher/presentation/widgets/common/generation_visual_transition.dart';

void main() {
  test(
    'two independent random curves stay inside the entire canvas and close smoothly',
    () {
      final motion = DotFieldMotion(math.Random(42));
      expect(motion.focusAt(0, 0), isNot(motion.focusAt(1, 0)));
      for (var index = 0; index < 2; index++) {
        final period = index == 0 ? 8.0 : 10.0;
        expect(
          (motion.focusAt(index, 0) - motion.focusAt(index, period)).distance,
          lessThan(0.00001),
        );
        expect(
          (motion.focusAt(index, 1) - motion.focusAt(index, 0)).distance,
          greaterThan(0.05),
        );
        for (var frame = 0; frame < 2000; frame++) {
          final point = motion.focusAt(index, frame / 10);
          expect(point.dx, inInclusiveRange(0.0, 1.0));
          expect(point.dy, inInclusiveRange(0.0, 1.0));
        }
        final before = motion.focusAt(index, period - 0.001);
        final start = motion.focusAt(index, 0);
        final after = motion.focusAt(index, 0.001);
        expect(
          ((start - before) - (after - start)).distance,
          lessThan(0.00001),
        );
      }
    },
  );

  testWidgets('dots keep their full radius inside portrait and wide frames', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: GenerationDotField()));
    final painter = tester
        .widget<CustomPaint>(
          find.descendant(
            of: find.byType(GenerationDotField),
            matching: find.byType(CustomPaint),
          ),
        )
        .painter!;
    await tester.pump(const Duration(milliseconds: 300));

    for (final size in const [Size(288, 421), Size(322, 322), Size(317, 73)]) {
      final canvas = TestRecordingCanvas();
      painter.paint(canvas, size);
      final circles = canvas.invocations
          .map((entry) => entry.invocation)
          .where((call) => call.memberName == #drawCircle)
          .toList();
      expect(circles, isNotEmpty);
      for (final call in circles) {
        final center = call.positionalArguments.first as Offset;
        final radius = call.positionalArguments[1] as double;
        expect(center.dx - radius, greaterThanOrEqualTo(9));
        expect(center.dy - radius, greaterThanOrEqualTo(9));
        expect(center.dx + radius, lessThanOrEqualTo(size.width - 9));
        expect(center.dy + radius, lessThanOrEqualTo(size.height - 9));
      }
    }
  });

  testWidgets(
    'dot motion repaints without rebuilding, reduced motion stops it',
    (tester) async {
      Widget app(bool reduce) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduce),
          child: const SizedBox(
            width: 320,
            height: 480,
            child: GenerationDotField(),
          ),
        ),
      );
      await tester.pumpWidget(app(false));
      final field = find.descendant(
        of: find.byType(GenerationDotField),
        matching: find.byType(CustomPaint),
      );
      final widget = tester.widget<CustomPaint>(field);
      var repaints = 0;
      void onRepaint() => repaints++;
      widget.painter!.addListener(onRepaint);
      await tester.pump(const Duration(milliseconds: 500));
      expect(repaints, greaterThan(0));
      expect(tester.widget<CustomPaint>(field), same(widget));
      await tester.pumpWidget(app(true));
      await tester.pumpAndSettle();
      final stopped = repaints;
      await tester.pump(const Duration(seconds: 2));
      expect(repaints, stopped);
      widget.painter!.removeListener(onRepaint);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'canvas transitions preserve the outgoing visual until the fade completes',
    (tester) async {
      Widget app(String stage, {bool reduce = false}) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduce),
          child: SizedBox(
            width: 320,
            height: 480,
            child: GenerationVisualTransition(
              stage: stage,
              child: ColoredBox(
                key: ValueKey('content-$stage'),
                color: stage == 'image' ? Colors.blue : Colors.white,
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(app('image'));
      await tester.pumpWidget(app('dots'));
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.byKey(const ValueKey('content-image')), findsOneWidget);
      expect(find.byKey(const ValueKey('content-dots')), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('content-image')), findsNothing);
      await tester.pumpWidget(app('final', reduce: true));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('content-dots')), findsNothing);
      expect(find.byKey(const ValueKey('content-final')), findsOneWidget);
    },
  );
}
