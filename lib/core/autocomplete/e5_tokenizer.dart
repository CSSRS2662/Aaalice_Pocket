import 'dart:convert';

import 'package:dart_sentencepiece_tokenizer/dart_sentencepiece_tokenizer.dart';
import 'package:unorm_dart/unorm_dart.dart' as unicode;

/// XLM-R special tokens and metaspace preprocessing for multilingual E5.
class E5Tokenizer {
  E5Tokenizer(String json) {
    final data = jsonDecode(json) as Map<String, dynamic>;
    // The package's HF loader does not inspect the Metaspace pre-tokenizer.
    data['normalizer'] = {
      'type': 'Sequence',
      'normalizers': [
        {'type': 'Prepend', 'prepend': '\u2581'},
        {'type': 'Replace', 'content': '\u2581'},
      ],
    };
    _tokenizer = HuggingFaceTokenizerLoader.fromMap(
      data,
      config: const SentencePieceConfig(),
    );
  }

  late final SentencePieceTokenizer _tokenizer;

  List<int> encodeQuery(String query) => _encode('query: ', query);

  /// Document side of E5, as the bundled vectors were encoded.
  List<int> encodePassage(String passage) => _encode('passage: ', passage);

  List<int> _encode(String prefix, String text) {
    final normalized = unicode
        .nfkc('$prefix${String.fromCharCodes(text.trim().runes.take(2048))}')
        .replaceAll(RegExp(r'\s+'), ' ');
    final ids = <int>[];
    for (final word in normalized.split(' ')) {
      if (word.isEmpty) continue;
      ids.addAll(_tokenizer.encode(word, addSpecialTokens: false).ids);
      if (ids.length >= 126) break;
    }
    return [0, ...ids.take(126), 2];
  }
}
