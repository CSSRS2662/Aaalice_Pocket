import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/models/character/character_prompt.dart';
import 'package:nai_launcher/presentation/widgets/character/character_marker.dart';

CharacterPrompt _character(String id, String prompt) =>
    CharacterPrompt(id: id, name: id, prompt: prompt);

void main() {
  group('CharacterGenderGlyphPainter', () {
    for (final gender in CharacterGender.values) {
      test('${gender.name} symbol ink is centred in its box', () {
        final bounds = CharacterGenderGlyphPainter.inkBounds(gender);
        expect(bounds.center.dx, closeTo(12, 0.01));
        expect(bounds.center.dy, closeTo(12, 0.01));
        expect(bounds.width, lessThanOrEqualTo(24));
        expect(bounds.height, lessThanOrEqualTo(24));
      });
    }
  });

  group('CharacterMarkerPalette', () {
    test('same gender gets distinct shades of one family', () {
      final characters = [
        _character('a', 'girl, red hair'),
        _character('b', 'boy'),
        _character('c', '1girl, cat ears'),
        _character('d', 'robot'),
      ];
      final a = CharacterMarkerPalette.of(characters, characters[0]);
      final b = CharacterMarkerPalette.of(characters, characters[1]);
      final c = CharacterMarkerPalette.of(characters, characters[2]);
      final d = CharacterMarkerPalette.of(characters, characters[3]);

      expect(a.gender, CharacterGender.female);
      expect(c.gender, CharacterGender.female);
      expect(a.fill, isNot(c.fill));
      expect(a.fill, CharacterMarkerPalette.shade(CharacterGender.female, 0));
      expect(c.fill, CharacterMarkerPalette.shade(CharacterGender.female, 1));
      expect(b.fill, CharacterMarkerPalette.base(CharacterGender.male));
      expect(d.fill, CharacterMarkerPalette.base(CharacterGender.other));
    });

    test('light shades carry a dark symbol', () {
      expect(CharacterMarkerPalette.inkFor(0), Colors.white);
      expect(CharacterMarkerPalette.inkFor(3), CharacterMarkerPalette.darkInk);
      expect(CharacterMarkerPalette.inkFor(5), CharacterMarkerPalette.darkInk);
    });
  });

  group('CharacterPositionMiniMap', () {
    test('frame takes the aspect ratio of the generation', () {
      expect(
        CharacterPositionMiniMap.frameSize(832 / 1216, 40).aspectRatio,
        closeTo(832 / 1216, 0.001),
      );
      expect(CharacterPositionMiniMap.frameSize(16 / 9, 40).width, 40);
    });

    test('dot stays inside the frame at the edges', () {
      for (final ratio in [832 / 1216, 1.0, 1920 / 1088]) {
        final frame = CharacterPositionMiniMap.frameSize(ratio, 40);
        for (final position in const [
          Offset.zero,
          Offset(1, 1),
          Offset(0, 1),
        ]) {
          final center = CharacterPositionMiniMap.dotCenter(frame, position, 8);
          expect(center.dx - 4, greaterThanOrEqualTo(1));
          expect(center.dy - 4, greaterThanOrEqualTo(1));
          expect(center.dx + 4, lessThanOrEqualTo(frame.width - 1));
          expect(center.dy + 4, lessThanOrEqualTo(frame.height - 1));
        }
      }
    });
  });

  group('CharacterPrompt.withGender', () {
    test('replaces the leading gender tag and keeps the rest', () {
      final girl = _character('a', '1girl, red hair, smile');
      expect(
        girl.withGender(CharacterGender.male).prompt,
        '1boy, red hair, smile',
      );
      expect(girl.withGender(CharacterGender.other).prompt, 'red hair, smile');
      expect(
        _character('b', 'cat, tail').withGender(CharacterGender.female).prompt,
        'girl, cat, tail',
      );
      expect(
        _character('c', '').withGender(CharacterGender.male).prompt,
        'boy, ',
      );
    });

    test('leaves a matching prompt alone', () {
      final boy = _character('a', 'boy');
      final same = boy.withGender(CharacterGender.male);
      expect(same.prompt, 'boy');
      expect(same.gender, CharacterGender.male);
      expect(same.effectiveGender, CharacterGender.male);
    });
  });
}
