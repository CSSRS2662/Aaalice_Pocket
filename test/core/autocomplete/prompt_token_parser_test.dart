import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/autocomplete/completion_models.dart';
import 'package:nai_launcher/core/autocomplete/prompt_token_parser.dart';

void main() {
  group('PromptTokenParser.parse', () {
    test('extracts the token under a cursor in the middle', () {
      final query = PromptTokenParser.parse(
        text: 'masterpiece, long hair, blue eyes',
        cursorPosition: 20,
        limit: 20,
        locale: 'en',
      );

      expect(query.token, 'long_hair');
      expect(
        query.fullText.substring(
          query.replacementRange.start,
          query.replacementRange.end,
        ),
        'long hair',
      );
      expect(query.existingTags, containsAll(['masterpiece', 'blue_eyes']));
    });

    test('preserves NovelAI braces and numeric weight suffixes', () {
      final braced = PromptTokenParser.parse(
        text: '{{long hair}}',
        cursorPosition: 7,
        limit: 20,
        locale: 'en',
      );
      final weighted = PromptTokenParser.parse(
        text: '(long hair:1.25)',
        cursorPosition: 6,
        limit: 20,
        locale: 'en',
      );

      expect(braced.token, 'long_hair');
      expect(weighted.token, 'long_hair');
      expect(
        PromptTokenParser.apply(
          text: braced.fullText,
          query: braced,
          canonicalTag: 'very_long_hair',
          autoInsertComma: true,
          replaceUnderscores: false,
        ).text,
        '{{very_long_hair}}, ',
      );
      expect(
        PromptTokenParser.apply(
          text: weighted.fullText,
          query: weighted,
          canonicalTag: 'very_long_hair',
          autoInsertComma: true,
          replaceUnderscores: false,
        ).text,
        '(very_long_hair:1.25), ',
      );
    });

    test('supports space-separated tag search when explicitly enabled', () {
      final query = PromptTokenParser.parse(
        text: 'foot_focus lo',
        cursorPosition: 13,
        limit: 20,
        locale: 'en',
        splitOnSpaces: true,
      );

      expect(query.token, 'lo');
      expect(query.existingTags, contains('foot_focus'));
      expect(query.replacementRange.start, 11);
    });

    test('treats artist colon as an artist-category prefix', () {
      final categoryQuery = PromptTokenParser.parse(
        text: 'masterpiece, artist:',
        cursorPosition: 'masterpiece, artist:'.length,
        limit: 20,
        locale: 'en',
      );
      final nameQuery = PromptTokenParser.parse(
        text: 'artist:john doe',
        cursorPosition: 'artist:john doe'.length,
        limit: 20,
        locale: 'en',
      );

      expect(categoryQuery.token, isEmpty);
      expect(categoryQuery.categoryFilter, TagCategory.artist);
      expect(
        categoryQuery.replacementRange.start,
        'masterpiece, artist:'.length,
      );
      expect(nameQuery.token, 'john_doe');
      expect(nameQuery.categoryFilter, TagCategory.artist);

      final result = PromptTokenParser.apply(
        text: nameQuery.fullText,
        query: nameQuery,
        canonicalTag: 'john_singer_sargent',
        autoInsertComma: true,
        replaceUnderscores: false,
      );
      expect(result.text, 'artist:john_singer_sargent, ');
    });

    test('supports Chinese input and requires explicit related-tag mode', () {
      final chinese = PromptTokenParser.parse(
        text: '杰作, 蓝色眼睛',
        cursorPosition: 8,
        limit: 20,
        locale: 'zh-CN',
      );
      final normal = PromptTokenParser.parse(
        text: 'blue_eyes,',
        cursorPosition: 10,
        limit: 20,
        locale: 'en',
      );
      final related = PromptTokenParser.parseRelated(
        text: 'blue_eyes,',
        cursorPosition: 10,
        limit: 20,
        locale: 'en',
      );

      expect(chinese.token, '蓝色眼睛');
      expect(chinese.isChinese, isTrue);
      expect(normal.token, isEmpty);
      expect(normal.relatedTag, isNull);
      expect(related?.relatedTag, 'blue_eyes');
    });

    test('detects and applies a tag library alias completion', () {
      final query = PromptTokenParser.parse(
        text: 'masterpiece, <角色',
        cursorPosition: 'masterpiece, <角色'.length,
        limit: 20,
        locale: 'zh-CN',
      );

      expect(query.kind, CompletionQueryKind.libraryAlias);
      expect(query.token, '角色');
      expect(
        query.fullText.substring(
          query.replacementRange.start,
          query.replacementRange.end,
        ),
        '<角色',
      );

      final result = PromptTokenParser.apply(
        text: query.fullText,
        query: query,
        canonicalTag: '角色立绘',
        autoInsertComma: true,
        replaceUnderscores: true,
      );
      expect(result.text, 'masterpiece, <角色立绘>, ');
      expect(result.cursorPosition, result.text.length);
    });

    test('replaces the closing bracket when completing inside an alias', () {
      final query = PromptTokenParser.parse(
        text: '<character preset>',
        cursorPosition: 5,
        limit: 20,
        locale: 'en',
      );
      final result = PromptTokenParser.apply(
        text: query.fullText,
        query: query,
        canonicalTag: 'character sheet',
        autoInsertComma: false,
        replaceUnderscores: false,
      );

      expect(query.kind, CompletionQueryKind.libraryAlias);
      expect(result.text, '<character sheet>');
    });

    test('does not duplicate an existing comma', () {
      final query = PromptTokenParser.parse(
        text: '{{long hair}}, next_tag',
        cursorPosition: 7,
        limit: 20,
        locale: 'en',
      );
      final result = PromptTokenParser.apply(
        text: query.fullText,
        query: query,
        canonicalTag: 'very_long_hair',
        autoInsertComma: true,
        replaceUnderscores: true,
      );

      expect(result.text, '{{very long hair}}, next_tag');
      expect(result.cursorPosition, '{{very long hair}}, '.length);
    });

    test(
      'creates a related insertion query without replacing weighted syntax',
      () {
        final query = PromptTokenParser.parseRelated(
          text: '{{blue_archive:1.2}}, solo',
          cursorPosition: 8,
          limit: 20,
          locale: 'en',
        );

        expect(query, isNotNull);
        expect(query!.relatedTag, 'blue_archive');
        expect(query.token, isEmpty);
        expect(query.replacementRange.start, '{{blue_archive:1.2}}, '.length);
        final result = PromptTokenParser.apply(
          text: query.fullText,
          query: query,
          canonicalTag: 'halo',
          autoInsertComma: true,
          replaceUnderscores: false,
        );
        expect(result.text, '{{blue_archive:1.2}}, halo, solo');
      },
    );

    test(
      'separates related insertion even when automatic trailing comma is off',
      () {
        final query = PromptTokenParser.parseRelated(
          text: 'blue_archive',
          cursorPosition: 5,
          limit: 20,
          locale: 'en',
        )!;
        final result = PromptTokenParser.apply(
          text: query.fullText,
          query: query,
          canonicalTag: 'halo',
          autoInsertComma: false,
          replaceUnderscores: false,
        );

        expect(result.text, 'blue_archive, halo');
        expect(result.cursorPosition, result.text.length);
      },
    );

    test('queries and replaces tags inside a character negative block', () {
      const text = 'girl, negative(red ha, glasses)';
      final query = PromptTokenParser.parse(
        text: text,
        cursorPosition: text.indexOf('red ha') + 'red ha'.length,
        limit: 20,
        locale: 'en',
      );

      expect(query.token, 'red_ha');
      expect(query.existingTags, containsAll(['girl', 'glasses']));
      expect(query.existingTags, isNot(contains('negative(red_ha')));

      final result = PromptTokenParser.apply(
        text: text,
        query: query,
        canonicalTag: 'red_hair',
        autoInsertComma: true,
        replaceUnderscores: false,
      );
      expect(result.text, 'girl, negative(red_hair, glasses)');
    });

    test('inserts related tags before the negative block closing boundary', () {
      const text = 'girl, negative(red hair)';
      final query = PromptTokenParser.parseRelated(
        text: text,
        cursorPosition: text.indexOf('red hair') + 3,
        limit: 20,
        locale: 'en',
      )!;

      final result = PromptTokenParser.apply(
        text: text,
        query: query,
        canonicalTag: 'glasses',
        autoInsertComma: false,
        replaceUnderscores: true,
      );
      expect(result.text, 'girl, negative(red hair, glasses)');
    });

    test('does not query the reserved keyword or its boundaries', () {
      const text = 'girl, negative(red hair)';
      final query = PromptTokenParser.parse(
        text: text,
        cursorPosition: text.indexOf('negative') + 3,
        limit: 20,
        locale: 'en',
      );

      expect(query.token, isEmpty);
      expect(query.replacementRange.start, text.indexOf('negative') + 3);
      expect(query.existingTags, containsAll(['girl', 'red_hair']));
    });
  });

  group('PromptTokenParser.editChangesActiveToken', () {
    bool changes(
      String before,
      int beforeCursor,
      String after,
      int afterCursor, {
      bool splitOnSpaces = false,
    }) => PromptTokenParser.editChangesActiveToken(
      previousText: before,
      previousCursorPosition: beforeCursor,
      currentText: after,
      currentCursorPosition: afterCursor,
      splitOnSpaces: splitOnSpaces,
    );

    test('ignores structural edits around an untouched tag', () {
      expect(changes('solo_focus', 0, '\nsolo_focus', 1), isFalse);
      expect(changes('first\nsolo_focus', 6, 'firstsolo_focus', 5), isFalse);
      expect(changes('first, solo_focus', 7, 'first,solo_focus', 6), isFalse);
      expect(changes('first,solo_focus', 6, 'firstsolo_focus', 5), isFalse);
      expect(changes('{solo_focus}', 1, 'solo_focus}', 0), isFalse);
      expect(changes('solo_focus, next', 10, ', next', 0), isFalse);
    });

    test('detects inserted, deleted, replaced, and pasted tag text', () {
      expect(changes('solo_focus', 4, 'sol_focus', 3), isTrue);
      expect(changes('solo_focus', 0, 'olo_focus', 0), isTrue);
      expect(changes('solo_focus', 4, 'solX_focus', 4), isTrue);
      expect(changes('', 0, 'solo_focus', 10), isTrue);
      expect(changes('', 0, '<角色', 3), isTrue);
      expect(changes('artist', 6, 'artist:', 7), isTrue);
    });

    test('treats spaces according to the field separator policy', () {
      expect(changes('blueeyes', 4, 'blue eyes', 5), isTrue);
      expect(
        changes('first solo', 6, 'firstsolo', 5, splitOnSpaces: true),
        isFalse,
      );
    });
  });

  group('PromptTokenParser context', () {
    test('lists written tags nearest first, without weights or disabled', () {
      const text =
          'school_uniform, 1.2::classroom::, {smile}, /*disabled:night*/, '
          'desk, , window';
      final cursor = text.indexOf('desk, ') + 'desk, '.length;
      expect(
        PromptTokenParser.contextTags(text: text, cursorPosition: cursor),
        ['desk', 'smile', 'classroom', 'school_uniform', 'window'],
      );
      expect(
        PromptTokenParser.contextTags(
          text: text,
          cursorPosition: cursor,
          max: 2,
        ),
        ['desk', 'smile'],
      );
    });

    test('an empty slot after tags continues from them', () {
      const text = 'beach, bikini, ';
      expect(
        PromptTokenParser.isContinuationSlot(
          text: text,
          cursorPosition: text.length,
        ),
        isTrue,
      );
      expect(
        PromptTokenParser.isContinuationSlot(text: 'beach', cursorPosition: 5),
        isFalse,
      );
      expect(
        PromptTokenParser.isContinuationSlot(text: '', cursorPosition: 0),
        isFalse,
      );

      final query = PromptTokenParser.parseRelated(
        text: text,
        cursorPosition: text.length,
        limit: 20,
        locale: 'en',
      )!;
      expect(query.relatedTag, 'bikini');
      expect(query.contextTags, ['beach']);
      expect(query.token, isEmpty);
    });

    test('a related tag under the caret carries the tags around it', () {
      const text = 'night, outdoors, smile, sky';
      final query = PromptTokenParser.parseRelated(
        text: text,
        cursorPosition: text.indexOf('smile') + 2,
        limit: 20,
        locale: 'en',
      )!;
      expect(query.relatedTag, 'smile');
      expect(query.contextTags, ['outdoors', 'night', 'sky']);
    });
  });

  group('tags with symbols of their own', () {
    CompletionQuery at(String text, [int? cursor]) => PromptTokenParser.parse(
      text: text,
      cursorPosition: cursor ?? text.length,
      limit: 20,
      locale: 'en',
    );
    String covered(CompletionQuery query) => query.fullText.substring(
      query.replacementRange.start,
      query.replacementRange.end,
    );
    String? relatedAfter(String text) => PromptTokenParser.parseRelated(
      text: text,
      cursorPosition: text.length,
      limit: 20,
      locale: 'en',
    )?.relatedTag;

    test('a qualifier in round brackets is part of the tag', () {
      final query = at('1girl, tippy_(gochiusa)');
      expect(query.token, 'tippy_(gochiusa)');
      expect(covered(query), 'tippy_(gochiusa)');
      expect(
        at('tippy_(gochiusa), sensei_(blue_archive), blu').existingTags,
        containsAll(['tippy_(gochiusa)', 'sensei_(blue_archive)']),
      );
      expect(
        relatedAfter('1girl, sensei_(blue_archive), '),
        'sensei_(blue_archive)',
      );
      const written = 'tippy_(gochiusa), smile, ';
      expect(
        PromptTokenParser.contextTags(
          text: written,
          cursorPosition: written.length,
        ),
        ['smile', 'tippy_(gochiusa)'],
      );
    });

    test('brackets around a tag are still weight syntax', () {
      for (final (text, tag, range) in [
        ('{{tippy_(gochiusa)}}', 'tippy_(gochiusa)', 'tippy_(gochiusa)'),
        ('[tippy_(gochiusa)]', 'tippy_(gochiusa)', 'tippy_(gochiusa)'),
        ('1.20::tippy_(gochiusa)::', 'tippy_(gochiusa)', 'tippy_(gochiusa)'),
        ('(tippy_(gochiusa):1.2)', 'tippy_(gochiusa)', 'tippy_(gochiusa)'),
        ('((long hair))', 'long_hair', 'long hair'),
        ('.5::long hair::', 'long_hair', 'long hair'),
        ('(o)_(o)', '(o)_(o)', '(o)_(o)'),
        ('00_qan[t]', '00_qan[t]', '00_qan[t]'),
      ]) {
        final query = at('1girl, $text, smile', 7 + text.length ~/ 2);
        expect(query.token, tag, reason: text);
        expect(covered(query), range, reason: text);
        expect(at('$text, blu').existingTags, contains(tag), reason: text);
      }
    });

    test('an SD group keeps its brackets out of its tags', () {
      const text = '(long hair, tippy_(gochiusa):1.2), smile';
      expect(at(text, 5).token, 'long_hair');
      expect(at(text, 20).token, 'tippy_(gochiusa)');
      expect(
        at('$text, blu').existingTags,
        containsAll(['long_hair', 'tippy_(gochiusa)', 'smile']),
      );
    });

    test('emoticons keep their colons and brackets', () {
      for (final tag in [
        ':3',
        '>_<',
        ':<',
        ';)',
        '>:)',
        '>:(',
        '^_^',
        '|_|',
        r'\m/',
        '!?',
        '?',
      ]) {
        final text = '1girl, $tag';
        expect(at(text).kind, CompletionQueryKind.tag, reason: tag);
        expect(at(text).token, tag, reason: tag);
        expect(relatedAfter('$text, '), tag, reason: tag);
        expect(
          PromptTokenParser.isContinuationSlot(
            text: '$text, ',
            cursorPosition: text.length + 2,
          ),
          isTrue,
          reason: tag,
        );
        expect(at('$tag, blu').existingTags, contains(tag), reason: tag);
      }
    });

    test('a name ending in a colon and a number is not a weight', () {
      expect(at('vertin_(reverse:1999)').token, 'vertin_(reverse:1999)');
      expect(at('reverse:1999').token, 'reverse:1999');
      expect(at('(reverse:1999)', 4).token, 'reverse:1999');
      expect(at('(long hair:1.25)', 6).token, 'long_hair');
    });

    test('completing inside a numeric weight keeps the weight', () {
      const text = '1.20::long ha::, smile';
      final query = at(text, text.indexOf('::,'));
      expect(query.token, 'long_ha');
      final applied = PromptTokenParser.apply(
        text: text,
        query: query,
        canonicalTag: 'long_hair',
        autoInsertComma: true,
        replaceUnderscores: false,
      );
      expect(applied.text, '1.20::long_hair::, smile');
    });

    test('completing a bracketed tag again does not double its bracket', () {
      const text = 'tippy_(gochiusa), smile';
      final applied = PromptTokenParser.apply(
        text: text,
        query: at(text, 9),
        canonicalTag: 'tippy_(gochiusa)',
        autoInsertComma: true,
        replaceUnderscores: false,
      );
      expect(applied.text, text);
    });

    test('an emoticon keeps its underscore where tags take spaces', () {
      String inserted(String tag) => PromptTokenParser.apply(
        text: 'x',
        query: at('x'),
        canonicalTag: tag,
        autoInsertComma: false,
        replaceUnderscores: true,
      ).text;
      for (final face in ['>_<', '^_^', 'o_o', '<o>_<o>', '(o)_(o)', '+_-']) {
        expect(inserted(face), face);
      }
      expect(inserted('long_hair'), 'long hair');
      expect(inserted('tippy_(gochiusa)'), 'tippy (gochiusa)');
    });

    test('a library name is still completed after <', () {
      expect(at('1girl, <my').kind, CompletionQueryKind.libraryAlias);
      expect(at('1.2::<my').kind, CompletionQueryKind.libraryAlias);
      expect(at('<random:cats,do').kind, CompletionQueryKind.libraryAlias);
      // A separator ends whatever the bracket began.
      expect(at('<3, smile').kind, CompletionQueryKind.tag);
      expect(at('<3, smile').token, 'smile');
    });
  });
}
