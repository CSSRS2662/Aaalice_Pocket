import 'dart:math' as math;

import '../autocomplete_settings.dart';
import '../completion_models.dart';
import '../tag_catalog_repository.dart';
import 'chinese_fuzzy_match.dart';
import 'english_words.dart';
import 'lexical_search_index.dart';
import 'pinyin_syllables.dart';
import 'search_lexicon.dart';

/// Non-AI fallbacks that run after the literal sources answered:
///
/// * Chinese queries: homophones (陈山 → 衬衫), fuzzy sounds, labels sharing
///   most characters in order (拨起头发 → 拨头发), and the query split into
///   words searched as English tag tokens (坐在椅子上 → sitting_on_chair).
/// * Letter queries: corrected typos and other word forms when nothing
///   matched literally, then the letters read as full pinyin, Ziranma double
///   pinyin or syllable initials.
///
/// Candidates carry the evidence needed by the shared ranker.
class LexicalEnhancementSource implements SupplementalCompletionSource {
  LexicalEnhancementSource({
    required LexicalSearchIndex index,
    required Future<SearchLexicon> Function() lexicon,
    required TagCatalogRepository catalog,
    required AutocompleteSettings Function() settings,
  }) : _index = index,
       _lexicon = lexicon,
       _catalog = catalog,
       _settings = settings;

  final LexicalSearchIndex _index;
  final Future<SearchLexicon> Function() _lexicon;
  final TagCatalogRepository _catalog;
  final AutocompleteSettings Function() _settings;

  static final RegExp _hanzi = RegExp(r'[㐀-鿿]');
  static final RegExp _letterQuery = RegExp(r"^[a-zA-Z][a-zA-Z\s_'\-]*$");
  static final RegExp _separators = RegExp(r"[\s_'\-]+");
  static final RegExp _conceptRuns = RegExp(r'[㐀-鿿]+|[a-z0-9]+');
  static const int _perStage = 40;

  static const Set<CompletionMatchKind> _literalChinese = {
    CompletionMatchKind.chineseExact,
    CompletionMatchKind.chinesePrefix,
  };
  static const Set<CompletionMatchKind> _literalEnglish = {
    CompletionMatchKind.englishExact,
    CompletionMatchKind.englishPrefix,
    CompletionMatchKind.aliasExact,
    CompletionMatchKind.aliasPrefix,
  };

  @override
  Future<List<CompletionCandidate>> supplement(
    CompletionQuery query,
    List<CompletionCandidate> primary,
  ) async {
    if (query.kind != CompletionQueryKind.tag || query.relatedTag != null) {
      return const [];
    }
    final token = query.token.trim();
    if (token.isEmpty) return const [];
    final settings = _settings();
    final List<CompletionCandidate> rows;
    if (_hanzi.hasMatch(token)) {
      rows = await _chinese(query, token, primary, settings);
    } else if (_letterQuery.hasMatch(token)) {
      rows = await _letters(query, token, primary, settings);
    } else {
      return const [];
    }
    final scope = query.typedCategoryScope;
    return scope == null
        ? rows
        : rows
              .where((row) => scope.contains(row.category))
              .toList(growable: false);
  }

  // ------------------------------------------------------------ Chinese

  Future<List<CompletionCandidate>> _chinese(
    CompletionQuery query,
    String token,
    List<CompletionCandidate> primary,
    AutocompleteSettings settings,
  ) async {
    final text = chineseSearchKey(token);
    if (text.length < 2 || text.length > 32) return const [];
    final lexicon = await _lexicon();
    final results = <CompletionCandidate>[];
    final scope = query.typedCategoryScope;
    final strong = primary
        .where((row) => _literalChinese.contains(row.matchKind))
        .length;

    if (settings.pinyinSearchEnabled) {
      final variants = lexicon.pinyin.readingVariants(text, maxVariants: 6);
      if (variants.isNotEmpty) {
        final homophones = await _homophones(variants, scope);
        results.addAll(homophones);
        if (settings.fuzzyPinyinRules.isNotEmpty) {
          results.addAll(
            await _fuzzy(variants, settings.fuzzyPinyinRules, results, scope),
          );
        }
      }
    }
    if (settings.approximateMatchEnabled &&
        strong < (text.length == 2 ? 3 : 8)) {
      results.addAll(await _approximate(text, scope, lexicon.crossLingual));
    }
    if (settings.crossLingualEnabled &&
        (scope?.contains(TagCategory.general) ?? true)) {
      results.addAll(await _crossLingual(token, lexicon.crossLingual, strong));
    }
    return results;
  }

  Future<List<CompletionCandidate>> _homophones(
    List<List<String>> variants,
    Set<TagCategory>? scope,
  ) async {
    // Labels that start with the reading only: mid-label homophones
    // (葛城（闪乱… for 城山) are noise more often than what was meant.
    final rows = await _index.pinyinMatches(
      _expression('py', [for (final variant in variants) _phrase(variant)]),
      limit: 160,
      scope: scope,
    );
    final best = <String, CompletionCandidate>{};
    for (final row in rows) {
      final syllables = row.pinyin.split(' ');
      final quality = variants
          .map((variant) => _sequenceQuality(syllables, variant))
          .reduce(math.max);
      if (quality <= 0) continue;
      _keepBest(
        best,
        _labelCandidate(row, CompletionMatchKind.homophone, quality),
      );
    }
    return _top(best.values);
  }

  Future<List<CompletionCandidate>> _fuzzy(
    List<List<String>> variants,
    Set<FuzzyPinyinRule> rules,
    List<CompletionCandidate> found,
    Set<TagCategory>? scope,
  ) async {
    final expression = _expression('pyf', [
      for (final variant in variants)
        _phrase(variant.map(foldPinyinFully).toList()),
    ]);
    final known = found.map((row) => row.stableId).toSet();
    final best = <String, CompletionCandidate>{};
    for (final row in await _index.pinyinMatches(expression, scope: scope)) {
      final syllables = row.pinyin.split(' ');
      var quality = 0.0;
      for (final variant in variants) {
        if (syllables.length < variant.length) continue;
        var same = true;
        var exact = true;
        for (var i = 0; i < variant.length && same; i++) {
          if (syllables[i] != variant[i]) exact = false;
          same =
              foldPinyin(syllables[i], rules) == foldPinyin(variant[i], rules);
        }
        // Exact readings were homophones already.
        if (!same || exact) continue;
        quality = math.max(
          quality,
          syllables.length == variant.length ? 1 : 0.6,
        );
      }
      if (quality <= 0) continue;
      final candidate = _labelCandidate(
        row,
        CompletionMatchKind.fuzzyPinyin,
        quality,
      );
      if (!known.contains(candidate.stableId)) _keepBest(best, candidate);
    }
    return _top(best.values);
  }

  Future<List<CompletionCandidate>> _approximate(
    String text,
    Set<TagCategory>? scope,
    CrossLingualLexicon lexicon,
  ) async {
    final anchors = text.length < 5
        ? const <String>[]
        : [
            for (final word in lexicon.segment(text))
              if (word.length >= 2 &&
                  !lexicon.isDropped(word) &&
                  lexicon.candidatesOf(word) != null)
                word,
          ];
    final best = <String, CompletionCandidate>{};
    for (final row in await _index.characterMatches(text, scope: scope)) {
      final label = chineseSearchKey(row.label);
      if (label.startsWith(text)) continue;
      final quality = chineseFuzzyQuality(text, label);
      if (quality <= 0) continue;
      final coverage = anchors.isEmpty
          ? 1.0
          : anchors.where(label.contains).length / anchors.length;
      _keepBest(
        best,
        _labelCandidate(
          row,
          CompletionMatchKind.approximate,
          quality * (.82 + .18 * coverage),
        ),
      );
    }
    return _top(best.values);
  }

  Future<List<CompletionCandidate>> _crossLingual(
    String text,
    CrossLingualLexicon lexicon,
    int strong,
  ) async {
    final groups = <List<String>>[];
    final words = <String>[];
    var covered = 0;
    var unknown = 0;
    for (final run in _conceptRuns.allMatches(text.toLowerCase())) {
      final part = run.group(0)!;
      final chinese = _hanzi.hasMatch(part);
      for (final segment in chinese ? lexicon.segment(part) : [part]) {
        if (lexicon.isDropped(segment)) continue;
        final alternatives = chinese ? lexicon.candidatesOf(segment) : [part];
        if (alternatives == null) {
          unknown += segment.length;
          continue;
        }
        covered += segment.length;
        if (words.contains(segment)) continue;
        groups.add([
          for (final term in alternatives)
            EnglishWords.concepts(term).join(' '),
        ]);
        words.add(segment);
      }
    }
    if (groups.isEmpty ||
        groups.length > 8 ||
        unknown > covered ||
        (groups.length == 1 && (unknown > 0 || strong > 0))) {
      return const [];
    }
    final coverage = covered / (covered + unknown);
    final confidence = (.6 + .4 * coverage) * (groups.length == 1 ? .82 : 1);
    final best = <String, CompletionCandidate>{};
    final hint = words.join('·');
    for (final row in await _index.conceptMatches(groups)) {
      _keepBest(
        best,
        CompletionCandidate(
          canonicalTag: row.tag,
          category: TagCategory.general,
          postCount: row.postCount,
          matchKind: CompletionMatchKind.crossLingual,
          sources: const {CompletionSourceKind.base},
          matchHint: hint,
          matchQuality: confidence * _conceptQuality(row.tokens, groups),
        ),
      );
    }
    return _top(best.values);
  }

  // ------------------------------------------------------------ letters

  Future<List<CompletionCandidate>> _letters(
    CompletionQuery query,
    String token,
    List<CompletionCandidate> primary,
    AutocompleteSettings settings,
  ) async {
    final results = <CompletionCandidate>[];
    if (settings.pinyinSearchEnabled) {
      final letters = token.toLowerCase().replaceAll(_separators, '');
      if (letters.length >= 2) {
        results.addAll(
          await _pinyinLetters(letters, settings, query.typedCategoryScope),
        );
      }
    }
    // Letters that read as whole syllables with matches are pinyin, not an
    // English typo (chenshan is not a misspelt henshin).
    final shortInitials = token.length <= 3;
    final readsAsPinyin = results.any(
      (row) =>
          row.matchQuality >= 1 &&
          (row.matchKind == CompletionMatchKind.pinyin ||
              row.matchKind == CompletionMatchKind.shuangpin ||
              (shortInitials &&
                  row.matchKind == CompletionMatchKind.pinyinInitials)),
    );
    final literal = primary.any(
      (row) => _literalEnglish.contains(row.matchKind),
    );
    if (settings.spellCorrectionEnabled && !literal && !readsAsPinyin) {
      results.addAll(await _englishFallbacks(query, token));
    }
    return results;
  }

  Future<List<CompletionCandidate>> _englishFallbacks(
    CompletionQuery query,
    String token,
  ) async {
    final words = EnglishWords.tokens(token).toList(growable: false);
    if (words.isEmpty || words.length > 8) return const [];
    final results = <CompletionCandidate>[];

    final stems = words.map(EnglishWords.stem).toList(growable: false);
    if (stems.join('_') != words.join('_')) {
      results.addAll(
        await _searchRewritten(
          query,
          stems,
          CompletionMatchKind.englishVariant,
          1,
        ),
      );
    }

    final weights = await _index.vocabularyWeights(words);
    final alternatives = await Future.wait([
      for (final word in words)
        if (weights.containsKey(word))
          Future.value(const <SpellSuggestion>[])
        else
          _index.spellingSuggestions(word, limit: 10),
    ]);
    if (alternatives.every((choices) => choices.isEmpty)) return results;
    final groups = [
      for (var i = 0; i < words.length; i++)
        [words[i], ...alternatives[i].map((item) => item.word)],
    ];
    final best = <String, CompletionCandidate>{};
    for (final row in await _catalog.searchSpellingCandidates(
      groups,
      scope: query.typedCategoryScope,
    )) {
      final term = EnglishWords.tokens(
        row.matchedAlias ?? row.canonicalTag,
      ).toList(growable: false);
      final corrected = <String>[];
      var distance = 0;
      for (var i = 0; i < words.length; i++) {
        final matches = groups[i].where(term.contains);
        if (matches.isEmpty) break;
        final chosen = matches.first;
        corrected.add(chosen);
        distance += EnglishWords.distance(words[i], chosen);
      }
      if (corrected.length != words.length || distance == 0) continue;
      final exact = term.join(' ') == corrected.join(' ');
      _keepBest(
        best,
        row.copyWith(
          matchHint: corrected.join(' '),
          matchQuality: (1 - distance / (token.length + 2)) * (exact ? 1 : .67),
        ),
      );
    }
    return [...results, ..._top(best.values)];
  }

  Future<List<CompletionCandidate>> _searchRewritten(
    CompletionQuery query,
    List<String> words,
    CompletionMatchKind kind,
    double quality,
  ) async {
    final rewritten = words.join('_');
    final rows = await _catalog.search(
      query.copyWith(token: rewritten, limit: _perStage),
    );
    return [
      for (final row in rows)
        if (_literalEnglish.contains(row.matchKind))
          row.copyWith(
            matchKind: kind,
            matchHint: words.join(' '),
            // Exact rewrites ahead of prefix rewrites.
            matchQuality:
                quality *
                (row.matchKind == CompletionMatchKind.englishExact ||
                        row.matchKind == CompletionMatchKind.aliasExact
                    ? 1
                    : 0.7),
          ),
    ];
  }

  Future<List<CompletionCandidate>> _pinyinLetters(
    String letters,
    AutocompleteSettings settings,
    Set<TagCategory>? scope,
  ) async {
    final lexicon = await _lexicon();
    final syllables = lexicon.pinyin.syllables;
    final best = <String, CompletionCandidate>{};

    Future<void> run(
      List<String> pieces, {
      required bool partialLast,
      required CompletionMatchKind kind,
      bool prefixesOnly = false,
    }) async {
      final terms = [
        for (var i = 0; i < pieces.length; i++)
          prefixesOnly || (partialLast && i == pieces.length - 1)
              ? '${pieces[i]}*'
              : pieces[i],
      ];
      final rows = await _index.pinyinMatches(
        'py : (^${terms.join(' + ')})',
        limit: 120,
        scope: scope,
      );
      for (final row in rows) {
        final sameLength = row.pinyin.split(' ').length == pieces.length;
        // Initials are loose enough already: only labels of that length.
        if (prefixesOnly && !sameLength) continue;
        final quality = !sameLength
            ? 0.6
            : partialLast
            ? 0.8
            : 1.0;
        _keepBest(best, _labelCandidate(row, kind, quality));
      }
    }

    if (settings.pinyinFullEnabled) {
      for (final split in syllables.splitFullPinyin(letters)) {
        await run(
          split.pieces,
          partialLast: split.partialLast,
          kind: CompletionMatchKind.pinyin,
        );
      }
    }
    if (settings.pinyinZiranmaEnabled) {
      final split = syllables.splitZiranma(letters);
      if (split != null) {
        await run(
          split.pieces,
          partialLast: split.partialLast,
          kind: CompletionMatchKind.shuangpin,
        );
      }
    }
    if (letters.length <= 8) {
      final letterList = letters.split('');
      if (settings.pinyinFullEnabled &&
          letterList.every(PinyinSyllables.isFullInitialLetter)) {
        await run(
          letterList,
          partialLast: false,
          kind: CompletionMatchKind.pinyinInitials,
          prefixesOnly: true,
        );
      }
      if (settings.pinyinZiranmaEnabled &&
          letterList.any(
            (letter) => !PinyinSyllables.isFullInitialLetter(letter),
          )) {
        await run(
          letterList.map(PinyinSyllables.ziranmaInitialOf).toList(),
          partialLast: false,
          kind: CompletionMatchKind.pinyinInitials,
          prefixesOnly: true,
        );
      }
    }
    return _top(best.values);
  }

  // ------------------------------------------------------------ helpers

  /// Syllables in order at the start of a reading.
  static String _phrase(List<String> syllables) =>
      '(^${syllables.join(' + ')})';

  static String _expression(String column, List<String> phrases) =>
      '$column : (${phrases.toSet().join(' OR ')})';

  /// 1 for the same syllables, 0.6 when the label starts with them, 0
  /// otherwise.
  static double _sequenceQuality(List<String> label, List<String> query) {
    if (label.length < query.length) return 0;
    for (var i = 0; i < query.length; i++) {
      if (label[i] != query[i]) return 0;
    }
    return label.length == query.length ? 1 : 0.6;
  }

  static const Set<String> _stopWords = {
    'on',
    'in',
    'with',
    'of',
    'the',
    'a',
    'an',
    'at',
    'to',
    'from',
    'by',
    'and',
    'own',
    'up',
  };

  static double _conceptQuality(String term, List<List<String>> groups) {
    final padded = ' $term ';
    final covered = <String>{};
    var penalty = 0.0;
    var last = -1;
    for (final alternatives in groups) {
      for (var i = 0; i < alternatives.length; i++) {
        final alternative = alternatives[i];
        final position = padded.indexOf(' $alternative ');
        if (position < 0) continue;
        if (position < last) penalty += .06;
        penalty += i * .035;
        covered.addAll(alternative.split(' '));
        last = position;
        break;
      }
    }
    final extra = term
        .split(' ')
        .where((word) => !_stopWords.contains(word) && !covered.contains(word))
        .length;
    return ((1 - penalty) / (1 + extra * .48)).clamp(0, 1);
  }

  static CompletionCandidate _labelCandidate(
    LexicalLabelMatch row,
    CompletionMatchKind kind,
    double quality,
  ) => CompletionCandidate(
    canonicalTag: row.tag,
    category: _category(row.category),
    postCount: row.postCount,
    matchHint: row.label,
    matchKind: kind,
    sources: const {CompletionSourceKind.base},
    matchQuality: quality,
  );

  static TagCategory _category(int value) => TagCategory.values.firstWhere(
    (category) => category.value == value,
    orElse: () => TagCategory.general,
  );

  static void _keepBest(
    Map<String, CompletionCandidate> best,
    CompletionCandidate candidate,
  ) {
    final current = best[candidate.stableId];
    if (current == null ||
        candidate.matchQuality > current.matchQuality ||
        (candidate.matchQuality == current.matchQuality &&
            candidate.matchKind.index < current.matchKind.index)) {
      best[candidate.stableId] = candidate;
    }
  }

  static List<CompletionCandidate> _top(Iterable<CompletionCandidate> rows) {
    final ordered = rows.toList()
      ..sort((a, b) {
        final quality = b.matchQuality.compareTo(a.matchQuality);
        if (quality != 0) return quality;
        return b.postCount.compareTo(a.postCount);
      });
    return ordered.take(_perStage).toList(growable: false);
  }
}
