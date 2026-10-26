import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/widgets/common/editable_double_field.dart';
import 'package:nai_launcher/presentation/widgets/common/one_line_field_width.dart';
import 'package:nai_launcher/presentation/widgets/common/stepped_slider.dart';
import 'package:nai_launcher/presentation/widgets/common/themed_form_input.dart';

Widget _app(Widget child, {double scale = 1, double width = 360}) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: MediaQuery(
      data: MediaQueryData(
        size: Size(width, 800),
        textScaler: TextScaler.linear(scale),
      ),
      child: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: width, child: child),
        ),
      ),
    ),
  );
}

/// How far each one-line field can be dragged sideways; zero when the
/// whole text fits.
List<double> _sideScroll(WidgetTester tester) => [
  for (final editable in tester.allRenderObjects.whereType<RenderEditable>())
    if (editable.maxLines == 1)
      (editable.offset as ScrollPosition).maxScrollExtent,
];

void main() {
  for (final scale in const [1.0, 1.3, 2.0, 3.0]) {
    testWidgets('a typed number never scrolls in its field at ${scale}x', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              EditableDoubleField(
                value: -12.34,
                min: -100,
                max: 100,
                onChanged: (_) {},
              ),
              EditableDoubleField(
                value: 0.65,
                decimals: 2,
                width: 56,
                onChanged: (_) {},
              ),
              const ContentWidthField(
                minWidth: 72,
                child: ThemedFormInput(
                  initialValue: '100',
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(isDense: true, suffixText: '%'),
                ),
              ),
            ],
          ),
          scale: scale,
        ),
      );
      await tester.pump();

      expect(_sideScroll(tester), everyElement(0));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the field keeps the width of its widest value', (tester) async {
    Future<double> widthFor(double value) async {
      await tester.pumpWidget(
        _app(
          Align(
            alignment: Alignment.topLeft,
            child: EditableDoubleField(
              value: value,
              min: 0,
              max: 1000,
              decimals: 1,
              onChanged: (_) {},
            ),
          ),
        ),
      );
      return tester.getSize(find.byType(TextField)).width;
    }

    expect(await widthFor(1), await widthFor(999.9));
  });

  testWidgets('with large text the stepped field moves under the track', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        SteppedSlider(
          value: 5.5,
          min: 0,
          max: 10,
          step: 0.1,
          decimals: 1,
          idPrefix: 'cfg',
          onChanged: (_) {},
        ),
        scale: 3,
        width: 320,
      ),
    );
    await tester.pump();

    final field = tester.getRect(find.byKey(const ValueKey('cfg-value')));
    final increase = tester.getRect(find.byKey(const ValueKey('cfg-increase')));
    expect(field.top, greaterThanOrEqualTo(increase.bottom));
    expect(field.right, lessThanOrEqualTo(320));
    expect(_sideScroll(tester), everyElement(0));
    expect(tester.takeException(), isNull);

    // At normal size it stays at the end of the track.
    await tester.pumpWidget(
      _app(
        SteppedSlider(
          value: 5.5,
          min: 0,
          max: 10,
          step: 0.1,
          decimals: 1,
          idPrefix: 'cfg',
          onChanged: (_) {},
        ),
      ),
    );
    await tester.pump();
    final inline = tester.getRect(find.byKey(const ValueKey('cfg-value')));
    final plus = tester.getRect(find.byKey(const ValueKey('cfg-increase')));
    expect(inline.left, greaterThanOrEqualTo(plus.right));
    expect(_sideScroll(tester), everyElement(0));
  });
}
