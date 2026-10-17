import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/agent/agent_types.dart';
import 'package:nai_launcher/core/agent/permissions/agent_permission.dart';
import 'package:nai_launcher/core/agent/permissions/tool_permission_catalog.dart';
import 'package:nai_launcher/core/constants/storage_keys.dart';
import 'package:nai_launcher/core/storage/local_storage_service.dart';
import 'package:nai_launcher/data/models/character/character_library_entry.dart';
import 'package:nai_launcher/data/models/character/character_prompt.dart';
import 'package:nai_launcher/data/models/fixed_tag/fixed_tag_entry.dart';
import 'package:nai_launcher/data/models/gallery/prompt_group_snapshot.dart';
import 'package:nai_launcher/data/models/image/image_params.dart'
    show ImageParams;
import 'package:nai_launcher/presentation/agent_chat/services/character_library_toolbox.dart';
import 'package:nai_launcher/presentation/providers/character_library_provider.dart';
import 'package:nai_launcher/presentation/providers/character_prompt_provider.dart';
import 'package:nai_launcher/presentation/providers/generation/generation_params_notifier.dart';

import '../../../helpers/memory_local_storage.dart';

final _refProvider = Provider<Ref>((ref) => ref);

/// In-memory character bar that holds two characters at most.
class _Characters extends CharacterPromptNotifier {
  @override
  CharacterPromptConfig build() {
    watchFixedTags();
    return const CharacterPromptConfig();
  }

  @override
  int get characterLimit => 2;

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
}

class _Params extends GenerationParamsNotifier {
  @override
  ImageParams build() => const ImageParams();
}

final _now = DateTime(2026, 10, 17);

CharacterLibraryEntry _entry(
  String id,
  String name, {
  List<PromptGroupSectionSnapshot> sections = const [],
  bool favorite = false,
}) => CharacterLibraryEntry(
  id: id,
  name: name,
  positiveSections: sections,
  favorite: favorite,
  createdAt: _now,
  updatedAt: _now,
);

ProviderContainer _setUp() {
  final storage = MemoryLocalStorage()
    ..values[StorageKeys.fixedTagsData] = jsonEncode([
      FixedTagEntry.create(
        name: '红瞳',
        content: 'red eyes',
      ).copyWith(id: 'eyes').toJson(),
    ])
    ..values[StorageKeys.characterLibraryData] = jsonEncode([
      _entry(
        'c1',
        'Alice',
        sections: const [
          PromptGroupSectionSnapshot(id: 's1', text: 'girl, silver hair'),
          PromptGroupSectionSnapshot(id: 's2', text: '', fixedTagId: 'eyes'),
        ],
      ).toJson(),
      _entry(
        'c2',
        'Bob',
        favorite: true,
        sections: const [PromptGroupSectionSnapshot(id: 's3', text: 'boy')],
      ).toJson(),
      _entry('c3', 'Carol').toJson(),
    ]);
  final container = ProviderContainer(
    overrides: [
      localStorageServiceProvider.overrideWithValue(storage),
      characterPromptNotifierProvider.overrideWith(_Characters.new),
      generationParamsNotifierProvider.overrideWith(_Params.new),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<Map<String, dynamic>> _run(
  ProviderContainer container,
  String name,
  Map<String, dynamic> params,
) async {
  final tool = CharacterLibraryToolbox(
    container.read(_refProvider),
  ).tools().firstWhere((tool) => tool.name == name);
  final AgentToolResult result = await tool.execute('call', params);
  return Map<String, dynamic>.from(result.details as Map);
}

void main() {
  test('list puts favorites first and filters by query', () async {
    final container = _setUp();
    final all = await _run(container, 'list_character_library', {});
    expect(
      [for (final e in all['entries'] as List) (e as Map)['name']],
      ['Bob', 'Alice', 'Carol'],
    );

    final hair = await _run(container, 'list_character_library', {
      'query': 'SILVER',
    });
    expect(hair['match_count'], 1);
    expect(((hair['entries'] as List).single as Map)['id'], 'c1');
  });

  test('get shows sections with fixed-tag names', () async {
    final container = _setUp();
    final result = await _run(container, 'get_character_library_entry', {
      'id': 'c1',
    });
    final sections = (result['entry'] as Map)['positive_sections'] as List;
    expect(sections.last, {
      'id': 's2',
      'text': '',
      'enabled': true,
      'fixed_tag_id': 'eyes',
      'fixed_tag_name': '红瞳',
      'keep_in_main': false,
    });
  });

  test('add brings entries in with their sections, up to the limit', () async {
    final container = _setUp();
    final result = await _run(container, 'add_character_from_library', {
      'ids': ['c1', 'c2', 'c3'],
    });

    expect(result['added_count'], 2);
    expect(result['not_added_ids'], ['c3']);
    final alice = (result['characters'] as List).first as Map;
    // The fixed tag takes its current content.
    expect(alice['prompt'], 'girl, silver hair, red eyes');
    expect(alice['library_entry_id'], 'c1');
    expect(alice['library_unsaved_changes'], isFalse);
  });

  test('save updates the linked entry unless asked for a new one', () async {
    final container = _setUp();
    await _run(container, 'add_character_from_library', {
      'ids': ['c2'],
    });
    final bob = container
        .read(characterPromptNotifierProvider)
        .characters
        .single;
    container
        .read(characterPromptNotifierProvider.notifier)
        .updateCharacter(bob.copyWith(name: 'Robert'));

    final updated = await _run(container, 'save_character_to_library', {
      'character_id': bob.id,
    });
    expect(updated['created'], isFalse);
    expect((updated['entry'] as Map)['id'], 'c2');
    expect(
      container.read(characterLibraryProvider.notifier).byId('c2')!.name,
      'Robert',
    );

    final copy = await _run(container, 'save_character_to_library', {
      'character_id': bob.id,
      'as_new': true,
    });
    expect(copy['created'], isTrue);
    expect(container.read(characterLibraryProvider), hasLength(4));
  });

  test('every library tool sits in the prompt permission domain', () {
    final container = _setUp();
    final tools = CharacterLibraryToolbox(container.read(_refProvider)).tools();
    final descriptors = {
      for (final tool in tools)
        tool.name: describeAgentToolPermission(tool.name),
    };
    expect(descriptors.values.map((d) => d.domain).toSet(), {
      AgentPermissionDomain.prompt,
    });
    expect(
      descriptors['list_character_library']!.operation,
      AgentPermissionOperation.read,
    );
    expect(
      descriptors['save_character_to_library']!.operation,
      AgentPermissionOperation.update,
    );
  });

  test('unknown ids are reported', () async {
    final container = _setUp();
    final result = await _run(container, 'add_character_from_library', {
      'ids': ['missing'],
    });
    expect(result['code'], 'character_library_entry_not_found');
  });
}
