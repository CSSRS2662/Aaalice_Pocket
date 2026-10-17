import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/widgets/common/themed_input_dialog.dart';

void main() {
  testWidgets('input, validation error and IME stay in the safe viewport', (
    tester,
  ) async {
    final view = tester.view;
    view.devicePixelRatio = 3;
    view.physicalSize = const Size(960, 1704);
    addTearDown(() {
      view.resetPhysicalSize();
      view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 568),
            padding: EdgeInsets.fromLTRB(12, 24, 12, 16),
            viewInsets: EdgeInsets.only(bottom: 240),
            textScaler: TextScaler.linear(3),
          ),
          child: Scaffold(
            body: ThemedInputDialog(
              title: 'A long localized title that wraps',
              labelText: 'A long field label',
              hintText: 'A long field hint',
              multiline: true,
              validator: (value) => value == 'bad'
                  ? 'A long validation error that must remain readable and scrollable'
                  : null,
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'bad');
    await tester.pump();

    expect(find.textContaining('long validation error'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(find.byType(TextField).evaluate().single.widget, isA<TextField>());

    view.physicalSize = const Size(4800, 2700);
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(1600, 900),
            textScaler: TextScaler.linear(3),
          ),
          child: Scaffold(
            body: ThemedInputDialog(title: 'Large text input', multiline: true),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty value submits only where empty clears a setting', (
    tester,
  ) async {
    for (final allowEmpty in const [false, true]) {
      String? result = 'unset';
      await tester.pumpWidget(
        MaterialApp(
          // A fresh navigator each round, so the last dialog is gone.
          key: ValueKey(allowEmpty),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await ThemedInputDialog.show(
                  context: context,
                  title: 'Instructions',
                  initialValue: 'old text',
                  multiline: true,
                  allowEmpty: allowEmpty,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();

      final confirm = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(confirm.onPressed != null, allowEmpty);
      if (allowEmpty) {
        await tester.tap(find.byType(FilledButton));
        await tester.pumpAndSettle();
        expect(result, isEmpty);
      }
    }
  });
}
