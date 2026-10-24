import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/autocomplete/lexical/lexical_search_providers.dart';
import '../../core/autocomplete/lexical/search_lexicon.dart';

/// Turns a name into a key that sorts Chinese names by pinyin among Latin
/// ones.
typedef NameSortKey = String Function(String name);

/// Name sorting by pinyin, ready once the bundled pinyin table has loaded.
/// Until then, or if it cannot load, names sort by their characters.
final nameSortKeyProvider = FutureProvider<NameSortKey>((ref) async {
  final lexicon = await ref.watch(searchLexiconAssetsProvider).lexicon();
  final readings = lexicon.pinyin.readingsOf;
  final cache = <String, String>{};
  return (name) => cache.putIfAbsent(name, () => pinyinSortKey(name, readings));
});

/// [name] in lower case with each hanzi spelled by its most common reading,
/// so 白色背景 sorts as "bai se bei jing" next to "background".
String pinyinSortKey(String name, List<String>? Function(int rune) readingsOf) {
  final key = StringBuffer();
  for (final rune in name.trim().toLowerCase().runes) {
    final readings = HanziPinyinTable.isHanzi(rune) ? readingsOf(rune) : null;
    if (readings == null || readings.isEmpty) {
      key.writeCharCode(rune);
    } else {
      key
        ..write(readings.first)
        ..write(' ');
    }
  }
  return key.toString();
}

/// Compares names by [key] when given, else by their lower-case text.
int compareNames(String a, String b, NameSortKey? key) {
  final left = key == null ? a.toLowerCase() : key(a);
  final right = key == null ? b.toLowerCase() : key(b);
  return left.compareTo(right);
}
