import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/models/character/character_prompt.dart';
import 'package:nai_launcher/data/services/prompt_group/character_fixed_tags.dart';

Map<String, Object?> _entry({
  required String prompt,
  required List<Map<String, Object?>> sections,
  String negativePrompt = '',
  List<Map<String, Object?>> negativeSections = const [],
}) => {
  'version': 1,
  'positivePrompt': prompt,
  'negativePrompt': negativePrompt,
  'positiveSections': sections,
  'negativeSections': negativeSections,
};

void main() {
  const alice = CharacterPrompt(
    id: 'a',
    name: 'Alice',
    prompt: 'red eyes, girl, silver hair',
    negativePrompt: 'bad hands',
  );
  final aliceEntry = _entry(
    prompt: 'red eyes, girl, silver hair',
    sections: [
      {'id': 's1', 'text': 'red eyes', 'fixedTagId': 'eyes'},
      {'id': 's2', 'text': 'girl, silver hair'},
    ],
    negativePrompt: 'bad hands',
    negativeSections: [
      {'id': 'n1', 'text': 'bad hands', 'fixedTagId': 'hands'},
    ],
  );

  group('claimed', () {
    test('an included character claims its included fixed tags', () {
      final claimed = CharacterFixedTags.claimed(
        const CharacterPromptConfig(characters: [alice]),
        {'a': aliceEntry},
      );
      expect(claimed, {'eyes', 'hands'});
    });

    test('left-out characters, sections or kept tags claim nothing', () {
      final kept = _entry(
        prompt: 'red eyes, girl, silver hair',
        sections: [
          {
            'id': 's1',
            'text': 'red eyes',
            'fixedTagId': 'eyes',
            'keepInMain': true,
          },
          {'id': 's2', 'text': 'neon', 'fixedTagId': 'neon', 'enabled': false},
          {'id': 's3', 'text': 'girl, silver hair'},
        ],
      );
      expect(
        CharacterFixedTags.claimed(
          const CharacterPromptConfig(characters: [alice]),
          {'a': kept},
        ),
        isEmpty,
      );
      expect(
        CharacterFixedTags.claimed(
          CharacterPromptConfig(characters: [alice.copyWith(enabled: false)]),
          {'a': aliceEntry},
        ),
        isEmpty,
      );
    });

    test('sections that no longer add up to the prompt are ignored', () {
      expect(
        CharacterFixedTags.claimed(
          CharacterPromptConfig(
            characters: [alice.copyWith(prompt: 'boy', negativePrompt: '')],
          ),
          {'a': aliceEntry},
        ),
        isEmpty,
      );
    });
  });

  group('resolve', () {
    test('rewrites fixed-tag sections and recombines the prompt', () {
      final result = CharacterFixedTags.resolve(
        alice,
        aliceEntry,
        (id) => id == 'eyes' ? '{red eyes}, glowing eyes' : null,
      );
      expect(result, isNotNull);
      expect(
        result!.character.prompt,
        '{red eyes}, glowing eyes, girl, silver hair',
      );
      expect(result.character.negativePrompt, 'bad hands');
      expect(result.entry['positivePrompt'], result.character.prompt);
      final sections = result.entry['positiveSections']! as List;
      expect((sections.first as Map)['text'], '{red eyes}, glowing eyes');
    });

    test('a deleted tag keeps the content it had', () {
      expect(
        CharacterFixedTags.resolve(alice, aliceEntry, (_) => null),
        isNull,
      );
    });

    test('resolveAll writes the changed entries back', () {
      final entries = <String, Object?>{'a': aliceEntry};
      final next = CharacterFixedTags.resolveAll(
        const CharacterPromptConfig(characters: [alice]),
        entries,
        (id) => id == 'hands' ? 'bad hands, extra fingers' : null,
      );
      expect(
        next!.characters.single.negativePrompt,
        'bad hands, extra fingers',
      );
      expect(
        (entries['a']! as Map)['negativePrompt'],
        'bad hands, extra fingers',
      );
    });
  });
}
