import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/constants/storage_keys.dart';
import 'package:nai_launcher/core/storage/local_storage_service.dart';
import 'package:nai_launcher/data/models/character/character_library_entry.dart';
import 'package:nai_launcher/data/models/character/character_prompt.dart';
import 'package:nai_launcher/data/models/fixed_tag/fixed_tag_entry.dart';
import 'package:nai_launcher/data/models/fixed_tag/fixed_tag_prompt_type.dart';
import 'package:nai_launcher/data/models/gallery/prompt_group_snapshot.dart';
import 'package:nai_launcher/data/services/prompt_group/character_section_store.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/adaptive/interaction_policy.dart';
import 'package:nai_launcher/presentation/providers/character_library_provider.dart';
import 'package:nai_launcher/presentation/providers/character_prompt_provider.dart';
import 'package:nai_launcher/presentation/providers/fixed_tags_provider.dart';
import 'package:nai_launcher/presentation/screens/character_library/character_library_editor_screen.dart';
import 'package:nai_launcher/presentation/screens/character_library/character_library_view.dart';
import 'package:nai_launcher/presentation/services/character_library_transfer.dart';

import '../../../helpers/memory_local_storage.dart';

/// In-memory character bar; the real notifier writes to Hive.
class _Characters extends CharacterPromptNotifier {
  @override
  CharacterPromptConfig build() {
    watchFixedTags();
    return const CharacterPromptConfig();
  }

  @override
  void addCharacter(
    CharacterGender gender, {
    String? name,
    String? prompt,
    String? negativePrompt,
    String? thumbnailPath,
  }) {
    if (state.characters.length >= 2) return;
    state = state.addCharacter(
      gender: gender,
      name: name,
      prompt: prompt,
      negativePrompt: negativePrompt,
    );
  }

  @override
  void updateCharacter(CharacterPrompt character) =>
      state = state.updateCharacter(character);

  @override
  void restoreConfig(CharacterPromptConfig config) => state = config;
}

FixedTagEntry _tag(
  String id,
  String name,
  String content, {
  bool enabled = true,
  FixedTagPromptType type = FixedTagPromptType.positive,
  FixedTagPosition position = FixedTagPosition.prefix,
}) => FixedTagEntry.create(
  name: name,
  content: content,
  enabled: enabled,
  promptType: type,
  position: position,
).copyWith(id: id);

final _now = DateTime(2026, 10, 16);

final _alice = CharacterLibraryEntry(
  id: 'c1',
  name: 'Alice',
  positiveSections: const [
    PromptGroupSectionSnapshot(id: 's1', text: 'red eyes', fixedTagId: 'eyes'),
    PromptGroupSectionSnapshot(id: 's2', text: 'girl, silver hair'),
  ],
  negativeSections: const [
    PromptGroupSectionSnapshot(
      id: 'n1',
      text: 'bad hands',
      fixedTagId: 'hands',
    ),
  ],
  category: '原创',
  favorite: true,
  createdAt: _now,
  updatedAt: _now,
);

final _bob = CharacterLibraryEntry(
  id: 'c2',
  name: 'Bob',
  gender: CharacterGender.male,
  positiveSections: const [
    PromptGroupSectionSnapshot(id: 's3', text: 'boy, glasses'),
  ],
  category: '同人',
  createdAt: _now,
  updatedAt: _now,
);

MemoryLocalStorage _storage() => MemoryLocalStorage()
  ..values[StorageKeys.fixedTagsData] = jsonEncode([
    _tag('eyes', '红瞳', 'red eyes').toJson(),
    _tag(
      'light',
      '逆光',
      'backlighting',
      enabled: false,
      position: FixedTagPosition.suffix,
    ).toJson(),
    _tag(
      'hands',
      '坏手',
      'bad hands',
      type: FixedTagPromptType.negative,
    ).toJson(),
  ])
  ..values[StorageKeys.characterLibraryData] = jsonEncode([
    _alice.toJson(),
    _bob.toJson(),
  ]);

Future<ProviderContainer> _pump(
  WidgetTester tester,
  Widget child, {
  MemoryLocalStorage? storage,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final memory = storage ?? _storage();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStorageServiceProvider.overrideWith((ref) => memory),
        characterPromptNotifierProvider.overrideWith(_Characters.new),
      ],
      child: MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: InteractionPolicyScope(
          initialPolicy: InteractionPolicy.touchFirst,
          child: Scaffold(body: child),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byWidget(child)));
}

void main() {
  testWidgets('favorites come first, then a group per category', (
    tester,
  ) async {
    await _pump(tester, const CharacterLibraryView());
    expect(find.text('收藏  1'), findsOneWidget);
    expect(find.text('同人  1'), findsOneWidget);
    expect(find.text('原创  1'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('character_library_row_c1')));
    await tester.pumpAndSettle();
    expect(find.textContaining('红瞳 · '), findsOneWidget);
    expect(find.textContaining('坏手 · '), findsOneWidget);
    // The fixed tag is on in the main prompt: the row says it moves over.
    expect(find.textContaining('橙点'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('adding brings sections and fixed tags into the bar', (
    tester,
  ) async {
    final container = await _pump(tester, const CharacterLibraryView());
    await tester.tap(find.byKey(const ValueKey('character_library_row_c1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('character_library_add_c1')));
    await tester.pumpAndSettle();

    final added = container
        .read(characterPromptNotifierProvider)
        .characters
        .single;
    expect(added.name, 'Alice');
    expect(added.prompt, 'red eyes, girl, silver hair');
    expect(added.negativePrompt, 'bad hands');
    final sections =
        CharacterSectionStore.readAll(
              container.read(localStorageServiceProvider),
            )[added.id]!
            as Map;
    expect((sections['positiveSections'] as List).first['fixedTagId'], 'eyes');
    expect(
      container.read(characterLibraryProvider.notifier).byId('c1')!.useCount,
      1,
    );

    // The bar character takes its fixed tags from the main prompt.
    final notifier = container.read(characterPromptNotifierProvider.notifier);
    expect(notifier.claimedFixedTags(), {'eyes', 'hands'});

    final transfer = CharacterLibraryTransfer(container.read);
    expect(transfer.linkedEntryId(added.id), 'c1');
    expect(transfer.hasUnsavedChanges(added), isFalse);
    notifier.updateCharacter(added.copyWith(name: 'Alicia'));
    final renamed = container.read(characterPromptNotifierProvider).characters;
    expect(transfer.hasUnsavedChanges(renamed.single), isTrue);

    transfer.saveFromPanel(renamed.single, asNew: false);
    expect(
      container.read(characterLibraryProvider.notifier).byId('c1')!.name,
      'Alicia',
    );
    expect(transfer.hasUnsavedChanges(renamed.single), isFalse);
    expect(container.read(characterLibraryProvider), hasLength(2));
  });

  testWidgets('edited fixed tags reach the characters using them', (
    tester,
  ) async {
    final container = await _pump(tester, const CharacterLibraryView());
    CharacterLibraryTransfer(container.read).addToPanel([_alice]);
    final fixedTags = container.read(fixedTagsNotifierProvider.notifier);
    final eyes = container
        .read(fixedTagsNotifierProvider)
        .entries
        .firstWhere((entry) => entry.id == 'eyes');
    await fixedTags.updateEntry(eyes.copyWith(content: 'golden eyes'));
    await tester.pump();
    expect(
      container.read(characterPromptNotifierProvider).characters.single.prompt,
      'golden eyes, girl, silver hair',
    );
  });

  testWidgets('several characters go into the bar at once', (tester) async {
    final container = await _pump(tester, const CharacterLibraryView());
    await tester.tap(find.byKey(const ValueKey('character_library_select')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('character_library_row_c1')));
    await tester.tap(find.byKey(const ValueKey('character_library_row_c2')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('character_library_add_selected')),
    );
    await tester.pumpAndSettle();
    expect(
      [
        for (final character
            in container.read(characterPromptNotifierProvider).characters)
          character.name,
      ],
      ['Alice', 'Bob'],
    );
  });

  testWidgets('the editor shows fixed tags as cards and brings in more', (
    tester,
  ) async {
    final container = await _pump(
      tester,
      const CharacterLibraryEditorScreen(entryId: 'c1'),
    );
    expect(find.text('固定词 · 红瞳'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('prompt_group_claim_note')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('prompt_group_add_fixed_tag')));
    await tester.pumpAndSettle();
    // Only positive tags; the one already in is greyed out.
    expect(
      find.byKey(const ValueKey('fixed_tag_reference_hands')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('fixed_tag_reference_light')));
    await tester.pumpAndSettle();

    final entry = container.read(characterLibraryProvider.notifier).byId('c1')!;
    expect(entry.positiveSections.last.fixedTagId, 'light');
    expect(entry.prompt, 'red eyes, girl, silver hair, backlighting');
    expect(tester.takeException(), isNull);
  });
}
