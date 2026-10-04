import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/presentation/adaptive/keyboard_settled_padding.dart';

class _Harness extends StatefulWidget {
  const _Harness({required this.childInsets});

  final List<double> childInsets;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  double inset = 0;

  // The same instance on every build, as a sheet's content is.
  late final Widget _content = Builder(
    builder: (context) {
      widget.childInsets.add(MediaQuery.viewInsetsOf(context).bottom);
      return const SizedBox.expand();
    },
  );

  void setInset(double value) => setState(() => inset = value);

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQueryData(viewInsets: EdgeInsets.only(bottom: inset)),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: KeyboardSettledPadding(child: _content),
      ),
    );
  }
}

void main() {
  late List<double> childInsets;

  setUp(KeyboardSettledPadding.resetKnownKeyboardHeight);

  Future<_HarnessState> pump(WidgetTester tester) async {
    childInsets = [];
    await tester.pumpWidget(_Harness(childInsets: childInsets));
    return tester.state<_HarnessState>(find.byType(_Harness));
  }

  double padding(WidgetTester tester) =>
      (tester
                  .widget<Padding>(
                    find.descendant(
                      of: find.byType(KeyboardSettledPadding),
                      matching: find.byType(Padding),
                    ),
                  )
                  .padding
              as EdgeInsets)
          .bottom;

  testWidgets('waits for the keyboard to finish opening, then jumps', (
    tester,
  ) async {
    final harness = await pump(tester);
    for (final inset in [60.0, 150.0, 240.0, 300.0]) {
      harness.setInset(inset);
      await tester.pump(const Duration(milliseconds: 16));
      expect(padding(tester), 0);
    }
    await tester.pump(const Duration(milliseconds: 100));
    expect(padding(tester), 300);
  });

  testWidgets('drops at once when the keyboard starts closing', (tester) async {
    final harness = await pump(tester);
    harness.setInset(300);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(padding(tester), 300);

    harness.setInset(260);
    await tester.pump();
    expect(padding(tester), 0);
    harness.setInset(0);
    await tester.pump(const Duration(milliseconds: 200));
    expect(padding(tester), 0);
  });

  testWidgets('the content never sees the moving inset', (tester) async {
    final harness = await pump(tester);
    final builds = childInsets.length;
    for (final inset in [60.0, 150.0, 240.0, 300.0]) {
      harness.setInset(inset);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 100));
    expect(childInsets.every((inset) => inset == 0), isTrue);
    // Rebuilt for the one jump, not for every keyboard frame.
    expect(childInsets.length - builds, lessThanOrEqualTo(1));
  });
}
