import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/agent/agent_types.dart';
import 'package:nai_launcher/core/constants/storage_keys.dart';
import 'package:nai_launcher/core/storage/local_storage_service.dart';
import 'package:nai_launcher/data/models/character/character_prompt.dart';
import 'package:nai_launcher/data/models/gallery/prompt_group_snapshot.dart';
import 'package:nai_launcher/data/models/image/image_params.dart'
    show ImageParams;
import 'package:nai_launcher/presentation/agent_chat/services/prompt_section_state.dart';
import 'package:nai_launcher/presentation/agent_chat/services/prompt_section_toolbox.dart';
import 'package:nai_launcher/presentation/agent_chat/services/prompt_toolbox.dart';
import 'package:nai_launcher/presentation/providers/character_prompt_provider.dart';
import 'package:nai_launcher/presentation/providers/generation/generation_params_notifier.dart';
import 'package:nai_launcher/presentation/providers/prompt_group_state_provider.dart';

import '../../../helpers/memory_local_storage.dart';

final _refProvider = Provider<Ref>((ref) => ref);

const _grouped = PromptGroupSnapshot(
  groupedMode: true,
  positiveSections: [
    PromptGroupSectionSnapshot(id: 'a', text: '1girl, solo'),
    PromptGroupSectionSnapshot(id: 'b', text: 'rain', enabled: false),
    PromptGroupSectionSnapshot(id: 'c', text: 'smile'),
  ],
  negativeSections: [PromptGroupSectionSnapshot(id: 'n', text: 'lowres')],
);

class _Params extends GenerationParamsNotifier {
  _Params(this.initial);

  final ImageParams initial;

  @override
  ImageParams build() => initial;

  @override
  void updatePrompt(String prompt) => state = state.copyWith(prompt: prompt);

  @override
  void updateNegativePrompt(String prompt) =>
      state = state.copyWith(negativePrompt: prompt);
}

class _NoCharacters extends CharacterPromptNotifier {
  @override
  CharacterPromptConfig build() => const CharacterPromptConfig();
}

({ProviderContainer container, MemoryLocalStorage storage}) _setUp({
  PromptGroupSnapshot? live,
  PromptGroupSnapshot? stored,
  String? prompt,
  String? negativePrompt,
}) {
  final storage = MemoryLocalStorage();
  if (stored != null) {
    storage.values[StorageKeys.promptGroupEditorState] = jsonEncode(
      stored.toJson(),
    );
  }
  final source = live ?? stored;
  final container = ProviderContainer(
    overrides: [
      localStorageServiceProvider.overrideWithValue(storage),
      characterPromptNotifierProvider.overrideWith(_NoCharacters.new),
      generationParamsNotifierProvider.overrideWith(
        () => _Params(
          ImageParams(
            prompt: prompt ?? source?.positivePrompt ?? '',
            negativePrompt: negativePrompt ?? source?.negativePrompt ?? '',
          ),
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  if (live != null) {
    container.read(currentPromptGroupSnapshotProvider.notifier).state = live;
  }
  return (container: container, storage: storage);
}

AgentTool _tool(ProviderContainer container, String name) {
  final ref = container.read(_refProvider);
  return [
    ...PromptToolbox(ref).tools(),
    ...PromptSectionToolbox(ref).tools(),
  ].firstWhere((tool) => tool.name == name);
}

List<String> _texts(List<PromptGroupSectionSnapshot> sections) => [
  for (final section in sections) section.text,
];

void main() {
  group('PromptSectionState.read', () {
    test('prefers the live editor partitions that produce the prompt', () {
      final (:container, storage: _) = _setUp(live: _grouped);
      final state = PromptSectionState(container.read(_refProvider)).read();
      expect(state.groupedMode, isTrue);
      expect(_texts(state.positiveSections), ['1girl, solo', 'rain', 'smile']);
      expect(state.positiveSections[1].enabled, isFalse);
    });

    test('falls back to the stored state, then to one section', () {
      final (:container, storage: _) = _setUp(
        stored: _grouped,
        negativePrompt: 'blurry',
      );
      final state = PromptSectionState(container.read(_refProvider)).read();
      expect(state.groupedMode, isTrue);
      expect(_texts(state.positiveSections), ['1girl, solo', 'rain', 'smile']);
      // The negative prompt no longer matches what was stored.
      expect(state.negativeSections.single.text, 'blurry');
      expect(state.negativeSections.single.id, 'n-1');
    });
  });

  group('PromptSectionEdits', () {
    test('replaceEnabled keeps disabled sections in place', () {
      final next = PromptSectionEdits.replaceEnabled(
        _grouped.positiveSections,
        'cat',
      );
      expect(_texts(next), ['cat', 'rain']);
      expect(next.last.enabled, isFalse);
    });

    test('removing the last section leaves an empty one', () {
      final next = PromptSectionEdits.remove(
        _grouped.negativeSections,
        'n',
      );
      expect(_texts(next), ['']);
    });
  });

  group('agent tools in grouped mode', () {
    test('get_prompt_state exposes sections', () async {
      final (:container, storage: _) = _setUp(live: _grouped);
      final result = await _tool(
        container,
        'get_prompt_state',
      ).execute('read', const {});
      expect(result.details['prompt_editor_mode'], 'grouped');
      expect(result.details['positive_prompt'], '1girl, solo, smile');
      expect(result.details['positive_sections'], [
        {'id': 'a', 'text': '1girl, solo', 'enabled': true},
        {'id': 'b', 'text': 'rain', 'enabled': false},
        {'id': 'c', 'text': 'smile', 'enabled': true},
      ]);
    });

    test('append adds a section instead of merging the others', () async {
      final (:container, :storage) = _setUp(live: _grouped);
      final result = await _tool(
        container,
        'set_positive_prompt',
      ).execute('append', const {'text': 'night', 'mode': 'append'});

      expect(result.isError, isFalse);
      expect(result.details['positive_prompt'], '1girl, solo, smile, night');
      final params = container.read(generationParamsNotifierProvider);
      expect(params.prompt, '1girl, solo, smile, night');
      final request = container.read(promptGroupRestoreRequestProvider)!;
      expect(request.restorePositive, isTrue);
      expect(request.restoreNegative, isFalse);
      expect(_texts(request.snapshot.positiveSections), [
        '1girl, solo',
        'rain',
        'smile',
        'night',
      ]);
      // A page opened later restores the same partitions from storage.
      final stored = PromptGroupSnapshot.fromJson(
        jsonDecode(
          storage.values[StorageKeys.promptGroupEditorState]! as String,
        ),
      )!;
      expect(_texts(stored.positiveSections), [
        '1girl, solo',
        'rain',
        'smile',
        'night',
      ]);
      expect(
        container.read(currentPromptGroupSnapshotProvider)!.positivePrompt,
        params.prompt,
      );
    });

    test('replace swaps the enabled sections and keeps disabled ones', () async {
      final (:container, storage: _) = _setUp(live: _grouped);
      await _tool(
        container,
        'set_positive_prompt',
      ).execute('replace', const {'text': 'cat'});
      final snapshot = container.read(currentPromptGroupSnapshotProvider)!;
      expect(_texts(snapshot.positiveSections), ['cat', 'rain']);
      expect(container.read(generationParamsNotifierProvider).prompt, 'cat');
      // The other side is untouched.
      expect(_texts(snapshot.negativeSections), ['lowres']);
    });

    test('edit_prompt_sections applies all operations or none', () async {
      final (:container, storage: _) = _setUp(live: _grouped);
      final tool = _tool(container, 'edit_prompt_sections');

      final rejected = await tool.execute('bad', const {
        'prompt_type': 'positive',
        'operations': [
          {'action': 'update', 'id': 'b', 'enabled': true},
          {'action': 'move', 'id': 'missing', 'index': 0},
        ],
      });
      expect(rejected.isError, isTrue);
      expect(rejected.details['code'], 'section_not_found');
      expect(container.read(promptGroupRestoreRequestProvider), isNull);
      expect(
        container.read(generationParamsNotifierProvider).prompt,
        '1girl, solo, smile',
      );

      final applied = await tool.execute('good', const {
        'prompt_type': 'positive',
        'operations': [
          {'action': 'update', 'id': 'b', 'enabled': true},
          {'action': 'move', 'id': 'c', 'index': 0},
          {'action': 'add', 'text': 'umbrella', 'index': 1},
        ],
      });
      expect(applied.isError, isFalse);
      expect(applied.details['prompt'], 'smile, umbrella, 1girl, solo, rain');
      expect(applied.details['added_section_ids'], hasLength(1));
      expect(
        container.read(generationParamsNotifierProvider).prompt,
        'smile, umbrella, 1girl, solo, rain',
      );
    });

    test('remove_prompt_section deletes one section', () async {
      final (:container, storage: _) = _setUp(live: _grouped);
      final result = await _tool(container, 'remove_prompt_section').execute(
        'remove',
        const {'prompt_type': 'positive', 'id': 'a'},
      );
      expect(result.isError, isFalse);
      expect(result.details['prompt'], 'smile');
      expect(
        _texts(
          container.read(currentPromptGroupSnapshotProvider)!.positiveSections,
        ),
        ['rain', 'smile'],
      );
    });
  });

  group('agent tools in single mode', () {
    const single = PromptGroupSnapshot(
      groupedMode: false,
      positiveSections: [PromptGroupSectionSnapshot(id: 'a', text: 'base')],
      negativeSections: [PromptGroupSectionSnapshot(id: 'n', text: '')],
    );

    test('set_positive_prompt keeps writing plain text', () async {
      final (:container, storage: _) = _setUp(live: single);
      final result = await _tool(
        container,
        'set_positive_prompt',
      ).execute('append', const {'text': 'sky', 'mode': 'append'});
      expect(result.details['positive_prompt'], 'base, sky');
      expect(result.details.containsKey('prompt_editor_mode'), isFalse);
      expect(container.read(promptGroupRestoreRequestProvider), isNull);
    });

    test('section edits need grouped mode unless asked to enable it', () async {
      final (:container, storage: _) = _setUp(live: single);
      final tool = _tool(container, 'edit_prompt_sections');
      final refused = await tool.execute('refuse', const {
        'prompt_type': 'positive',
        'operations': [
          {'action': 'add', 'text': 'sky'},
        ],
      });
      expect(refused.details['code'], 'prompt_not_grouped');

      final enabled = await tool.execute('enable', const {
        'prompt_type': 'positive',
        'operations': [
          {'action': 'add', 'text': 'sky'},
        ],
        'enable_grouped_mode': true,
      });
      expect(enabled.isError, isFalse);
      expect(
        container.read(promptGroupRestoreRequestProvider)!.snapshot.groupedMode,
        isTrue,
      );
      expect(container.read(generationParamsNotifierProvider).prompt, 'base, sky');
    });
  });
}
