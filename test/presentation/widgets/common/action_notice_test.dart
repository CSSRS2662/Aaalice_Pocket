import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/widgets/common/action_notice.dart';
import 'package:nai_launcher/presentation/widgets/common/duplicate_save_notice.dart';

const _notice = ValueKey('action_notice');
const _bar = ValueKey('bottom_bar');
const _action = ValueKey('duplicate_save_anyway');

Future<BuildContext> _pumpPage(
  WidgetTester tester, {
  double width = 400,
  double textScale = 1,
  bool bottomBar = true,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 800);
  addTearDown(tester.view.reset);
  late BuildContext pageContext;
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) {
            pageContext = context;
            return const SizedBox.expand();
          },
        ),
        bottomNavigationBar: bottomBar
            ? const SizedBox(key: _bar, height: 80)
            : null,
      ),
    ),
  );
  return pageContext;
}

void main() {
  testWidgets('the notice floats above the page bottom bar', (tester) async {
    final context = await _pumpPage(tester);

    showDuplicateSaveNotice(context, onSaveAnyway: () {});
    await tester.pumpAndSettle();

    expect(
      find.text(
        "This image is already in your photo gallery, so it wasn't saved",
      ),
      findsOneWidget,
    );
    expect(find.text('Save anyway'), findsOneWidget);
    final notice = tester.getRect(find.byKey(_notice));
    final bar = tester.getRect(find.byKey(_bar));
    expect(notice.bottom, closeTo(bar.top - 12, 0.5));
    ActionNotice.dismiss();
  });

  testWidgets('without a bottom bar it keeps the same gap to the edge', (
    tester,
  ) async {
    final context = await _pumpPage(tester, bottomBar: false);

    showDuplicateSaveNotice(context, onSaveAnyway: () {});
    await tester.pumpAndSettle();

    expect(tester.getRect(find.byKey(_notice)).bottom, closeTo(788, 0.5));
    ActionNotice.dismiss();
  });

  testWidgets('it closes on its own after a few seconds', (tester) async {
    final context = await _pumpPage(tester);

    showDuplicateSaveNotice(context, onSaveAnyway: () {});
    await tester.pumpAndSettle();
    await tester.pump(ActionNotice.duration);

    expect(find.byKey(_notice), findsNothing);
  });

  testWidgets('saving anyway runs once and closes the notice', (tester) async {
    final context = await _pumpPage(tester);
    var saves = 0;

    showDuplicateSaveNotice(context, count: 3, onSaveAnyway: () => saves++);
    await tester.pumpAndSettle();
    expect(
      find.text("3 images are already in your photo gallery and weren't saved"),
      findsOneWidget,
    );
    final action = tester.getSize(find.byKey(_action));
    expect(action.height, greaterThanOrEqualTo(kMinInteractiveDimension));
    await tester.tap(find.byKey(_action));
    await tester.pumpAndSettle();

    expect(saves, 1);
    expect(find.byKey(_notice), findsNothing);
  });

  testWidgets('a new notice replaces the current one', (tester) async {
    final context = await _pumpPage(tester);

    showDuplicateSaveNotice(context, onSaveAnyway: () {});
    showDuplicateSaveNotice(context, count: 2, onSaveAnyway: () {});
    await tester.pumpAndSettle();

    expect(find.byKey(_notice), findsOneWidget);
    expect(
      find.text("2 images are already in your photo gallery and weren't saved"),
      findsOneWidget,
    );
    ActionNotice.dismiss();
  });

  testWidgets('it fits narrow screens and large text', (tester) async {
    for (final width in const [320.0, 600.0, 840.0, 1180.0, 1600.0]) {
      for (final textScale in const [1.0, 3.0]) {
        final context = await _pumpPage(
          tester,
          width: width,
          textScale: textScale,
        );
        showDuplicateSaveNotice(context, count: 12, onSaveAnyway: () {});
        await tester.pumpAndSettle();

        final notice = tester.getRect(find.byKey(_notice));
        expect(notice.left, greaterThanOrEqualTo(0), reason: '$width');
        expect(notice.right, lessThanOrEqualTo(width), reason: '$width');
        expect(
          find.byKey(_action).hitTestable(),
          findsOneWidget,
          reason: '$width x$textScale',
        );
        expect(tester.takeException(), isNull, reason: '$width x$textScale');
        ActionNotice.dismiss();
      }
    }
  });
}
