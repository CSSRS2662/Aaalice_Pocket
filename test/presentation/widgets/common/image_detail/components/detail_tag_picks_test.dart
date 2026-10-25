import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/presentation/widgets/common/image_detail/components/detail_tag_picks.dart';

void main() {
  test('picks copy in prompt order, not in the order picked', () {
    final picks = DetailTagPicks();
    addTearDown(picks.dispose);

    picks.toggle(DetailTagSide.positive, 2, 'smile');
    picks.toggle(DetailTagSide.positive, 0, '1girl');
    expect(picks.active, isTrue);
    expect(picks.count, 2);
    expect(picks.text, '1girl, smile');

    // Dropping the last pick keeps picking on.
    picks
      ..toggle(DetailTagSide.positive, 2, 'smile')
      ..toggle(DetailTagSide.positive, 0, '1girl');
    expect(picks.active, isTrue);
    expect(picks.count, 0);
    expect(picks.text, isEmpty);
  });

  test('select all of a side can be undone one tag at a time', () {
    final picks = DetailTagPicks();
    addTearDown(picks.dispose);

    picks.setAll(DetailTagSide.negative, const [
      'lowres',
      'bad hands',
    ], picked: true);
    expect(picks.countOf(DetailTagSide.negative), 2);
    picks.toggle(DetailTagSide.negative, 0, 'lowres');
    expect(picks.isPicked(DetailTagSide.negative, 0), isFalse);
    expect(picks.text, 'bad hands');

    picks.end();
    expect(picks.active, isFalse);
    expect(picks.count, 0);
  });

  test('picks of both prompts use the two-line form', () {
    expect(
      formatPickedTags(positive: const ['1girl', 'smile'], negative: const []),
      '1girl, smile',
    );
    expect(
      formatPickedTags(positive: const [], negative: const ['lowres']),
      'lowres',
    );
    expect(
      formatPickedTags(positive: const ['1girl'], negative: const ['lowres']),
      'positive: 1girl\nnegative: lowres',
    );
  });
}
