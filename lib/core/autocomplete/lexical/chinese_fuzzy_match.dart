import 'dart:math' as math;

import 'english_words.dart';

final _separators = RegExp(r'[^a-z0-9㐀-鿿]');

String chineseSearchKey(String text) =>
    text.toLowerCase().replaceAll(_separators, '');

Iterable<String> chineseBigrams(String text) sync* {
  for (var i = 1; i < text.length; i++) {
    yield text.substring(i - 1, i + 1);
  }
}

int chineseEditBudget(int length) => (length ~/ 3).clamp(1, 4);

double chineseFuzzyQuality(String query, String label) {
  final budget = chineseEditBudget(query.length);
  final longer = math.max(query.length, label.length);
  if ((query.length - label.length).abs() > budget + 1 || label.isEmpty) {
    return 0;
  }
  final edits = EnglishWords.distance(query, label);
  final ordered = _orderedOverlap(query, label);
  if (edits <= budget) {
    final shorter = math.min(query.length, label.length);
    final remaining = label.split('').toList();
    final shared = query.split('').where(remaining.remove).length;
    final sameCharacters = shared == longer;
    final shortLabelPenalty = label.length == 1 && !sameCharacters ? .14 : 0;
    return (.62 +
            .25 * (1 - edits / longer) +
            (.07 * ordered + .06 * shared) / shorter +
            (sameCharacters && edits == 1 ? .035 : 0) -
            shortLabelPenalty)
        .clamp(0, 1);
  }

  // A fragment can leave gaps, and two intact phrases can arrive out of order.
  if (query.length < 4) return 0;
  final pairs = chineseBigrams(label).toSet();
  final pairCoverage =
      chineseBigrams(query).where(pairs.contains).length / (query.length - 1);
  final orderCoverage = ordered / longer;
  final anchored =
      orderCoverage >= .5 &&
      query.length >= 5 &&
      _hasSharedTrigram(query, label);
  if (!anchored && orderCoverage < .6 && pairCoverage < .5) return 0;
  return (anchored ? .33 : .20) + .36 * orderCoverage + .23 * pairCoverage;
}

bool _hasSharedTrigram(String query, String label) {
  for (var i = 3; i <= query.length; i++) {
    if (label.contains(query.substring(i - 3, i))) return true;
  }
  return false;
}

int _orderedOverlap(String a, String b) {
  final row = List<int>.filled(b.length + 1, 0);
  for (var i = 0; i < a.length; i++) {
    var diagonal = 0;
    for (var j = 0; j < b.length; j++) {
      final above = row[j + 1];
      row[j + 1] = a.codeUnitAt(i) == b.codeUnitAt(j)
          ? diagonal + 1
          : math.max(above, row[j]);
      diagonal = above;
    }
  }
  return row.last;
}
