import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/models/character/character_prompt.dart';

String _lead(String prompt, CharacterGender gender) =>
    CharacterPrompt.leadingWithGender(prompt, gender);

void main() {
  test('adds the gender tag in front when the prompt has none', () {
    expect(
      _lead('hatsune miku, twintails', CharacterGender.female),
      'girl, hatsune miku, twintails',
    );
    expect(_lead('glasses', CharacterGender.male), 'boy, glasses');
    expect(_lead('', CharacterGender.female), 'girl');
  });

  test('moves a matching tag to the front instead of adding another', () {
    expect(
      _lead('hatsune miku, 1girl, smile', CharacterGender.female),
      '1girl, hatsune miku, smile',
    );
    expect(_lead('glasses, boy', CharacterGender.male), 'boy, glasses');
  });

  test('keeps a prompt that already leads with the gender', () {
    expect(
      _lead('1girl,  red eyes', CharacterGender.female),
      '1girl,  red eyes',
    );
  });

  test('rewrites a leading tag of the other gender', () {
    expect(_lead('1boy, glasses', CharacterGender.female), '1girl, glasses');
    expect(_lead('girl, glasses', CharacterGender.male), 'boy, glasses');
  });

  test('other removes a leading gender tag and adds none', () {
    expect(_lead('girl, robot', CharacterGender.other), 'robot');
    expect(_lead('robot, girl', CharacterGender.other), 'robot, girl');
  });

  test('the helper agrees with the panel gender', () {
    for (final gender in CharacterGender.values) {
      final prompt = _lead('silver hair, maid', gender);
      final character = CharacterPrompt(id: 'c', name: 'C', prompt: prompt);
      expect(character.effectiveGender, gender, reason: gender.name);
    }
  });
}
