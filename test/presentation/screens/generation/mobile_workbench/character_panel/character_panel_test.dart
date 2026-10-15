import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/storage/local_storage_service.dart';
import 'package:nai_launcher/data/models/character/character_prompt.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/adaptive/interaction_policy.dart';
import 'package:nai_launcher/presentation/providers/character_place_options_provider.dart';
import 'package:nai_launcher/presentation/providers/character_prompt_provider.dart';
import 'package:nai_launcher/presentation/providers/image_generation_provider.dart';
import 'package:nai_launcher/presentation/screens/generation/mobile_workbench/character_panel/character_panel.dart';
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
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageServiceProvider.overrideWith((ref) => MemoryLocalStorage()),
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
