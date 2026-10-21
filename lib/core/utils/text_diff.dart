/// How a piece of text fares between two versions.
enum TextDiffKind { same, added, removed }

class TextDiffSegment {
  const TextDiffSegment(this.kind, this.text);

  final TextDiffKind kind;
  final String text;

  @override
  bool operator ==(Object other) =>
      other is TextDiffSegment && other.kind == kind && other.text == text;

  @override
  int get hashCode => Object.hash(kind, text);

  @override
  String toString() => '${kind.name}($text)';
}

/// Words, runs of spaces, separators (commas and the like) and single CJK
/// characters, so a changed tag or word is marked as a whole.
final RegExp _token = RegExp(
  r'\s+|[,，、;；:：()（）{}\[\]<>|]|[぀-ヿ㐀-鿿]|[^\s,，、;；:：()（）{}\[\]<>|぀-ヿ㐀-鿿]+',
);

/// The longest common subsequence of tokens beyond this many cells is not
/// worth computing for a confirmation card; the text is shown replaced.
const int _maxDiffCells = 250000;

/// Marks what [after] adds to and removes from [before], token by token,
/// with neighbouring segments of one kind merged.
List<TextDiffSegment> diffText(String before, String after) {
  if (before == after) {
    return before.isEmpty
        ? const []
        : [TextDiffSegment(TextDiffKind.same, before)];
  }
  final a = [for (final match in _token.allMatches(before)) match[0]!];
  final b = [for (final match in _token.allMatches(after)) match[0]!];
  // Shared ends need no table.
  var start = 0;
  while (start < a.length && start < b.length && a[start] == b[start]) {
    start++;
  }
  var endA = a.length;
  var endB = b.length;
  while (endA > start && endB > start && a[endA - 1] == b[endB - 1]) {
    endA--;
    endB--;
  }
  final segments = <TextDiffSegment>[];
  void add(TextDiffKind kind, String text) {
    if (text.isEmpty) return;
    if (segments.isNotEmpty && segments.last.kind == kind) {
      segments[segments.length - 1] = TextDiffSegment(
        kind,
        segments.last.text + text,
      );
    } else {
      segments.add(TextDiffSegment(kind, text));
    }
  }

  add(TextDiffKind.same, a.sublist(0, start).join());
  final midA = a.sublist(start, endA);
  final midB = b.sublist(start, endB);
  if ((midA.length + 1) * (midB.length + 1) > _maxDiffCells) {
    add(TextDiffKind.removed, midA.join());
    add(TextDiffKind.added, midB.join());
  } else {
    final rows = midA.length + 1;
    final cols = midB.length + 1;
    final lengths = List<int>.filled(rows * cols, 0);
    for (var i = midA.length - 1; i >= 0; i--) {
      for (var j = midB.length - 1; j >= 0; j--) {
        lengths[i * cols + j] = midA[i] == midB[j]
            ? lengths[(i + 1) * cols + j + 1] + 1
            : _max(lengths[(i + 1) * cols + j], lengths[i * cols + j + 1]);
      }
    }
    var i = 0;
    var j = 0;
    while (i < midA.length && j < midB.length) {
      if (midA[i] == midB[j]) {
        add(TextDiffKind.same, midA[i]);
        i++;
        j++;
      } else if (lengths[(i + 1) * cols + j] >= lengths[i * cols + j + 1]) {
        add(TextDiffKind.removed, midA[i]);
        i++;
      } else {
        add(TextDiffKind.added, midB[j]);
        j++;
      }
    }
    add(TextDiffKind.removed, midA.sublist(i).join());
    add(TextDiffKind.added, midB.sublist(j).join());
  }
  add(TextDiffKind.same, a.sublist(endA).join());
  return segments;
}

int _max(int a, int b) => a > b ? a : b;
