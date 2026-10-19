import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/agent/agent_types.dart';
import 'package:nai_launcher/core/constants/storage_keys.dart';
import 'package:nai_launcher/core/storage/local_storage_service.dart';
import 'package:nai_launcher/data/models/character/character_prompt.dart';
import 'package:nai_launcher/data/models/fixed_tag/fixed_tag_entry.dart';
import 'package:nai_launcher/data/models/fixed_tag/fixed_tag_prompt_type.dart';
import 'package:nai_launcher/data/models/image/image_params.dart'
    show ImageParams;
import 'package:nai_launcher/data/services/prompt_group/character_section_store.dart';
import 'package:nai_launcher/presentation/agent_chat/services/fixed_tags_toolbox.dart';
import 'package:nai_launcher/presentation/agent_chat/services/prompt_section_toolbox.dart';
import 'package:nai_launcher/presentation/agent_chat/services/prompt_toolbox.dart';
import 'package:nai_launcher/presentation/providers/character_prompt_provider.dart';
import 'package:nai_launcher/presentation/providers/character_workspace_provider.dart';
import 'package:nai_launcher/presentation/providers/generation/generation_params_notifier.dart';

import '../../../helpers/memory_local_storage.dart';

final _refProvider = Provider<Ref>((ref) => ref);

/// In-memory character list; the real notifier persists to Hive.
class _Characters extends CharacterPromptNotifier {
  _Characters(this.initial);

  final List<CharacterPrompt> initial;

  @override
  CharacterPromptConfig build() {
    watchFixedTags();
    return CharacterPromptConfig(characters: initial);
  }

  @override
  void updateCharacter(CharacterPrompt character) =>
      state = state.updateCharacter(character);

  @override
  Future<bool> updateCharacterPersisted(CharacterPrompt character) async {
    state = state.updateCharacter(character);
    return true;
  }

  @override
  Future<({CharacterPrompt character, bool persisted})?> addCharacterPersisted(
    CharacterGender gender, {
    required String name,
    required String prompt,
    String? negativePrompt,
    required bool enabled,
    required CharacterPositionMode positionMode,
    CharacterPosition? customPosition,
  }) async {
    final existing = {for (final c in state.characters) c.id};
    state = state.addCharacter(
      gender: gender,
      name: name,
      prompt: prompt,
      negativePrompt: negativePrompt,
    );
    final created = state.characters
        .firstWhere((c) => !existing.contains(c.id))
        .copyWith(enabled: enabled, positionMode: positionMode);
    state = state.updateCharacter(created);
    return (character: created, persisted: true);
  }
}

class _Params extends GenerationParamsNotifier {
  @override
  ImageParams build() => const ImageParams(prompt: 'masterpiece');

  @override
  void updatePrompt(String prompt) => state = state.copyWith(prompt: prompt);
}

FixedTagEntry _tag(
  String id,
  String name,
  String content, {
  FixedTagPromptType type = FixedTagPromptType.positive,
}) => FixedTagEntry.create(
  name: name,
  content: content,
  promptType: type,
).copyWith(id: id);

const _alice = CharacterPrompt(
  id: 'alice',
  name: 'Alice',
  prompt: 'girl, red eyes, silver hair',
  negativePrompt: 'bad hands',
);

ProviderContainer _setUp({
  bool grouped = true,
  bool storeAliceSections = true,
}) {
  final storage = MemoryLocalStorage()
    ..values[StorageKeys.characterPromptsGrouped] = grouped
    ..values[StorageKeys.fixedTagsData] = jsonEncode([
      _tag('eyes', '红瞳', 'red eyes').toJson(),
      _tag('light', '逆光', 'backlighting').toJson(),
      _tag(
        'hands',
        '坏手',
        'bad hands',
        type: FixedTagPromptType.negative,
      ).toJson(),
    ]);
  if (storeAliceSections) {
    storage.values[StorageKeys.characterPromptGroupState] = jsonEncode({
      'alice': {
        'version': 1,
        'positivePrompt': _alice.prompt,
        'negativePrompt': _alice.negativePrompt,
        'positiveSections': [
          {'id': 's1', 'text': 'girl'},
          {'id': 's2', 'text': 'red eyes', 'fixedTagId': 'eyes'},
          {'id': 's3', 'text': 'silver hair'},
          {'id': 's4', 'text': 'smile', 'enabled': false},
        ],
        'negativeSections': [
          {'id': 'n1', 'text': 'bad hands'},
        ],
      },
    });
  }
  final container = ProviderContainer(
    overrides: [
      localStorageServiceProvider.overrideWithValue(storage),
      characterPromptNotifierProvider.overrideWith(
        () => _Characters(const [_alice]),
      ),
      generationParamsNotifierProvider.overrideWith(_Params.new),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

AgentTool _tool(ProviderContainer container, String name) {
  final ref = container.read(_refProvider);
  return [
    ...PromptToolbox(ref).tools(),
    ...PromptSectionToolbox(ref).tools(),
    ...FixedTagsToolbox(ref).tools(),
  ].firstWhere((tool) => tool.name == name);
}

Future<Map<String, dynamic>> _run(
  ProviderContainer container,
  String name,
  Map<String, dynamic> params,
) async {
  final result = await _tool(container, name).execute('call', params);
  return Map<String, dynamic>.from(result.details as Map);
}

Map<String, Object?> _stored(ProviderContainer container, String id) =>
    CharacterSectionStore.readAll(
          container.read(localStorageServiceProvider),
        )[id]!
        as Map<String, Object?>;

CharacterPrompt _character(ProviderContainer container, String id) =>
    container.read(characterPromptNotifierProvider).findCharacterById(id)!;

void main() {
  test(
    'get_prompt_state lists each character\'s sections in grouped mode',
    () async {
      final container = _setUp();
      final state = await _run(container, 'get_prompt_state', {});

      expect(state['character_editor_mode'], 'grouped');
      final alice = (state['characters'] as List).single as Map;
      final sections = alice['positive_sections'] as List;
      expect(sections.map((s) => (s as Map)['id']), ['s1', 's2', 's3', 's4']);
      expect(sections[1], {
        'id': 's2',
        'text': 'red eyes',
        'enabled': true,
        'fixed_tag_id': 'eyes',
        'fixed_tag_name': '红瞳',
        'keep_in_main': false,
      });
      expect(alice.containsKey('library_entry_id'), isFalse);
    },
  );

  test(
    'edit_prompt_sections edits a character and keeps its sections',
    () async {
      final container = _setUp();
      final result = await _run(container, 'edit_prompt_sections', {
        'prompt_type': 'positive',
        'character_id': 'alice',
        'operations': [
          {'action': 'update', 'id': 's4', 'enabled': true},
          {'action': 'add', 'fixed_tag_id': 'light'},
          {'action': 'add', 'text': 'school uniform', 'index': 3},
        ],
      });

      expect(result['ok'], isTrue);
      const prompt =
          'girl, red eyes, silver hair, school uniform, smile, backlighting';
      expect(result['prompt'], prompt);
      expect(_character(container, 'alice').prompt, prompt);
      final stored = _stored(container, 'alice');
      expect(stored['positivePrompt'], prompt);
      expect((stored['positiveSections'] as List).length, 6);
      // The character now takes both fixed tags out of the main prompt.
      expect(
        container
            .read(characterPromptNotifierProvider.notifier)
            .claimedFixedTags(),
        {'eyes', 'light'},
      );
    },
  );

  test(
    'fixed-tag sections follow their tag and stay with characters',
    () async {
      final container = _setUp();
      final rewrite = await _run(container, 'edit_prompt_sections', {
        'prompt_type': 'positive',
        'character_id': 'alice',
        'operations': [
          {'action': 'update', 'id': 's2', 'text': 'blue eyes'},
        ],
      });
      expect(rewrite['code'], 'fixed_tag_section');

      final wrongSide = await _run(container, 'edit_prompt_sections', {
        'prompt_type': 'positive',
        'character_id': 'alice',
        'operations': [
          {'action': 'add', 'fixed_tag_id': 'hands'},
        ],
      });
      expect(wrongSide['code'], 'fixed_tag_side');

      final keep = await _run(container, 'edit_prompt_sections', {
        'prompt_type': 'positive',
        'character_id': 'alice',
        'operations': [
          {'action': 'update', 'id': 's2', 'keep_in_main': true},
        ],
      });
      expect(keep['ok'], isTrue);
      expect(
        container
            .read(characterPromptNotifierProvider.notifier)
            .claimedFixedTags(),
        isEmpty,
      );
    },
  );

  test('update_character replaces only the enabled text sections', () async {
    final container = _setUp();
    final result = await _run(container, 'update_character', {
      'id': 'alice',
      'prompt': 'girl, twin tails',
    });

    final character = result['character'] as Map;
    final sections = character['positive_sections'] as List;
    expect(
      [for (final s in sections) (s as Map)['text']],
      ['girl, twin tails', 'red eyes', 'smile'],
    );
    expect(_character(container, 'alice').prompt, 'girl, twin tails, red eyes');
    expect(
      _stored(container, 'alice')['positivePrompt'],
      'girl, twin tails, red eyes',
    );
  });

  test('add_character takes its prompt as sections', () async {
    final container = _setUp();
    final result = await _run(container, 'add_character', {
      'name': 'Bob',
      'gender': 'male',
      'prompt_sections': [
        {'text': 'boy'},
        {'fixed_tag_id': 'eyes'},
        {'text': 'glasses', 'enabled': false},
      ],
    });

    final bob = result['character'] as Map;
    expect(bob['prompt'], 'boy, red eyes');
    expect((bob['positive_sections'] as List).length, 3);
    final id = bob['id'] as String;
    expect(_stored(container, id)['positivePrompt'], 'boy, red eyes');
  });

  test('section lists and prompts cannot be given together', () async {
    final container = _setUp();
    final result = await _run(container, 'add_character', {
      'name': 'Bob',
      'prompt': 'boy',
      'prompt_sections': [
        {'text': 'boy'},
      ],
    });
    expect(result['code'], 'invalid_sections');
  });

  test(
    'character sections need grouped mode unless asked to enable it',
    () async {
      final container = _setUp(grouped: false, storeAliceSections: false);
      final operations = [
        {'action': 'add', 'text': 'smile'},
      ];
      final refused = await _run(container, 'edit_prompt_sections', {
        'prompt_type': 'positive',
        'character_id': 'alice',
        'operations': operations,
      });
      expect(refused['code'], 'character_prompts_not_grouped');

      final enabled = await _run(container, 'edit_prompt_sections', {
        'prompt_type': 'positive',
        'character_id': 'alice',
        'operations': operations,
        'enable_grouped_mode': true,
      });
      expect(enabled['prompt'], 'girl, red eyes, silver hair, smile');
      expect(container.read(characterPromptsGroupedProvider), isTrue);
    },
  );

  test('the main prompt has no fixed-tag sections', () async {
    final container = _setUp();
    final result = await _run(container, 'edit_prompt_sections', {
      'prompt_type': 'positive',
      'operations': [
        {'action': 'add', 'fixed_tag_id': 'eyes'},
      ],
      'enable_grouped_mode': true,
    });
    expect(result['code'], 'invalid_operations');
    expect(result['message'], contains('only in characters'));
  });

  test('list_fixed_tags names the characters that claim a tag', () async {
    final container = _setUp();
    final result = await _run(container, 'list_fixed_tags', {});

    final entries = <Object?, Map>{
      for (final entry in result['entries'] as List)
        (entry as Map)['id']: entry,
    };
    expect(entries['eyes']!['claimed_by'], [
      {'id': 'alice', 'name': 'Alice'},
    ]);
    expect((entries['light'] as Map).containsKey('claimed_by'), isFalse);
    final prefixes = (result['projection'] as Map)['positive_prefixes'] as List;
    expect([for (final p in prefixes) (p as FixedTagEntry).id], ['light']);
  });

  group('the first tag follows the character gender', () {
    test('add_character starts a female prompt with girl', () async {
      final container = _setUp(grouped: false);
      final result = await _run(container, 'add_character', {
        'name': 'Miku',
        'gender': 'female',
        'prompt': 'hatsune miku, twintails, school uniform',
      });
      final miku = result['character'] as Map;
      expect(miku['prompt'], 'girl, hatsune miku, twintails, school uniform');
      final created = _character(container, miku['id'] as String);
      expect(created.effectiveGender, CharacterGender.female);
    });

    test('add_character moves an existing 1girl to the front', () async {
      final container = _setUp(grouped: false);
      final result = await _run(container, 'add_character', {
        'name': 'Miku',
        'prompt': 'hatsune miku, 1girl, twintails',
      });
      expect(
        (result['character'] as Map)['prompt'],
        '1girl, hatsune miku, twintails',
      );
    });

    test('add_character leads the first section in grouped mode', () async {
      final container = _setUp();
      final result = await _run(container, 'add_character', {
        'name': 'Rin',
        'gender': 'female',
        'prompt_sections': [
          {'text': 'kagamine rin'},
          {'text': 'sailor collar'},
        ],
      });
      final rin = result['character'] as Map;
      expect(rin['prompt'], 'girl, kagamine rin, sailor collar');
      final sections = rin['positive_sections'] as List;
      expect((sections.first as Map)['text'], 'girl, kagamine rin');
    });

    test('update_character with a new gender rewrites the first tag', () async {
      final container = _setUp(grouped: false, storeAliceSections: false);
      await _run(container, 'update_character', {
        'id': 'alice',
        'gender': 'male',
      });
      final alice = _character(container, 'alice');
      expect(alice.prompt, 'boy, red eyes, silver hair');
      expect(alice.effectiveGender, CharacterGender.male);
    });

    test('a rewritten prompt keeps the current gender', () async {
      final container = _setUp(grouped: false, storeAliceSections: false);
      await _run(container, 'update_character', {
        'id': 'alice',
        'prompt': 'red eyes, maid',
      });
      expect(_character(container, 'alice').prompt, 'girl, red eyes, maid');
    });
  });
}
