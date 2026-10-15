import 'dart:convert';

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
import 'package:nai_launcher/presentation/providers/image_generation_provider.dart';
import 'package:nai_launcher/presentation/screens/generation/mobile_workbench/character_panel/character_panel.dart';
import 'package:nai_launcher/presentation/screens/generation/widgets/prompt_group_tile.dart';
import 'package:nai_launcher/presentation/widgets/character/inline_character_editor.dart';

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

Future<ProviderContainer> _pumpPanel(
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
              body: Center(
                child: FilledButton(
                  onPressed: () => showCharacterPanel(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.text('open')));
}

AppLocalizations _l10n(WidgetTester tester) => AppLocalizations.of(
  tester.element(find.byKey(const ValueKey('character-panel'))),
)!;

List<String> _ids(ProviderContainer container) => [
  for (final c in container.read(characterPromptNotifierProvider).characters)
    c.id,
];

Future<void> _openPlacement(WidgetTester tester) async {
  final manual = find.text(_l10n(tester).characterPanel_positionManual);
  await tester.ensureVisible(manual);
  await tester.pumpAndSettle();
  await tester.tap(manual);
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
  testWidgets('two taps on the cross delete a card and undo restores it', (
    tester,
  ) async {
    final container = await _pumpPanel(tester);
    final cross = find.byKey(const ValueKey('character_panel_delete_b'));

    await tester.tap(cross);
    await tester.pump();
    expect(_ids(container), ['a', 'b', 'c']);
    await tester.tap(cross);
    await tester.pumpAndSettle();
    expect(_ids(container), ['a', 'c']);

    await tester.tap(find.byKey(const ValueKey('character-panel-toast-undo')));
    await tester.pumpAndSettle();
    expect(_ids(container), ['a', 'b', 'c']);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('the gender choice rewrites the first tag of the prompt', (
    tester,
  ) async {
    final container = await _pumpPanel(tester);
    await tester.tap(find.text('Bob'));
    await tester.pumpAndSettle();
    expect(find.byType(CharacterPromptEditor), findsOneWidget);

    await tester.tap(find.text(_l10n(tester).characterEditor_addOther));
    await tester.pumpAndSettle();
    final bob = container
        .read(characterPromptNotifierProvider)
        .findCharacterById('b')!;
    expect(bob.prompt, 'glasses');
    expect(bob.effectiveGender, CharacterGender.other);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cards show a position map in the generation shape', (
    tester,
  ) async {
    final container = await _pumpPanel(
      tester,
      config: const CharacterPromptConfig(
        characters: [_girl, _boy],
        globalAiChoice: false,
      ),
    );
    final params = container.read(generationParamsNotifierProvider);
    final map = tester.getSize(
      find.byKey(const ValueKey('character_panel_map_a')),
    );
    expect(map.aspectRatio, closeTo(params.width / params.height, 0.02));

    container
        .read(generationParamsNotifierProvider.notifier)
        .updateSize(1216, 832);
    await tester.pumpAndSettle();
    final turned = tester.getSize(
      find.byKey(const ValueKey('character_panel_map_a')),
    );
    expect(turned.aspectRatio, closeTo(1216 / 832, 0.02));
  });

  testWidgets('placement: tap moves the selection, drag moves a marker', (
    tester,
  ) async {
    final container = await _pumpPanel(tester);
    await _openPlacement(tester);

    // Alice is selected first; a tap on empty space moves her there.
    await tester.tapAt(_at(tester, 0.2, 0.85));
    await tester.pumpAndSettle();
    var alice = _position(container, 'a');
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
    alice = _position(container, 'a');
    expect(alice.column, closeTo(0.2, 0.01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('snap puts a placed character on its cell centre', (
    tester,
  ) async {
    final container = await _pumpPanel(tester);
    await _openPlacement(tester);
    final snap = find.byKey(const ValueKey('character-place-snap'));
    expect(tester.getRect(snap).right, lessThanOrEqualTo(390));
    await tester.tap(snap);
    await tester.pumpAndSettle();

    await tester.tapAt(_at(tester, 0.33, 0.93));
    await tester.pumpAndSettle();
    final alice = _position(container, 'a');
    expect(alice.column, closeTo(0.3, 0.001));
    expect(alice.row, closeTo(0.9, 0.001));
  });

  testWidgets('hand to AI keeps placed positions and returns to the grid', (
    tester,
  ) async {
    final container = await _pumpPanel(tester);
    await _openPlacement(tester);
    await tester.tapAt(_at(tester, 0.2, 0.85));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('character-place-hand-to-ai')));
    await tester.pumpAndSettle();
    final config = container.read(characterPromptNotifierProvider);
    expect(config.globalAiChoice, isTrue);
    expect(
      config.findCharacterById('a')!.customPosition?.column,
      closeTo(0.2, 0.01),
    );
    expect(find.byKey(const ValueKey('character-panel-adjust')), findsNothing);
  });

  testWidgets('short landscape puts the controls beside a usable canvas', (
    tester,
  ) async {
    await _pumpPanel(tester, size: const Size(800, 360));
    await _openPlacement(tester);

    final picture = tester.getRect(
      find.byKey(const ValueKey('character-place-picture')),
    );
    final done = tester.getRect(
      find.byKey(const ValueKey('character-place-done')),
    );
    expect(picture.height, greaterThan(180));
    expect(done.left, greaterThanOrEqualTo(picture.right));
    expect(done.bottom, lessThanOrEqualTo(360));
    expect(
      find.byKey(const ValueKey('character-place-chip-c')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('grouped mode shows sections and writes them back', (
    tester,
  ) async {
    final container = await _pumpPanel(tester);
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('character-panel-editor-mode')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('character_positive_prompt_group_grid')),
      findsOneWidget,
    );
    expect(find.byType(PromptGroupTile), findsOneWidget);

    final dot = find.byWidgetPredicate(
      (widget) =>
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith(
            'prompt_group_enabled_',
          ),
    );
    await tester.tap(dot);
    await tester.pumpAndSettle();
    final alice = container
        .read(characterPromptNotifierProvider)
        .findCharacterById('a')!;
    expect(alice.prompt, '');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a gender change keeps the sections apart', (tester) async {
    final storage = MemoryLocalStorage();
    storage.values[StorageKeys.characterPromptGroupState] = jsonEncode({
      'a': {
        'mode': 'grouped',
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
    final container = await _pumpPanel(tester, storage: storage);
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();
    expect(find.byType(PromptGroupTile), findsNWidgets(2));

    await tester.tap(find.text(_l10n(tester).characterEditor_addMale));
    await tester.pumpAndSettle();

    final alice = container
        .read(characterPromptNotifierProvider)
        .findCharacterById('a')!;
    expect(alice.prompt, 'boy, red hair');
    expect(alice.effectiveGender, CharacterGender.male);
    expect(find.byType(PromptGroupTile), findsNWidgets(2));
    final saved = jsonDecode(
      storage.values[StorageKeys.characterPromptGroupState]! as String,
    );
    expect(saved['a']['positivePrompt'], 'boy, red hair');
    expect(tester.takeException(), isNull);
  });

  testWidgets('pages below the header leave it in view', (tester) async {
    await _pumpPanel(tester);
    final panel = tester.getRect(find.byKey(const ValueKey('character-panel')));
    // 52 of header plus the sheet's own 16 gap above the panel.
    expect(panel.top, closeTo(52, 1));
  });

  testWidgets('the edit page keeps one control row and pins its footer', (
    tester,
  ) async {
    final container = await _pumpPanel(tester);
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();

    Rect rectOf(Key key) => tester.getRect(find.byKey(key));
    const toggle = ValueKey('tag-mode-button');
    const clear = ValueKey('character-prompt-clear-button');
    const mode = ValueKey('character-panel-editor-mode');
    final before = [rectOf(toggle), rectOf(clear), rectOf(mode)];
    expect(before[2].left, greaterThan(before[1].right - 1));
    expect(before[1].left, greaterThan(before[0].right - 1));

    await tester.tap(find.byKey(mode));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('character_positive_prompt_group_grid')),
      findsOneWidget,
    );
    expect([rectOf(toggle), rectOf(clear), rectOf(mode)], before);

    // Position and actions sit at the bottom of the panel.
    final panel = rectOf(const ValueKey('character-panel'));
    final footer = rectOf(const ValueKey('character-panel-edit-footer'));
    expect(panel.bottom - footer.bottom, lessThan(8));

    // The include switch lives in the header, left of the arrows.
    final include = rectOf(const ValueKey('character-panel-include'));
    expect(
      include.right,
      lessThanOrEqualTo(
        rectOf(const ValueKey('character-panel-previous')).left,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('character-panel-include')));
    await tester.pumpAndSettle();
    expect(
      container
          .read(characterPromptNotifierProvider)
          .findCharacterById('a')!
          .enabled,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a new name applies while typing, without Enter', (tester) async {
    final container = await _pumpPanel(tester);
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();

    final field = find.descendant(
      of: find.byKey(const ValueKey('character-panel-name-a')),
      matching: find.byType(EditableText),
    );
    await tester.enterText(field, 'Alicia');
    await tester.pump();
    expect(
      container
          .read(characterPromptNotifierProvider)
          .findCharacterById('a')!
          .name,
      'Alicia',
    );

    // The name sits on the back arrow's line.
    final back = tester.getCenter(
      find.byKey(const ValueKey('character-panel-back')),
    );
    expect(tester.getCenter(field).dy, closeTo(back.dy, 2));

    await tester.tap(find.byKey(const ValueKey('character-panel-back')));
    await tester.pumpAndSettle();
    expect(find.text('Alicia'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('every page fits a 320 wide phone with 3x text', (tester) async {
    await _pumpPanel(tester, size: const Size(320, 640), textScale: 3);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();
    expect(find.byType(CharacterPromptEditor), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('character-panel-back')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('character_panel_add_tile')),
    );
    await tester.tap(find.byKey(const ValueKey('character_panel_add_tile')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('character-panel-add-female')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('character-panel-back')));
    await tester.pumpAndSettle();
    await _openPlacement(tester);
    expect(
      find.byKey(const ValueKey('character-place-picture')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('character-place-done')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
