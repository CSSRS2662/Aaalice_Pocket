import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/utils/text_diff.dart';

TextDiffSegment _same(String text) => TextDiffSegment(TextDiffKind.same, text);
TextDiffSegment _added(String text) =>
    TextDiffSegment(TextDiffKind.added, text);
TextDiffSegment _removed(String text) =>
    TextDiffSegment(TextDiffKind.removed, text);

void main() {
  test('marks a replaced tag as a whole', () {
    expect(diffText('blue eyes, smile, solo', 'blue eyes, grin, solo'), [
      _same('blue eyes, '),
      _removed('smile'),
      _added('grin'),
      _same(', solo'),
    ]);
  });

  test('marks added and removed tags', () {
    expect(diffText('1girl, smile', '1girl, smile, long hair'), [
      _same('1girl, smile'),
      _added(', long hair'),
    ]);
    expect(diffText('1girl, hat, smile', '1girl, smile'), [
      _same('1girl, '),
      _removed('hat, '),
      _same('smile'),
    ]);
  });

  test('splits Chinese by character', () {
    expect(diffText('白色帽子', '黑色帽子'), [
      _removed('白'),
      _added('黑'),
      _same('色帽子'),
    ]);
  });

  test('handles empty and equal text', () {
    expect(diffText('', ''), isEmpty);
    expect(diffText('same', 'same'), [_same('same')]);
    expect(diffText('', 'new'), [_added('new')]);
    expect(diffText('old', ''), [_removed('old')]);
  });

  test('every segment rebuilds both texts', () {
    const before = '{{masterpiece}}, 1girl, 1.2::blue hair::, smile';
    const after = 'masterpiece, 1girl, 1.3::blue hair::, grin, sky';
    final segments = diffText(before, after);
    expect(
      segments
          .where((s) => s.kind != TextDiffKind.added)
          .map((s) => s.text)
          .join(),
      before,
    );
    expect(
      segments
          .where((s) => s.kind != TextDiffKind.removed)
          .map((s) => s.text)
          .join(),
      after,
    );
  });
}
