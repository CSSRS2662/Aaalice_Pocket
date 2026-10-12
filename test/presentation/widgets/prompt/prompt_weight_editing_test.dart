import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/presentation/widgets/prompt/prompt_weight_editing.dart';

void main() {
  for (final newline in ['\n', '\r\n']) {
    test(
      'repeated weight steps preserve multiline content ${newline.length}',
      () {
        final body =
            'cat,${newline}blue eyes,$newline$newline'
            '1.46::upper_body, {{{{three-quarter_view}}}}::,$newline'
            '0.90::backlighting, rim_light::, soft background';
        final controller = TextEditingController(text: body)
          ..selection = TextSelection(baseOffset: 0, extentOffset: body.length);
        addTearDown(controller.dispose);

        for (final expected in [0.95, 0.90, 0.95, 1.0, 1.05, 1.10, 1.05]) {
          final current = PromptWeightEditing.parseSelection(controller).weight;
          final step = expected > current ? 0.05 : -0.05;
          expect(
            PromptWeightEditing.applyWeight(controller, current + step),
            isTrue,
          );
          expect(
            controller.text,
            expected == 1 ? body : '${expected.toStringAsFixed(2)}::$body::',
          );
          expect(
            PromptWeightEditing.parseSelection(controller).weight,
            closeTo(expected, 0.00001),
          );
          expect(PromptWeightEditing.parseSelection(controller).baseText, body);
          expect(
            controller.selection,
            TextSelection(baseOffset: 0, extentOffset: controller.text.length),
          );
        }
      },
    );
  }

  test('numeric weights support the full negative slider range', () {
    expect(PromptWeightEditing.withWeight('cat', -4), '-3.00::cat::');
    expect(PromptWeightEditing.withWeight('cat', -1.25), '-1.25::cat::');
    expect(PromptWeightEditing.withWeight('cat', 0), '0.00::cat::');
    expect(
      PromptWeightEditing.withWeight(
        'cat',
        -1.25,
        numericEmphasisEnabled: false,
      ),
      '-1.25::cat::',
    );
    expect(PromptWeightEditing.withWeight('cat', 4), '3.00::cat::');
  });

  group('enclosingWeightBlock', () {
    TextSelection? blockFor(String text, String word, {int occurrence = 0}) {
      var start = -1;
      for (var i = 0; i <= occurrence; i++) {
        start = text.indexOf(word, start + 1);
      }
      return PromptWeightEditing.enclosingWeightBlock(
        text,
        TextSelection(baseOffset: start, extentOffset: start + word.length),
      );
    }

    String? selected(String text, TextSelection? selection) =>
        selection?.textInside(text);

    test('widens a word to its whole block without the separator', () {
      const text = 'smile, 1.40::smile::, blush';
      expect(
        selected(text, blockFor(text, 'smile', occurrence: 1)),
        '1.40::smile::',
      );
      expect(selected(text, blockFor(text, '1.40')), '1.40::smile::');
    });

    test('a word in a weighted group selects the whole group', () {
      const text = 'cat, 1.2::smile, blush::';
      expect(selected(text, blockFor(text, 'blush')), '1.2::smile, blush::');
    });

    test('numeric weights do not nest, so a reset stays one block', () {
      // NAI closes the block at the first `::`; `1.5::` only resets weight.
      const text = '1.2::1.5::smile::, blush';
      expect(selected(text, blockFor(text, 'smile')), '1.2::1.5::smile::');
    });

    test('leaves plain tags and complete blocks alone', () {
      const text = 'smile, 1.40::smile::, blush';
      expect(blockFor(text, 'blush'), isNull);
      expect(blockFor(text, 'smile'), isNull);
      expect(blockFor(text, '1.40::smile::'), isNull);
      expect(
        PromptWeightEditing.enclosingWeightBlock(
          text,
          const TextSelection.collapsed(offset: 14),
        ),
        isNull,
      );
    });
  });

  group('doubleTapSelection', () {
    // The platform's double tap selects [word]; what it becomes.
    String? widened(String text, String word) {
      final start = text.indexOf(word);
      final selection = PromptWeightEditing.doubleTapSelection(
        text,
        TextSelection(baseOffset: start, extentOffset: start + word.length),
      );
      return selection?.textInside(text);
    }

    test('one Chinese character becomes its whole tag', () {
      const text = 'thin_thighs, 微笑的女孩, 淡绿色t恤';
      expect(widened(text, '笑'), '微笑的女孩');
      expect(widened(text, '恤'), '淡绿色t恤');
    });

    test('one word of a spaced tag becomes the whole tag', () {
      const text = 'masterpiece, long hair, looking at viewer';
      expect(widened(text, 'hair'), 'long hair');
      expect(widened(text, 'at'), 'looking at viewer');
    });

    test('a tag already selected whole is left alone', () {
      const text = 'masterpiece, long_hair, 微笑';
      expect(widened(text, 'long_hair'), isNull);
      expect(widened(text, '微笑'), isNull);
    });

    test('takes the weight brackets of the tag along', () {
      const text = 'cat, {{long hair}}, [微笑], /*disabled:blue eyes*/';
      expect(widened(text, 'hair'), '{{long hair}}');
      expect(widened(text, '笑'), '[微笑]');
      expect(widened(text, 'eyes'), '/*disabled:blue eyes*/');
    });

    test('inside a group it is the one tag, in a weight block the block', () {
      const group = '{shiny skin, shiny, 白色 连衣裙}, cat';
      expect(widened(group, 'skin'), 'shiny skin');
      expect(widened(group, '连衣裙'), '白色 连衣裙');
      const block = 'cat, 1.2::long hair, 微笑::';
      expect(widened(block, '微'), '1.2::long hair, 微笑::');
      expect(widened('cat, 1.40::long hair::', 'hair'), '1.40::long hair::');
    });

    test('emoticons with angle brackets are tags of their own', () {
      const text = '>_<, 微笑 的, :>';
      expect(widened(text, '的'), '微笑 的');
      expect(widened(text, '_'), '>_<');
    });

    test('unfinished syntax and the gaps between tags keep the word', () {
      expect(widened('cat, {long hair', 'hair'), isNull);
      expect(widened('cat ,  dog', ' '), isNull);
      expect(
        PromptWeightEditing.doubleTapSelection(
          'long hair',
          const TextSelection.collapsed(offset: 2),
        ),
        isNull,
      );
    });
  });
}
