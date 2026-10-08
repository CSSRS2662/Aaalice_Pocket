import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/autocomplete/completion_models.dart';
import 'package:nai_launcher/core/autocomplete/related_tag_scorer.dart';
import 'package:nai_launcher/core/autocomplete/tag_catalog_repository.dart';

TagCatalogRecord _record(
  String tag,
  int postCount, [
  TagCategory category = TagCategory.general,
]) => TagCatalogRecord(
  canonicalTag: tag,
  category: category,
  postCount: postCount,
);

RelatedContextTag _context(
  TagCatalogRecord record,
  Map<String, int> related, {
  bool complete = true,
  int distance = 0,
}) => RelatedContextTag(
  record: record,
  weight: RelatedTagScorer.contextWeight(record.postCount, distance: distance),
  related: related,
  complete: complete,
);

void main() {
  test('names only lead when the context already names one', () {
    final scores = RelatedTagScorer.score(
      context: [
        _context(_record('kimono', 200000), {
          'some_character': 30000,
          'obi': 20000,
        }),
      ],
      candidates: {
        'some_character': _record(
          'some_character',
          40000,
          TagCategory.character,
        ),
        'obi': _record('obi', 60000),
      },
    );
    expect(scores['obi'], 1.0);
    expect(scores['some_character']!, lessThan(1.0));
  });

  test('a cut-off list still shows a popular tag conflicts', () {
    final night = _record('night', 500000);
    // Cut off at 5000 shared posts: day, expected about 83000 times by
    // chance, was seen with night fewer than 5000 times.
    final scores = RelatedTagScorer.score(
      context: [
        _context(_record('outdoors', 1000000), {
          'day': 400000,
          'night_sky': 60000,
        }),
        _context(
          night,
          {'night_sky': 150000, 'moon': 5000},
          complete: false,
          distance: 1,
        ),
      ],
      candidates: {
        'day': _record('day', 1500000),
        'night_sky': _record('night_sky', 200000),
      },
    );
    expect(scores['night_sky'], 1.0);
    expect(scores['day']!, lessThan(0.1));
  });

  test('specific context tags weigh more than generic ones', () {
    expect(
      RelatedTagScorer.contextWeight(60000, distance: 0),
      greaterThan(RelatedTagScorer.contextWeight(6000000, distance: 0)),
    );
    expect(
      RelatedTagScorer.contextWeight(60000, distance: 0),
      greaterThan(RelatedTagScorer.contextWeight(60000, distance: 2)),
    );
  });
}
