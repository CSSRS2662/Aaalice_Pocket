import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/screens/generation/widgets/prompt_group_controller.dart';
import 'package:nai_launcher/presentation/screens/generation/widgets/prompt_group_grid.dart';

class _Calls {
  final opened = <String>[];
  final menus = <String>[];
  final toggled = <String>[];
  final deleted = <String>[];
  var reordered = 0;
}

Future<(PromptGroupCollection, _Calls)> _pumpGrid(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(400, 800);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final groups = PromptGroupCollection.fromJson([
    {'id': 's0', 'text': 'snow, winter'},
    {'id': 's1', 'text': 'smile, blush'},
    {'id': 's2', 'text': 'upper_body'},
    {'id': 's3', 'text': 'scenery'},
  ], fallbackText: '');
  addTearDown(groups.dispose);
  final calls = _Calls();
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: PromptGroupGrid(
            groups: groups,
            onOpen: calls.opened.add,
            onShowActions: calls.menus.add,
            onToggleEnabled: calls.toggled.add,
            onDelete: calls.deleted.add,
            onReordered: () => calls.reordered++,
          ),
        ),
      ),
    ),
  );
  return (groups, calls);
}

Finder _tile(String id) => find.byKey(ValueKey('prompt_group_tile_$id'));
Finder _cross(String id) => find.byKey(ValueKey('prompt_group_delete_$id'));

String _crossTooltip(WidgetTester tester, String id) => tester
    .widget<Tooltip>(
      find.descendant(of: _cross(id), matching: find.byType(Tooltip)),
    )
    .message!;

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(PromptGroupGrid)))!;

void main() {
  testWidgets('two columns of equal tiles followed by the add tile', (
    tester,
  ) async {
    await _pumpGrid(tester);
    final first = tester.getRect(_tile('s0'));
    final second = tester.getRect(_tile('s1'));
    final third = tester.getRect(_tile('s2'));
    expect(second.top, first.top);
    expect(second.left, greaterThan(first.right));
    expect(third.left, first.left);
    expect(third.top, greaterThan(first.bottom));
    expect(second.size, first.size);
    final add = tester.getRect(
      find.byKey(const ValueKey('prompt_group_add_tile')),
    );
    expect(add.top, greaterThan(third.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('tap opens a section and the dot toggles it', (tester) async {
    final (_, calls) = await _pumpGrid(tester);
    await tester.tap(_tile('s1'));
    await tester.pump();
    expect(calls.opened, ['s1']);

    await tester.tap(find.byKey(const ValueKey('prompt_group_enabled_s2')));
    await tester.pump();
    expect(calls.toggled, ['s2']);
    expect(calls.opened, ['s1']);
  });

  testWidgets('the cross deletes on the second tap only', (tester) async {
    final (_, calls) = await _pumpGrid(tester);
    expect(_crossTooltip(tester, 's0'), _l10n(tester).prompt_deleteGroup);

    await tester.tap(_cross('s0'));
    await tester.pump();
    expect(_crossTooltip(tester, 's0'), _l10n(tester).prompt_groupDeleteAgain);
    expect(calls.deleted, isEmpty);
    expect(calls.opened, isEmpty);

    await tester.tap(_cross('s0'));
    await tester.pump();
    expect(calls.deleted, ['s0']);
  });

  testWidgets('an armed cross resets after a tap elsewhere or a pause', (
    tester,
  ) async {
    final (_, calls) = await _pumpGrid(tester);
    await tester.tap(_cross('s1'));
    await tester.pump();
    await tester.tapAt(const Offset(200, 780));
    await tester.pump();
    expect(_crossTooltip(tester, 's1'), _l10n(tester).prompt_deleteGroup);

    await tester.tap(_cross('s1'));
    await tester.pump(const Duration(seconds: 4));
    expect(_crossTooltip(tester, 's1'), _l10n(tester).prompt_deleteGroup);
    await tester.tap(_cross('s1'));
    await tester.pump();
    expect(calls.deleted, isEmpty);
  });

  testWidgets('a long press released in place opens the section menu', (
    tester,
  ) async {
    final (groups, calls) = await _pumpGrid(tester);
    await tester.longPress(_tile('s2'));
    await tester.pumpAndSettle();
    expect(calls.menus, ['s2']);
    expect(calls.reordered, 0);
    expect(groups.sections.map((s) => s.id), ['s0', 's1', 's2', 's3']);
  });

  testWidgets('long press and drag moves a section with live reflow', (
    tester,
  ) async {
    final (groups, calls) = await _pumpGrid(tester);
    final firstSlot = tester.getRect(_tile('s0')).topLeft;
    final target = tester.getCenter(_tile('s2'));
    final gesture = await tester.startGesture(tester.getCenter(_tile('s0')));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveTo(target);
    await tester.pump();
    // Other tiles have already made room before the drop.
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.getRect(_tile('s1')).topLeft, firstSlot);
    await gesture.up();
    await tester.pumpAndSettle();

    expect(groups.sections.map((s) => s.id), ['s1', 's2', 's0', 's3']);
    expect(calls.reordered, 1);
    expect(calls.menus, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the add tile creates a section and opens it', (tester) async {
    final (groups, calls) = await _pumpGrid(tester);
    await tester.tap(find.byKey(const ValueKey('prompt_group_add_tile')));
    await tester.pump();
    await tester.pump();
    expect(groups.sections, hasLength(5));
    expect(calls.opened, [groups.sections.last.id]);
  });
}
