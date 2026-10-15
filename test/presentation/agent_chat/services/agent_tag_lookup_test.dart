import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/autocomplete/autocomplete_cache_database.dart';
import 'package:nai_launcher/core/autocomplete/autocomplete_providers.dart';
import 'package:nai_launcher/core/autocomplete/autocomplete_settings.dart';
import 'package:nai_launcher/core/autocomplete/completion_models.dart';
import 'package:nai_launcher/core/autocomplete/danbooru_completion_source.dart';
import 'package:nai_launcher/presentation/agent_chat/services/agent_tag_lookup.dart';
import 'package:nai_launcher/presentation/agent_chat/services/tag_toolbox.dart';

final _refProvider = Provider<Ref>((ref) => ref);

CompletionCandidate _tag(
  String tag,
  TagCategory category, {
  String? translation,
  CompletionMatchKind kind = CompletionMatchKind.related,
  int? cooccurrence,
}) => CompletionCandidate(
  canonicalTag: tag,
  category: category,
  postCount: 1000,
  translation: translation,
  matchKind: kind,
  sources: const {CompletionSourceKind.base},
  cooccurrenceCount: cooccurrence,
);

/// Answers searches by token and related queries by anchor.
class _Catalog implements CompletionSource {
  final related = <CompletionQuery>[];

  @override
  Future<List<CompletionCandidate>> search(CompletionQuery query) async {
    if (query.relatedTag case final anchor? when query.token.isEmpty) {
      related.add(query);
      if (anchor != 'genshin_impact') return const [];
      return [
        _tag('raiden_shogun', TagCategory.character, cooccurrence: 900),
        _tag('1girl', TagCategory.general, cooccurrence: 800),
        _tag('nahida_(genshin_impact)', TagCategory.character),
        _tag('genshin_impact', TagCategory.copyright),
      ];
    }
    return switch (query.token) {
      '原神' => [
        _tag(
          'genshin_impact',
          TagCategory.copyright,
          translation: '原神',
          kind: CompletionMatchKind.chineseExact,
        ),
      ],
      'chenshan' => [
        _tag(
          'shirt',
          TagCategory.general,
          translation: '衬衫',
          kind: CompletionMatchKind.pinyin,
        ),
      ],
      'genshi' => [
        _tag(
          'genshin_impact',
          TagCategory.copyright,
          kind: CompletionMatchKind.englishPrefix,
        ),
      ],
      _ => const [],
    };
  }
}

class _NoTranslations implements TranslationResolver {
  @override
  Future<Map<String, String>> resolve(
    List<String> canonicalTags, {
    required String locale,
  }) async => const {};
}

class _OfflineDanbooru extends DanbooruCompletionSource {
  _OfflineDanbooru() : super(cache: AutocompleteCacheDatabase());

  @override
  Future<List<CompletionCandidate>> search(CompletionQuery query) =>
      throw StateError('the agent must not search online');
}

AgentTagLookup _lookup(_Catalog catalog) => AgentTagLookup(
  services: AutocompleteServices(
    localSources: [catalog],
    tagLookupSources: [catalog],
    dictionaryTranslations: _NoTranslations(),
    llmTranslations: _NoTranslations(),
    danbooru: _OfflineDanbooru(),
  ),
  // The editor's own switches never turn the agent's lookup off or online.
  settings: const AutocompleteSettings(enabled: false, danbooruEnabled: true),
);

void main() {
  test('search reads Chinese and pinyin through the editor pipeline', () async {
    final lookup = _lookup(_Catalog());
    final chinese = await lookup.search('原神', limit: 10);
    expect(chinese.candidates.single.canonicalTag, 'genshin_impact');
    final pinyin = await lookup.search('chenshan', limit: 10);
    expect(pinyin.candidates.single.matchKind, CompletionMatchKind.pinyin);
  });

  test('related resolves a Chinese anchor and keeps the chosen categories', () async {
    final catalog = _Catalog();
    final result = await _lookup(catalog).related(
      ['原神', 'smile', 'Red Hair'],
      limit: 10,
      categories: {TagCategory.character},
    );
    expect(result.relatedAnchor, 'genshin_impact');
    expect(
      result.candidates.map((candidate) => candidate.canonicalTag),
      ['raiden_shogun', 'nahida_(genshin_impact)'],
    );
    final query = catalog.related.last;
    expect(query.contextTags, ['smile', 'red_hair']);
    expect(query.relatedCategories, {TagCategory.character});
  });

  test('a prefix anchor falls back to a search, and says so', () async {
    final result = await _lookup(
      _Catalog(),
    ).related(['genshi'], limit: 10);
    expect(result.relatedAnchor, isNull);
    expect(result.candidates.single.canonicalTag, 'genshin_impact');
  });

  test('search_tags suggest returns the anchor and category-filtered rows', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final tool = TagToolbox(
      container.read(_refProvider),
      lookup: () => _lookup(_Catalog()),
    ).tools().single;

    final result = await tool.execute('suggest', const {
      'mode': 'suggest',
      'query': '原神',
      'categories': ['character'],
    });
    expect(result.isError, isFalse);
    expect(result.details['anchor'], 'genshin_impact');
    final rows = result.details['results'] as List;
    expect(rows.first, {
      'tag': 'raiden_shogun',
      'category': 'character',
      'post_count': 1000,
      'cooccurrence': 900,
    });

    final pinyin = await tool.execute('search', const {'query': 'chenshan'});
    expect((pinyin.details['results'] as List).single, {
      'tag': 'shirt',
      'category': 'general',
      'post_count': 1000,
      'chinese': '衬衫',
      'match': 'pinyin',
    });

    final rejected = await tool.execute('bad', const {
      'mode': 'suggest',
      'query': 'genshin_impact',
      'categories': ['artist'],
    });
    expect(rejected.details['code'], 'invalid_categories');
  });
}
