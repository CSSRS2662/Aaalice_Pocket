import 'lexical/english_words.dart';

typedef _Contrast = ({
  Set<String> wanted,
  Set<String> opposite,
  String? subject,
});

/// Explicit contrasts the embedding can otherwise treat as near synonyms.
class CompletionIntent {
  CompletionIntent(String text)
    : _axes = _detectAxes(text),
      _posture = _detectPosture(text),
      _closed = _closure(text),
      _quantity = _bodyQuantity.firstMatch(text),
      _absence = _missingClothing.hasMatch(text),
      _avoidSingle = _negatedOnly.hasMatch(text);

  final List<_Contrast> _axes;
  final Set<String>? _posture;
  final bool? _closed;
  final RegExpMatch? _quantity;
  final bool _absence;
  final bool _avoidSingle;

  static final _bodyQuantity = RegExp(
    r'(一|单|兩|两|二|双|雙)(?:只|隻|条|條|侧|側|边|邊)?(眼|手|脚|腳|腿|臂)',
  );
  static const _bodyParts = {
    '眼': ('eye', 'eyes'),
    '手': ('hand', 'hands'),
    '脚': ('foot', 'feet'),
    '腳': ('foot', 'feet'),
    '腿': ('leg', 'legs'),
    '臂': ('arm', 'arms'),
  };
  static final _missingClothing = RegExp(r'(?:不|没|沒|没有|沒有|未)(?:穿|戴|系)|^无|^無');
  static final _open = RegExp(r'张开|張開|睁[开開眼]|睜[开開眼]|敞[开開着著]|打开|打開|张嘴|張嘴');
  static final _close = RegExp(r'闭|閉|关闭|關閉|合上|闭合|閉合');
  static final _negatedOpen = RegExp(
    r'(?:没有|沒有|没|沒|未|不|不要|别|別)(?:张开|張開|睁开|睜開|敞开|敞開|打开|打開|张嘴|張嘴)',
  );
  static final _negatedClose = RegExp(r'(?:不|不要|别|別)(?:[闭閉][上住着著眼嘴]|关闭|關閉|合上)');
  static final _negationPrefix = RegExp(
    r'(?:不要|别|別|没有|沒有|没|沒|未|不(?!要|只|但))[^，,。！？!?；;]{0,6}$',
  );
  static final _negatedOnly = RegExp(
    r'(?:不要|别|別|不能|不应|不應)只[^，,。！？!?；;]{0,6}[一单單]',
  );
  static const _openWords = {'open', 'opened', 'opening'};
  static const _closedWords = {'closed', 'closing', 'shut'};

  static bool? _closure(String text) {
    if (_negatedOpen.hasMatch(text)) return true;
    if (_negatedClose.hasMatch(text)) return false;
    final open = _open.hasMatch(text);
    final closed = _close.hasMatch(text);
    return open == closed ? null : closed;
  }

  static final _opposites = [
    (
      positiveQuery: RegExp(r'向左|朝左|左[边邊侧側手脚腳眼]'),
      negativeQuery: RegExp(r'向右|朝右|右[边邊侧側手脚腳眼]'),
      positiveTag: const {'left'},
      negativeTag: const {'right'},
      subject: null,
    ),
    (
      positiveQuery: RegExp(r'上方|上面|上沿|顶端|頂端'),
      negativeQuery: RegExp(r'下方|下面|下沿|底部'),
      positiveTag: const {'above', 'over', 'up', 'top'},
      negativeTag: const {'below', 'under', 'down', 'bottom', 'beneath'},
      subject: null,
    ),
    (
      positiveQuery: RegExp(r'(?:面向|面对|面對|正对|正對|看向)(?:镜头|鏡頭|观众|觀眾|观者|觀者)'),
      negativeQuery: RegExp(
        r'背对|背對|背过身|背過身|从背后|從背後|'
        r'(?:不看|避[开開]|移[开開]|躲[开開])(?:镜头|鏡頭|观众|觀眾|观者|觀者)',
      ),
      positiveTag: const {'viewer'},
      negativeTag: const {'away', 'behind', 'back'},
      subject: null,
    ),
    (
      positiveQuery: RegExp(
        r'长发|長髮|(?:头发|頭髮|发尾|髮尾).{0,4}(?:超过|超過|越过|越過|垂到)[肩胸腰]',
      ),
      negativeQuery: RegExp(r'短发|短髮|剪短(?:头发|頭髮)'),
      positiveTag: const {'long'},
      negativeTag: const {'short'},
      subject: 'hair',
    ),
    (
      positiveQuery: RegExp(r'(?:塞|扎|收)[进進入](?:腰|裤|褲|裙)'),
      negativeQuery: RegExp(r'衣[摆擺角].{0,4}(?:垂|留)在外'),
      positiveTag: const {'tucked'},
      negativeTag: const {'untucked'},
      subject: null,
    ),
  ];

  static List<_Contrast> _detectAxes(String text) {
    final result = <_Contrast>[];
    for (final axis in _opposites) {
      final positive = axis.positiveQuery.allMatches(text);
      final negative = axis.negativeQuery.allMatches(text);
      final wantsPositive =
          positive.any((m) => !_isNegated(text, m)) ||
          negative.any((m) => _isNegated(text, m));
      final wantsNegative =
          negative.any((m) => !_isNegated(text, m)) ||
          positive.any((m) => _isNegated(text, m));
      if (wantsPositive == wantsNegative) continue;
      result.add((
        wanted: wantsPositive ? axis.positiveTag : axis.negativeTag,
        opposite: wantsPositive ? axis.negativeTag : axis.positiveTag,
        subject: axis.subject,
      ));
    }
    return result;
  }

  static bool _isNegated(String text, RegExpMatch match) =>
      _negationPrefix.hasMatch(text.substring(0, match.start));

  static final _postures = [
    (RegExp(r'坐[着著在下]'), const {'sit', 'sitting', 'seated'}),
    (RegExp(r'站[着著在立]'), const {'stand', 'standing'}),
    (RegExp(r'躺[着著在下]'), const {'lying', 'reclining'}),
    (RegExp(r'跪[着著在下]'), const {'kneel', 'kneeling'}),
  ];

  static Set<String>? _detectPosture(String text) {
    final matches = _postures.where(
      (posture) =>
          posture.$1.allMatches(text).any((match) => !_isNegated(text, match)),
    );
    return matches.length == 1 ? matches.first.$2 : null;
  }

  double adjustment(String tag) {
    if (_axes.isEmpty &&
        _posture == null &&
        _closed == null &&
        _quantity == null &&
        !_absence &&
        !_avoidSingle) {
      return 0;
    }
    final words = EnglishWords.tokens(tag).toSet();
    var score = 0.0;
    for (final axis in _axes) {
      if (axis.subject != null && !words.contains(axis.subject)) continue;
      score += _contrast(words, axis.wanted, axis.opposite);
    }
    if (_posture case final posture?) {
      final matches = posture.any(words.contains);
      final conflicts = _postures.any(
        (alternative) =>
            alternative.$2 != posture && alternative.$2.any(words.contains),
      );
      score += _adjust(matches, conflicts);
    }
    if (_closed case final closed?) {
      score += _contrast(
        words,
        closed ? _closedWords : _openWords,
        closed ? _openWords : _closedWords,
      );
    }
    if (_quantity case final quantity?) {
      final (singular, plural) = _bodyParts[quantity.group(2)]!;
      final one = quantity.group(1) == '一' || quantity.group(1) == '单';
      if (words.contains(singular) || words.contains(plural)) {
        final single = words.contains('one') || words.contains('single');
        final multiple =
            !single &&
            (words.contains(plural) ||
                words.contains('two') ||
                words.contains('both'));
        score += one
            ? (multiple ? -.26 : (single ? .07 : 0))
            : (single ? -.26 : (multiple ? .07 : 0));
      }
    }
    if (_absence &&
        words.any(
          (word) =>
              word == 'no' ||
              word == 'without' ||
              word == 'bare' ||
              (word.length > 6 && word.endsWith('less')),
        )) {
      score += .07;
    }
    if (_avoidSingle) {
      score += _contrast(
        words,
        const {'two', 'both', 'multiple'},
        const {'one', 'single', 'solo'},
      );
    }
    return score.clamp(-.48, .14);
  }

  static double _contrast(
    Set<String> words,
    Set<String> wanted,
    Set<String> opposite,
  ) {
    final matches = wanted.any(words.contains);
    final conflicts = opposite.any(words.contains);
    return _adjust(matches, conflicts);
  }

  static double _adjust(bool matches, bool conflicts) =>
      matches == conflicts ? 0 : (matches ? .07 : -.26);
}
