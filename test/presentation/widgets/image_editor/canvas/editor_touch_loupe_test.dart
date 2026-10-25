import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/presentation/widgets/image_editor/canvas/editor_canvas.dart';
import 'package:nai_launcher/presentation/widgets/image_editor/canvas/editor_touch_loupe.dart';
import 'package:nai_launcher/presentation/widgets/image_editor/core/editor_state.dart';

Widget _wrapCanvas(EditorState state) {
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 400,
          height: 400,
          child: Stack(
            children: [
              Positioned.fill(child: EditorCanvas(state: state)),
              Positioned.fill(child: EditorTouchLoupe(state: state)),
            ],
          ),
        ),
      ),
    ),
  );
}

final _loupe = find.byKey(const ValueKey('editor-touch-loupe'));

void main() {
  group('placeTouchLoupe', () {
    const size = Size(400, 600);

    test('starts top left and moves away from a finger near it', () {
      final far = placeTouchLoupe(
        size: size,
        finger: const Offset(200, 400),
        current: TouchLoupeCorner.topLeft,
        diameter: 120,
      );
      expect(far.corner, TouchLoupeCorner.topLeft);
      expect(far.rect, const Rect.fromLTWH(12, 12, 120, 120));

      final near = placeTouchLoupe(
        size: size,
        finger: const Offset(60, 150),
        current: TouchLoupeCorner.topLeft,
        diameter: 120,
      );
      expect(near.corner, TouchLoupeCorner.topRight);
      expect(near.rect, const Rect.fromLTWH(268, 12, 120, 120));
    });

    test('stays in the other corner until the finger comes near it', () {
      final back = placeTouchLoupe(
        size: size,
        finger: const Offset(60, 150),
        current: TouchLoupeCorner.topRight,
        diameter: 120,
      );
      expect(back.corner, TouchLoupeCorner.topRight);

      final near = placeTouchLoupe(
        size: size,
        finger: const Offset(330, 60),
        current: TouchLoupeCorner.topRight,
        diameter: 120,
      );
      expect(near.corner, TouchLoupeCorner.topLeft);
    });

    test('goes to the bottom when the finger is near both top corners', () {
      final placed = placeTouchLoupe(
        size: const Size(260, 600),
        finger: const Offset(130, 80),
        current: TouchLoupeCorner.topLeft,
        diameter: 110,
      );
      expect(placed.corner, TouchLoupeCorner.bottomLeft);
      expect(placed.rect.bottom, 600 - 12);
    });
  });

  test('a large brush is shown smaller, never below life size', () {
    expect(touchLoupeScale(diameter: 120), 2);
    expect(touchLoupeScale(diameter: 120, brushDiameter: 10), 2);
    expect(touchLoupeScale(diameter: 120, brushDiameter: 60), 1.4);
    expect(touchLoupeScale(diameter: 120, brushDiameter: 400), 1);
  });

  testWidgets('a drawing finger gets the loupe away from it until it lifts', (
    tester,
  ) async {
    final state = EditorState()..setCanvasSize(const Size(200, 200));
    addTearDown(state.dispose);
    state.setToolById('brush');
    await tester.pumpWidget(_wrapCanvas(state));
    await tester.pumpAndSettle();
    expect(_loupe, findsNothing);

    final finger = await tester.startGesture(
      const Offset(60, 60),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump();
    expect(state.touchDrawPoint.value, const Offset(60, 60));
    expect(_loupe, findsOneWidget);
    // The finger is at the top left, so the loupe takes the top right.
    final rect = tester.getRect(_loupe);
    expect(rect.right, 400 - 12);
    expect(rect.top, 12);
    expect(
      tester.widget<RawMagnifier>(_loupe).focalPointOffset,
      const Offset(60, 60) - rect.center,
    );

    await finger.moveTo(const Offset(300, 320));
    await tester.pump();
    expect(tester.getRect(_loupe), rect);
    expect(
      tester.widget<RawMagnifier>(_loupe).focalPointOffset,
      const Offset(300, 320) - rect.center,
    );

    await finger.up();
    await tester.pump();
    expect(state.touchDrawPoint.value, isNull);
    expect(_loupe, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a second finger, a mouse or a fill leave it hidden', (
    tester,
  ) async {
    final state = EditorState()..setCanvasSize(const Size(200, 200));
    addTearDown(state.dispose);
    state.setToolById('brush');
    await tester.pumpWidget(_wrapCanvas(state));
    await tester.pumpAndSettle();

    final first = await tester.startGesture(
      const Offset(200, 200),
      kind: PointerDeviceKind.touch,
      pointer: 1,
    );
    await tester.pump();
    expect(_loupe, findsOneWidget);
    final second = await tester.startGesture(
      const Offset(260, 260),
      kind: PointerDeviceKind.touch,
      pointer: 2,
    );
    await tester.pump();
    expect(_loupe, findsNothing);
    await second.up();
    await first.up();
    await tester.pump();

    final mouse = await tester.startGesture(
      const Offset(200, 200),
      kind: PointerDeviceKind.mouse,
    );
    await mouse.moveTo(const Offset(220, 220));
    await tester.pump();
    expect(_loupe, findsNothing);
    await mouse.up();
    await mouse.removePointer();

    state.setToolById('fill');
    await tester.pump();
    final tap = await tester.startGesture(
      const Offset(200, 200),
      kind: PointerDeviceKind.touch,
      pointer: 3,
    );
    await tester.pump();
    expect(_loupe, findsNothing);
    await tap.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
