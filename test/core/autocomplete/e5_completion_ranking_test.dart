import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/autocomplete/completion_models.dart';
import 'package:nai_launcher/core/autocomplete/completion_ranker.dart';

void main() {
  const query = CompletionQuery(
    fullText: '不穿袜子',
    cursorPosition: 4,
    token: '不穿袜子',
    replacementRange: TextReplacementRange(start: 0, end: 4),
    existingTags: {'already_used'},
    limit: 20,
    locale: 'zh-CN',
  );
  CompletionCandidate candidate(String tag, double similarity, int count) =>
      CompletionCandidate(
        canonicalTag: tag,
        category: TagCategory.general,
        postCount: count,
        matchKind: CompletionMatchKind.fullText,
        sources: const {CompletionSourceKind.base},
        semanticScore: similarity,
      );

  test('cosine ordering survives merge without popularity overriding it', () {
    final rows = CompletionRanker.mergeAndSort([
      candidate('no_socks', .91, 20),
      candidate('socks', .85, 9000000),
      candidate('already_used', .99, 1),
      const CompletionCandidate(
        canonicalTag: 'no_socks',
        category: TagCategory.general,
        postCount: 20,
        matchKind: CompletionMatchKind.fullText,
        sources: {CompletionSourceKind.zhDictionary},
        translation: '未穿袜',
      ),
    ], query: query);
    // A written tag found by meaning keeps its cosine place.
    expect(rows.map((row) => row.canonicalTag), [
      'already_used',
      'no_socks',
      'socks',
    ]);
    expect(rows.first.isExisting, isTrue);
    expect(rows[1].semanticScore, .91);
    expect(rows[1].translation, '未穿袜');
    final mergedAgain = CompletionRanker.mergeAndSort(rows, query: query);
    expect(
      mergedAgain.map((row) => row.canonicalTag),
      rows.map((row) => row.canonicalTag),
    );
  });

  test('exact Chinese dictionary match stays ahead of semantic guesses', () {
    final rows = CompletionRanker.mergeAndSort([
      candidate('guess', .99, 9000000),
      const CompletionCandidate(
        canonicalTag: 'exact',
        category: TagCategory.general,
        postCount: 1,
        matchKind: CompletionMatchKind.chineseExact,
        sources: {CompletionSourceKind.zhDictionary},
      ),
    ], query: query);
    expect(rows.first.canonicalTag, 'exact');
  });

  test('explicit contrasts correct ambiguous cosine ordering', () {
    for (final (text, wanted, opposite) in const [
      ('嘴巴没有张开', 'closed_mouth', 'open_mouth'),
      ('两只眼睛都闭着', 'closed_eyes', 'one_eye_closed'),
      ('举起右手', 'right_hand_up', 'left_hand_up'),
      ('在水面下方', 'under_water', 'above_water'),
      ('跪在地板上', 'kneeling_on_floor', 'standing_on_floor'),
      ('别把衣角塞进腰里', 'untucked_shirt', 'shirt_tucked_in'),
      ('别把头发剪成短发', 'long_hair', 'short_hair'),
      ('视线避开镜头', 'looking_away', 'looking_at_viewer'),
      ('不要只画一个人', 'two_people', 'solo'),
    ]) {
      final rows = CompletionRanker.mergeAndSort([
        candidate(opposite, .94, 200000),
        candidate(wanted, .89, 100),
      ], query: query.copyWith(token: text));
      expect(rows.first.canonicalTag, wanted, reason: text);
    }
  });
}
