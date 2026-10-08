import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/constants/storage_keys.dart';
import 'package:nai_launcher/core/storage/local_storage_service.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/screens/generation/widgets/prompt_group_controller.dart';
import 'package:nai_launcher/presentation/screens/generation/widgets/prompt_group_edit_sheet.dart';

import '../../../../helpers/memory_local_storage.dart';

class _Calls {
  final toggled = <String>[];
  final deleted = <String>[];
}

Future<(PromptGroupCollection, _Calls)> _openSheet(
  WidgetTester tester, {
  Size size = const Size(360, 800),
  double textScale = 1,
  String sectionId = 's1',
  bool autocomplete = true,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final groups = PromptGroupCollection.fromJson([
    {'id': 's0', 'text': 'snow, winter'},
    {'id': 's1', 'text': 'uniform, checkered_skirt, white_coat, open_coat'},
    {'id': 's2', 'text': 'smile', 'enabled': false},
  ], fallbackText: '');
  addTearDown(groups.dispose);
  final calls = _Calls();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageServiceProvider.overrideWith(
          (ref) =>
              MemoryLocalStorage()
                ..values[StorageKeys.enableAutocomplete] = autocomplete,
        ),
      ],
      child: MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showPromptGroupEditSheet(
                  context,
                  groups: groups,
                  sectionId: sectionId,
                  negative: false,
                  numericEmphasisEnabled: true,
                  callbacks: PromptGroupEditCallbacks(
                    onChanged: () {},
                    onToggleEnabled: (id) {
                      calls.toggled.add(id);
                      final section = groups.sectionById(id)!;
                      groups.setEnabled(id, !section.enabled);
                    },
                    onDuplicate: (_) {},
                    onMoveToFront: (_) {},
                    onDelete: calls.deleted.add,
                    onOpenAssistantSettings: () {},
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return (groups, calls);
}

bool _clipped(WidgetTester tester, Finder text) =>
    tester.renderObject<RenderParagraph>(text).didExceedMaxLines;

void main() {
  testWidgets('title and include label show in full on a phone', (
    tester,
  ) async {
    await _openSheet(tester);
    final title = find.byKey(const ValueKey('prompt_group_edit_title'));
    expect(_clipped(tester, title), isFalse);
    expect(_clipped(tester, find.text('参与生成')), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the prompt field fills the space above the toolbar', (
    tester,
  ) async {
    await _openSheet(tester);
    final field = tester.getRect(find.byType(TextField));
    final toolbar = tester.getRect(
      find.byKey(const ValueKey('prompt_group_edit_enabled')),
    );
    expect(field.height, greaterThan(450));
    expect(toolbar.top - field.bottom, lessThan(40));
    expect(toolbar.bottom, greaterThan(740));
  });

  testWidgets('opening a section puts the caret at the end, ready to type', (
    tester,
  ) async {
    final (groups, _) = await _openSheet(tester);
    final section = groups.sectionById('s1')!;
    expect(section.focusNode.hasFocus, isTrue);
    expect(
      section.controller.selection,
      TextSelection.collapsed(offset: section.controller.text.length),
    );

    // Moving on while typing keeps the keyboard on the next section.
    await tester.tap(find.byKey(const ValueKey('prompt_group_edit_next')));
    await tester.pumpAndSettle();
    final next = groups.sectionById('s2')!;
    expect(next.focusNode.hasFocus, isTrue);
    expect(next.controller.selection.baseOffset, next.controller.text.length);
  });

  testWidgets('narrow screens with large text still fit without overflow', (
    tester,
  ) async {
    await _openSheet(tester, size: const Size(320, 640), textScale: 2);
    expect(
      find.byKey(const ValueKey('prompt_group_edit_done')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('arrows and swipes move between sections; toggle and done', (
    tester,
  ) async {
    final (_, calls) = await _openSheet(tester);
    final title = find.byKey(const ValueKey('prompt_group_edit_title'));
    String titleText() => tester.widget<Text>(title).textSpan!.toPlainText();
    expect(titleText(), '分区 2 / 3');

    await tester.tap(find.byKey(const ValueKey('prompt_group_edit_next')));
    await tester.pumpAndSettle();
    expect(titleText(), '分区 3 / 3');
    expect(find.text('已停用'), findsOneWidget);

    await tester.fling(title, const Offset(200, 0), 1000);
    await tester.pumpAndSettle();
    expect(titleText(), '分区 2 / 3');

    await tester.tap(find.byKey(const ValueKey('prompt_group_edit_enabled')));
    await tester.pump();
    expect(calls.toggled, ['s1']);

    await tester.tap(find.byKey(const ValueKey('prompt_group_edit_done')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('prompt_group_edit_title')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('deleting from the menu closes first, then deletes', (
    tester,
  ) async {
    final (_, calls) = await _openSheet(tester);
    await tester.tap(find.byKey(const ValueKey('prompt_group_edit_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除分区'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('prompt_group_edit_title')), findsNothing);
    expect(calls.deleted, ['s1']);
  });

  testWidgets('the comma key separates tags without doubling commas', (
    tester,
  ) async {
    final (groups, _) = await _openSheet(tester, autocomplete: false);
    final controller = groups.sectionById('s1')!.controller;
    final comma = find.byKey(const ValueKey('prompt_group_edit_comma'));
    final original = controller.text;

    await tester.tap(comma);
    await tester.pump();
    expect(controller.text, '$original, ');
    expect(controller.selection.baseOffset, controller.text.length);

    // Right after a comma it only settles the caret.
    await tester.tap(comma);
    await tester.pump();
    expect(controller.text, '$original, ');

    // Just before a comma it steps over it.
    controller.selection = const TextSelection.collapsed(offset: 7);
    await tester.tap(comma);
    await tester.pump();
    expect(controller.text, '$original, ');
    expect(controller.selection.baseOffset, 'uniform, '.length);
    expect(groups.sectionById('s1')!.focusNode.hasFocus, isTrue);
  });

  testWidgets('header tools go to the bottom row as the header gets tight', (
    tester,
  ) async {
    Finder inHeader(Finder finder) => find.descendant(
      of: find.byKey(const ValueKey('prompt_group_edit_header_tools')),
      matching: finder,
    );
    final toggle = find.byKey(const ValueKey('tag-mode-button'));
    final menu = find.byKey(const ValueKey('prompt_group_edit_menu'));

    await _openSheet(tester, size: const Size(600, 800), autocomplete: false);
    expect(inHeader(toggle), findsOneWidget);
    expect(inHeader(menu), findsOneWidget);
    final comma = tester.getRect(
      find.byKey(const ValueKey('prompt_group_edit_comma')),
    );
    // The comma key ends the bottom row, right above the keyboard.
    expect(comma.right, closeTo(600 - 12, 1));

    await tester.pumpWidget(const SizedBox());
    await _openSheet(
      tester,
      size: const Size(320, 640),
      textScale: 2,
      autocomplete: false,
    );
    expect(
      find.byKey(const ValueKey('prompt_group_edit_header_tools')),
      findsNothing,
    );
    expect(toggle, findsOneWidget);
    expect(menu, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
