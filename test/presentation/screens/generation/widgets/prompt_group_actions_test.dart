import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/screens/generation/widgets/prompt_group_actions.dart';
import 'package:nai_launcher/presentation/screens/generation/widgets/prompt_group_controller.dart';

Future<List<PromptGroupAction?>> _openMenu(
  WidgetTester tester,
  String sectionId,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(360, 800);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final groups = PromptGroupCollection.fromJson([
    {'id': 's0', 'text': 'snow, winter'},
    {'id': 's1', 'text': '  '},
  ], fallbackText: '');
  addTearDown(groups.dispose);
  final results = <PromptGroupAction?>[];
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async => results.add(
                await showPromptGroupActions(
                  context,
                  groups: groups,
                  sectionId: sectionId,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return results;
}

ListTile _saveItem(WidgetTester tester) => tester.widget<ListTile>(
  find.byKey(const ValueKey('prompt_group_action_saveToLibrary')),
);

void main() {
  testWidgets('a section can be saved to the library from its menu', (
    tester,
  ) async {
    final results = await _openMenu(tester, 's0');
    expect(find.text('保存到词库'), findsOneWidget);
    expect(_saveItem(tester).enabled, isTrue);

    await tester.tap(find.text('保存到词库'));
    await tester.pumpAndSettle();
    expect(results, [PromptGroupAction.saveToLibrary]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty section offers nothing to save', (tester) async {
    await _openMenu(tester, 's1');
    expect(_saveItem(tester).enabled, isFalse);
  });
}
