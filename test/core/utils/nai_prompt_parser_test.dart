import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/utils/nai_prompt_parser.dart';
import 'package:nai_launcher/data/models/prompt/prompt_tag.dart';

void main() {
  group('NaiPromptParser.splitSegments', () {
    test('keeps nested weighted syntax in one segment', () {
      expect(NaiPromptParser.splitSegments('{a, [b, (c, d)]}, tail'), [
        '{a, [b, (c, d)]}',
        'tail',
      ]);
    });

    test('handles unmatched delimiters without corrupting later depth', () {
      expect(NaiPromptParser.splitSegments('a}, b], c), d'), [
        'a}',
        'b]',
        'c)',
        'd',
      ]);
      expect(NaiPromptParser.splitSegments('{a, b, c'), ['{a, b, c']);
    });

    test('protects commas inside paired double pipes', () {
      expect(NaiPromptParser.splitSegments('||a, b||, c'), ['||a, b||', 'c']);
      expect(NaiPromptParser.splitSegments(r'\|\|a,b, c'), [
        r'\|\|a',
        'b',
        'c',
      ]);
    });

    test('escaped syntax characters do not split or change depth', () {
      expect(
        NaiPromptParser.splitSegments(
          r'a\,b, \{c\,d\}, \[e\,f\], \(g\,h\), i\|j',
        ),
        [r'a\,b', r'\{c\,d\}', r'\[e\,f\]', r'\(g\,h\)', r'i\|j'],
      );
    });

    test('continuous backslashes use odd-even escaping semantics', () {
      expect(NaiPromptParser.splitSegments(r'a\\,b'), [r'a\\', 'b']);
      expect(NaiPromptParser.splitSegments(r'a\\\,b, c'), [r'a\\\,b', 'c']);
    });
  });

  group('NaiPromptParser.containsFragment', () {
    test('matches complete consecutive fragments', () {
      expect(
        NaiPromptParser.containsFragment(
          'head, {{{masterpiece, best quality}}}, tail',
          '{{{masterpiece, best quality}}}',
        ),
        isTrue,
      );
      expect(
        NaiPromptParser.containsFragment('head, blue eyes, tail', 'blue eyes'),
        isTrue,
      );
    });

    test('does not match substrings or non-consecutive fragments', () {
      expect(
        NaiPromptParser.containsFragment('masterpiece portrait', 'masterpiece'),
        isFalse,
      );
      expect(NaiPromptParser.containsFragment('a, middle, b', 'a, b'), isFalse);
    });
  });

  group('weights', () {
    test('negative weights parse and round-trip as numeric syntax', () {
      final tags = NaiPromptParser.parse('1.3::red hair::, -1::hat::, -3::x::');

      expect([for (final tag in tags) tag.weight], [1.3, -1.0, -3.0]);
      expect(
        NaiPromptParser.toPromptString(tags),
        '1.3::red hair::, -1::hat::, -3::x::',
      );
    });

    test('a weight below zero is written numerically even from brackets', () {
      final tag = NaiPromptParser.parse('[hat]').single;

      expect(tag.copyWith(weight: -0.5).toSyntaxString(), '-0.5::hat::');
      expect(tag.toSyntaxString(), '[hat]');
    });

    test('stacked brackets keep a positive floor', () {
      final tag = NaiPromptParser.parse('${'[' * 30}hat${']' * 30}').single;

      expect(tag.weight, PromptTag.minBracketWeight);
    });
  });
}
