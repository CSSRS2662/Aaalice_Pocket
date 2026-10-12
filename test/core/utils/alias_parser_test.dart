import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/utils/alias_parser.dart';

void main() {
  List<String> references(String text) =>
      AliasParser.parse(text).map((reference) => reference.rawText).toList();

  bool typing(String text) =>
      AliasParser.detectPartialAlias(text, text.length).$1;

  group('AliasParser.parse', () {
    test('finds library references, the reserved list forms included', () {
      expect(references('1girl, <我的角色>, {<outfit>}, 1.2::<pose>::'), [
        '<我的角色>',
        '<outfit>',
        '<pose>',
      ]);
      final list = AliasParser.parse('<random:cats,dogs>').single;
      expect(list.type, AliasReferenceType.random);
      expect(list.entryNames, ['cats', 'dogs']);
    });

    test('an emoticon is no reference, whatever follows it', () {
      expect(references('>_<, 1girl, :>'), isEmpty);
      expect(references(':<, smile, >:), >o<, cat, ;>'), isEmpty);
      expect(references('<o>_<o>, <|>_<|>'), isEmpty);
      expect(references('>_<, <outfit>, :>'), ['<outfit>']);
    });
  });

  group('AliasParser.detectPartialAlias', () {
    test('a name is being typed after an opening bracket', () {
      expect(AliasParser.detectPartialAlias('1girl, <my na', 13), (
        true,
        'my na',
        7,
      ));
      expect(typing('<'), isTrue);
      expect(typing('{<out'), isTrue);
      expect(typing('1.2::<out'), isTrue);
      expect(typing('她穿着<服'), isTrue);
      expect(typing('<random:cats,do'), isTrue);
      expect(typing('<outfit>, smi'), isFalse);
    });

    test('the bracket that ends an emoticon opens nothing', () {
      for (final text in [
        '>_<',
        '>_<, ',
        '>_<, smile, ',
        '>o<, smi',
        ':<',
        ':<, smile',
        ';<, ',
        '>3<, ',
        'deluxe<<<, ',
        '<3, smile',
      ]) {
        expect(typing(text), isFalse, reason: text);
      }
    });
  });
}
