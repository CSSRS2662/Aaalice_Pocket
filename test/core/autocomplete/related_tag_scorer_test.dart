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
  double weight = 1,
  bool complete = true,
}) => RelatedContextTag(
  record: record,
  weight: weight,
  related: related,
  complete: complete,
);

void main() {
  test('the last tag holds 60% and the rest split by specificity', () {
    expect(RelatedTagScorer.shares(const []), [1]);
    final shares = RelatedTagScorer.shares(const [60000, 6000000]);
    expect(shares.first, RelatedTagScorer.anchorShare);
    expect(shares.reduce((a, b) => a + b), closeTo(1, 1e-9));
    // A specific tag speaks louder than a `1girl`-like one.
    expect(shares[1], greaterThan(shares[2]));
  });

  test('the last tag leads even when a specific tag has bigger numbers', () {
    // classroom's companions score far higher than smile's in raw votes;
    // scaling each tag's votes lets smile's own pick reach the top.
    final scores = RelatedTagScorer.score(
      context: [
        _context(_record('smile', 2000000), {
          'grin': 150000,
          'desk': 20000,
        }, weight: 0.6),
        _context(_record('classroom', 60000), {
          'desk': 20000,
          'grin': 4000,
        }, weight: 0.4),
      ],
      candidates: {
        'grin': _record('grin', 400000),
        'desk': _record('desk', 80000),
      },
    );
    expect(scores['grin'], 1.0);
    expect(scores['desk']!, lessThan(1.0));
  });

  test('after a general tag only general tags are suggested', () {
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
    expect(scores.keys, ['obi']);
  });

  test('categories the user chose replace that rule', () {
    final scores = RelatedTagScorer.score(
      context: [
        _context(_record('kimono', 200000), {
          'some_character': 30000,
          'some_series': 25000,
          'obi': 20000,
        }),
      ],
      candidates: {
        'some_character': _record(
          'some_character',
          40000,
          TagCategory.character,
        ),
        'some_series': _record('some_series', 90000, TagCategory.copyright),
        'obi': _record('obi', 60000),
      },
      categories: {TagCategory.character},
    );
    expect(scores.keys, ['some_character']);
  });

  test('a character leads to its traits before its castmates', () {
    final scores = RelatedTagScorer.score(
      context: [
        _context(_record('some_character', 3000, TagCategory.character), {
          'green_eyes': 2400,
          'castmate': 1500,
        }),
      ],
      candidates: {
        'castmate': _record('castmate', 5000, TagCategory.character),
        'green_eyes': _record('green_eyes', 400000),
      },
    );
    expect(scores['green_eyes'], 1.0);
    expect(scores['castmate']!, lessThan(1.0));
  });

  test('a cut-off list still shows a popular tag conflicts', () {
    // Cut off at 5000 shared posts: day, expected about 83000 times by
    // chance, was seen with night fewer than 5000 times.
    final scores = RelatedTagScorer.score(
      context: [
        _context(_record('outdoors', 1000000), {
          'day': 400000,
          'night_sky': 60000,
        }, weight: 0.6),
        _context(
          _record('night', 500000),
          {'night_sky': 150000, 'moon': 5000},
          weight: 0.4,
          complete: false,
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
}
