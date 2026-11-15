import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import 'english_words.dart';
import 'pinyin_syllables.dart';

/// Bundled data for non-AI lexical search, built by
/// `tool/search_lexicon/build_search_lexicon.py` from pinned MIT sources.
class SearchLexicon {
  SearchLexicon._(this.pinyin, this.crossLingual, this.version);

  static const pinyinAsset = 'assets/search_lexicon/hanzi_pinyin.json.gz';
  static const crossLingualAsset =
      'assets/search_lexicon/zh_en_lexicon.json.gz';

  final HanziPinyinTable pinyin;
  final CrossLingualLexicon crossLingual;

  /// Changes whenever either data file changes; part of the index fingerprint.
  final String version;

  static SearchLexicon decode({
    required Uint8List pinyinGz,
    required Uint8List crossLingualGz,
  }) {
    final readings =
        (jsonDecode(utf8.decode(gzip.decode(pinyinGz))) as Map)['readings']
            as Map;
    final lexicon = jsonDecode(utf8.decode(gzip.decode(crossLingualGz))) as Map;
    final digest = sha1.convert([...pinyinGz, ...crossLingualGz]).toString();
    return SearchLexicon._(
      HanziPinyinTable({
        for (final entry in readings.entries)
          (entry.key as String).runes.first: (entry.value as String).split(','),
      }),
      CrossLingualLexicon(
        words: {
          for (final entry in (lexicon['words'] as Map).entries)
            entry.key as String: List<String>.unmodifiable(
              (entry.value as List).cast<String>(),
            ),
        },
        drop: (lexicon['drop'] as List).cast<String>().toSet(),
      ),
      digest.substring(0, 12),
    );
  }

  static Future<SearchLexicon> loadAssets({AssetBundle? bundle}) async {
    final source = bundle ?? rootBundle;
    final pinyin = await source.load(pinyinAsset);
    final words = await source.load(crossLingualAsset);
    return decode(
      pinyinGz: pinyin.buffer.asUint8List(
        pinyin.offsetInBytes,
        pinyin.lengthInBytes,
      ),
      crossLingualGz: words.buffer.asUint8List(
        words.offsetInBytes,
        words.lengthInBytes,
      ),
    );
  }
}

/// Toneless readings per character, most common first (at most three).
class HanziPinyinTable {
  HanziPinyinTable(this._readings)
    : syllables = PinyinSyllables(_readings.values.expand((r) => r));

  final Map<int, List<String>> _readings;
  final PinyinSyllables syllables;

  List<String>? readingsOf(int rune) => _readings[rune];

  static bool isHanzi(int rune) => rune >= 0x3400 && rune <= 0x9fff;

  /// Syllable sequences for [text], one per combination of readings, ordered
  /// by how common the readings are. Latin letters and digits become one
  /// token per run; other characters are skipped. Returns empty when a
  /// character has no reading or [text] has no hanzi.
  List<List<String>> readingVariants(String text, {int maxVariants = 4}) {
    final slots = <List<String>>[];
    final ascii = StringBuffer();
    var hasHanzi = false;
    void flushAscii() {
      if (ascii.isEmpty) return;
      slots.add([ascii.toString()]);
      ascii.clear();
    }

    for (final rune in text.toLowerCase().runes) {
      if (isHanzi(rune)) {
        flushAscii();
        final readings = _readings[rune];
        if (readings == null || readings.isEmpty) return const [];
        slots.add(readings);
        hasHanzi = true;
      } else if ((rune >= 0x61 && rune <= 0x7a) ||
          (rune >= 0x30 && rune <= 0x39)) {
        ascii.writeCharCode(rune);
      } else {
        flushAscii();
      }
    }
    flushAscii();
    if (!hasHanzi) return const [];

    // Best-first over reading ranks: the common reading of every character,
    // then one less common reading at a time.
    final variants = <List<String>>[];
    final seen = <String>{};
    void add(List<int> choice) {
      final sequence = [
        for (var i = 0; i < slots.length; i++) slots[i][choice[i]],
      ];
      if (seen.add(sequence.join(' '))) variants.add(sequence);
    }

    final base = List.filled(slots.length, 0);
    add(base);
    for (var rank = 1; rank < 3 && variants.length < maxVariants; rank++) {
      for (var i = 0; i < slots.length && variants.length < maxVariants; i++) {
        if (slots[i].length > rank) add([...base]..[i] = rank);
      }
    }
    return variants;
  }
}

/// Chinese words mapped to English tag-name tokens, plus the function words a
/// tag search should ignore. A candidate containing `_` is a phrase.
class CrossLingualLexicon {
  CrossLingualLexicon({
    required Map<String, List<String>> words,
    required Set<String> drop,
  }) : _words = words,
       _drop = drop,
       _maxWordLength = [
         ...words.keys,
         ...drop,
       ].fold<int>(1, (max, word) => word.length > max ? word.length : max);

  final Map<String, List<String>> _words;
  final Set<String> _drop;
  final int _maxWordLength;

  List<String>? candidatesOf(String word) => _words[word];

  static final _indefiniteClassifier = RegExp(r'^一[辆輛艘棵颗顆片块塊张張顶頂枚]$');

  bool isDropped(String word) =>
      _drop.contains(word) || _indefiniteClassifier.hasMatch(word);

  Set<String> get englishWords => {
    for (final alternatives in _words.values)
      for (final term in alternatives) ...EnglishWords.tokens(term),
  };

  /// Favors longer known words while accounting for uncovered characters
  /// across the entire query. Uncovered characters remain in the output.
  List<String> segment(String text) {
    final scores = List<double>.filled(text.length + 1, 0);
    final lengths = List<int>.filled(text.length, 1);
    for (var start = text.length - 1; start >= 0; start--) {
      scores[start] = scores[start + 1] - 2;
      final longest = _maxWordLength.clamp(1, text.length - start);
      for (var length = longest; length > 0; length--) {
        final word = text.substring(start, start + length);
        final known = _words.containsKey(word);
        if (!known && !isDropped(word)) continue;
        final score = scores[start + length] + length * (known ? 2 : 1.9) - 1;
        if (score <= scores[start]) continue;
        scores[start] = score;
        lengths[start] = length;
      }
    }
    return [
      for (var start = 0; start < text.length; start += lengths[start])
        text.substring(start, start + lengths[start]),
    ];
  }
}

/// Short stable hash of bytes, for fingerprints of bundled inputs.
String shortDigest(List<int> bytes) =>
    sha1.convert(bytes).toString().substring(0, 12);
