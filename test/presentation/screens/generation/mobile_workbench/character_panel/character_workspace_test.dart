import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/constants/storage_keys.dart';
import 'package:nai_launcher/core/storage/local_storage_service.dart';
import 'package:nai_launcher/data/models/character/character_prompt.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/adaptive/interaction_policy.dart';
import 'package:nai_launcher/presentation/providers/character_place_options_provider.dart';
import 'package:nai_launcher/presentation/providers/character_prompt_provider.dart';
import 'package:nai_launcher/presentation/providers/character_workspace_provider.dart';
import 'package:nai_launcher/presentation/providers/image_generation_provider.dart';
import 'package:nai_launcher/presentation/screens/generation/mobile_workbench/character_panel/character_placement_sheet.dart';
import 'package:nai_launcher/presentation/screens/generation/mobile_workbench/character_panel/character_workspace.dart';
import 'package:nai_launcher/presentation/screens/generation/mobile_workbench/character_panel/character_workspace_editor.dart';
import 'package:nai_launcher/presentation/screens/generation/widgets/prompt_group_tile.dart';

import '../../../../../helpers/memory_local_storage.dart';

/// In-memory character state; the real notifier writes to Hive.
class _Characters extends CharacterPromptNotifier {
  _Characters(this.initial);

  final CharacterPromptConfig initial;

  @override
  CharacterPromptConfig build() => initial;

  @override
  void addCharacter(
    CharacterGender gender, {
    String? name,
    String? prompt,
    String? negativePrompt,
    String? thumbnailPath,
  }) {
    state = state.addCharacter(
      gender: gender,
      name: name,
      prompt: prompt,
      negativePrompt: negativePrompt,
      thumbnailPath: thumbnailPath,
    );
  }

  @override
  void updateCharacter(CharacterPrompt character) {
    state = state.updateCharacter(character).normalizeCustomPositions();
  }

  @override
  void removeCharacter(String id) => state = state.removeCharacter(id);

  @override
  void replaceAll(List<CharacterPrompt> characters) {
    state = CharacterPromptConfig(
      characters: characters,
      globalAiChoice: state.globalAiChoice,
    ).normalizeCustomPositions();
  }

  @override
  void setCharacterOrder(List<String> orderedIds) {
    final byId = {for (final c in state.characters) c.id: c};
    state = state.copyWith(
      characters: [for (final id in orderedIds) byId[id]!],
    );
  }

  @override
  void setGlobalAiChoice(bool value) {
    final next = state.copyWith(globalAiChoice: value);
    state = value ? next : next.normalizeCustomPositions();
  }
}

const _girl = CharacterPrompt(id: 'a', name: 'Alice', prompt: 'girl, red hair');
const _boy = CharacterPrompt(id: 'b', name: 'Bob', prompt: 'boy, glasses');
const _maid = CharacterPrompt(id: 'c', name: 'Cora', prompt: 'girl, maid');

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  CharacterPromptConfig config = const CharacterPromptConfig(
    characters: [_girl, _boy, _maid],
  ),
  Size size = const Size(390, 844),
  double textScale = 1,
  MemoryLocalStorage? storage,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageServiceProvider.overrideWith(
          (ref) => storage ?? MemoryLocalStorage(),
        ),
        characterPromptNotifierProvider.overrideWith(() => _Characters(config)),
        characterPlaceOptionsProvider.overrideWith(
          (ref) => (snap: false, backdrop: false),
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
        home: InteractionPolicyScope(
          initialPolicy: InteractionPolicy.touchFirst,
          child: Builder(
            builder: (context) => Scaffold(
              body: Column(
                children: [
                  TextButton(
                    onPressed: () => showCharacterPlacement(context),
                    child: const Text('place'),
                  ),
                  const Expanded(child: CharacterWorkspace(negative: false)),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.text('place')));
}

CharacterPrompt _character(ProviderContainer container, String id) =>
    container.read(characterPromptNotifierProvider).findCharacterById(id)!;

Future<void> _expand(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(ValueKey('character_workspace_row_$id')));
  await tester.pumpAndSettle();
}

Future<void> _openPlacement(WidgetTester tester) async {
  await tester.tap(find.text('place'));
  await tester.pumpAndSettle();
}

Offset _at(WidgetTester tester, double column, double row) {
  final rect = tester.getRect(
    find.byKey(const ValueKey('character-place-picture')),
  );
  return rect.topLeft + Offset(rect.width * column, rect.height * row);
}

CharacterPosition _position(ProviderContainer container, String id) {
  final config = container.read(characterPromptNotifierProvider);
  return config.resolvePosition(config.findCharacterById(id)!);
}

void main() {
  testWidgets('closed rows are one line each; one opens in place', (
    tester,
  ) async {
    await _pump(tester);
    final rows = [
      for (final id in ['a', 'b', 'c'])
        tester.getRect(find.byKey(ValueKey('character_workspace_row_$id'))),
    ];
    for (final row in rows) {
      expect(row.height, lessThanOrEqualTo(52));
    }
    expect(find.byType(CharacterWorkspaceEditor), findsNothing);

    await _expand(tester, 'b');
    expect(find.byType(CharacterWorkspaceEditor), findsOneWidget);
    expect(find.byType(PromptGroupTile), findsOneWidget);
    await _expand(tester, 'a');
    expect(find.byType(CharacterWorkspaceEditor), findsOneWidget);
    expect(
      find.byKey(const ValueKey('character-workspace-name-a')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the marker includes or leaves out a character', (tester) async {
    final container = await _pump(tester);
    await tester.tap(
      find.byKey(const ValueKey('character_workspace_enabled_b')),
    );
    await tester.pumpAndSettle();
    expect(_character(container, 'b').enabled, isFalse);
  });

  testWidgets('a new character opens right away', (tester) async {
    final container = await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('character-workspace-add')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('character-workspace-add-male')),
    );
    await tester.pumpAndSettle();

    final characters = container
        .read(characterPromptNotifierProvider)
        .characters;
    expect(characters, hasLength(4));
    expect(characters.last.effectiveGender, CharacterGender.male);
    expect(
      container.read(characterWorkspaceExpandedProvider),
      characters.last.id,
    );
    expect(find.byType(CharacterWorkspaceEditor), findsOneWidget);
  });

  testWidgets('deleting a character can be undone in place', (tester) async {
    final container = await _pump(tester);
    await _expand(tester, 'b');
    await tester.tap(find.byKey(const ValueKey('character-workspace-delete')));
    await tester.pumpAndSettle();
    expect(
      [
        for (final c
            in container.read(characterPromptNotifierProvider).characters)
          c.id,
      ],
      ['a', 'c'],
    );

    await tester.tap(find.byKey(const ValueKey('prompt_group_undo_action')));
    await tester.pumpAndSettle();
    expect(
      [
        for (final c
            in container.read(characterPromptNotifierProvider).characters)
          c.id,
      ],
      ['a', 'b', 'c'],
    );
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('long press and drag reorders characters', (tester) async {
    final container = await _pump(tester);
    final first = tester.getCenter(
      find.byKey(const ValueKey('character_workspace_row_a')),
    );
    final third = tester.getCenter(
      find.byKey(const ValueKey('character_workspace_row_c')),
    );
    final gesture = await tester.startGesture(first);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    // Past the last row, in steps the list can follow.
    final target = third + const Offset(0, 60);
    for (var step = 1; step <= 6; step++) {
      await gesture.moveTo(Offset.lerp(first, target, step / 6)!);
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(
      [
        for (final c
            in container.read(characterPromptNotifierProvider).characters)
          c.id,
      ],
      ['b', 'c', 'a'],
    );
  });

  testWidgets('a section dot writes the prompt back', (tester) async {
    final container = await _pump(tester);
    await _expand(tester, 'a');
    final dot = find.byWidgetPredicate(
      (widget) =>
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith(
            'prompt_group_enabled_',
          ),
    );
    await tester.tap(dot);
    await tester.pumpAndSettle();
    expect(_character(container, 'a').prompt, '');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a gender change keeps the sections apart', (tester) async {
    final storage = MemoryLocalStorage();
    storage.values[StorageKeys.characterPromptGroupState] = jsonEncode({
      'a': {
        'positivePrompt': 'girl, red hair',
        'negativePrompt': '',
        'positiveSections': [
          {'id': 's1', 'text': 'girl'},
          {'id': 's2', 'text': 'red hair'},
        ],
        'negativeSections': [
          {'id': 'n1', 'text': ''},
        ],
      },
    });
    final container = await _pump(tester, storage: storage);
    await _expand(tester, 'a');
    expect(find.byType(PromptGroupTile), findsNWidgets(2));

    await tester.tap(
      find.byKey(const ValueKey('character-workspace-gender-male')),
    );
    await tester.pumpAndSettle();
    final alice = _character(container, 'a');
    expect(alice.prompt, 'boy, red hair');
    expect(alice.effectiveGender, CharacterGender.male);
    expect(find.byType(PromptGroupTile), findsNWidgets(2));
  });

  testWidgets('single mode shows the whole prompt', (tester) async {
    final storage = MemoryLocalStorage()
      ..values[StorageKeys.characterPromptsGrouped] = false;
    await _pump(tester, storage: storage);
    await _expand(tester, 'a');
    expect(find.byType(PromptGroupTile), findsNothing);
    expect(
      find.byKey(const ValueKey('character-workspace-whole')),
      findsOneWidget,
    );
    expect(find.text('girl, red hair'), findsWidgets);
  });

  testWidgets('a new name applies while typing', (tester) async {
    final container = await _pump(tester);
    await _expand(tester, 'a');
    final field = find.descendant(
      of: find.byKey(const ValueKey('character-workspace-name-a')),
      matching: find.byType(EditableText),
    );
    await tester.enterText(field, 'Alicia');
    await tester.pump();
    expect(_character(container, 'a').name, 'Alicia');
  });

  testWidgets('manual rows show where each character stands', (tester) async {
    final container = await _pump(
      tester,
      config: const CharacterPromptConfig(
        characters: [_girl, _boy],
        globalAiChoice: false,
      ),
    );
    final params = container.read(generationParamsNotifierProvider);
    final map = tester.getSize(
      find.byKey(const ValueKey('character_workspace_map_a')),
    );
    expect(map.aspectRatio, closeTo(params.width / params.height, 0.03));

    container
        .read(generationParamsNotifierProvider.notifier)
        .updateSize(1216, 832);
    await tester.pumpAndSettle();
    final turned = tester.getSize(
      find.byKey(const ValueKey('character_workspace_map_a')),
    );
    expect(turned.aspectRatio, closeTo(1216 / 832, 0.03));

    await tester.tap(
      find.byKey(const ValueKey('character-workspace-position-mode')),
    );
    await tester.pumpAndSettle();
    expect(
      container.read(characterPromptNotifierProvider).globalAiChoice,
      isTrue,
    );
    expect(
      find.byKey(const ValueKey('character_workspace_map_a')),
      findsNothing,
    );
  });

  testWidgets('placement: tap moves the selection, drag moves a marker', (
    tester,
  ) async {
    final container = await _pump(tester);
    await _openPlacement(tester);
    expect(
      container.read(characterPromptNotifierProvider).globalAiChoice,
      isFalse,
    );

    await tester.tapAt(_at(tester, 0.2, 0.85));
    await tester.pumpAndSettle();
    final alice = _position(container, 'a');
    expect(alice.column, closeTo(0.2, 0.01));
    expect(alice.row, closeTo(0.85, 0.01));

    final bob = _position(container, 'b');
    final picture = tester.getRect(
      find.byKey(const ValueKey('character-place-picture')),
    );
    await tester.dragFrom(
      _at(tester, bob.column, bob.row),
      Offset(-picture.width * 0.2, -picture.height * 0.2),
    );
    await tester.pumpAndSettle();
    final moved = _position(container, 'b');
    expect(moved.column, closeTo(bob.column - 0.2, 0.01));
    expect(moved.row, closeTo(bob.row - 0.2, 0.01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('placement: snap and hand back to AI', (tester) async {
    final container = await _pump(tester);
    await _openPlacement(tester);
    await tester.tap(find.byKey(const ValueKey('character-place-snap')));
    await tester.pumpAndSettle();
    await tester.tapAt(_at(tester, 0.33, 0.93));
    await tester.pumpAndSettle();
    final alice = _position(container, 'a');
    expect(alice.column, closeTo(0.3, 0.001));
    expect(alice.row, closeTo(0.9, 0.001));

    await tester.tap(find.byKey(const ValueKey('character-place-hand-to-ai')));
    await tester.pumpAndSettle();
    expect(
      container.read(characterPromptNotifierProvider).globalAiChoice,
      isTrue,
    );
    expect(find.byKey(const ValueKey('character-placement')), findsNothing);
  });

  testWidgets('a 320 wide phone with 3x text keeps everything usable', (
    tester,
  ) async {
    await _pump(tester, size: const Size(320, 640), textScale: 3);
    expect(tester.takeException(), isNull);
    await _expand(tester, 'a');
    expect(find.byType(CharacterWorkspaceEditor), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('place'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('character-place-done')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('short landscape places the canvas beside the controls', (
    tester,
  ) async {
    await _pump(tester, size: const Size(800, 360));
    await _openPlacement(tester);
    final picture = tester.getRect(
      find.byKey(const ValueKey('character-place-picture')),
    );
    final done = tester.getRect(
      find.byKey(const ValueKey('character-place-done')),
    );
    expect(picture.height, greaterThan(180));
    expect(done.left, greaterThanOrEqualTo(picture.right));
    expect(tester.takeException(), isNull);
  });
}
