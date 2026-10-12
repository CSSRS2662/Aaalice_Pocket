import '../utils/alias_parser.dart';
import '../utils/character_prompt_block_parser.dart';
import 'completion_models.dart';

class PromptTokenParser {
  const PromptTokenParser._();

  static final RegExp _weightNumberSuffix = RegExp(r'(?::\s*-?\d+(?:\.\d+)?)$');
  static final RegExp _numericWeightOpening = RegExp(
    r'-?(?:\d+(?:\.\d*)?|\.\d+)::',
  );
  static final RegExp _letterOrDigit = RegExp(r'[a-z0-9]');
  static final RegExp _artistCategoryPrefix = RegExp(
    r'^artist:',
    caseSensitive: false,
  );
  static final RegExp _lineBreak = RegExp(r'[\r\n]');
  static final RegExp _tagSeparator = RegExp(r'[,\n]');
  static final RegExp _tagSeparatorWithSpaces = RegExp(r'[,\n\s]+');
  static final RegExp _syntaxSuffix = RegExp(
    r'^(?::\s*-?\d+(?:\.\d+)?)?(?:[\}\]\)]|::)*',
  );

  /// Written tags sent along with a related tag; with it they make the six
  /// the co-occurrence source reads.
  static const int relatedContextTags = 5;

  static final RegExp _leadingComma = RegExp(r'^\s*,\s*');
  static final RegExp _disabledSpan = RegExp(r'/\*[\s\S]*?\*/');

  static CompletionQuery parse({
    required String text,
    required int cursorPosition,
    required int limit,
    required String locale,
    bool splitOnSpaces = false,
  }) {
    final cursor = cursorPosition.clamp(0, text.length);
    final syntax = CharacterPromptBlockParser.parse(text);
    final negativeBlock = syntax.blockContaining(cursor, contentOnly: true);
    if (syntax.hasNegativeBlock &&
        negativeBlock == null &&
        syntax.blockContaining(cursor) != null) {
      return CompletionQuery(
        fullText: text,
        cursorPosition: cursor,
        token: '',
        replacementRange: TextReplacementRange(start: cursor, end: cursor),
        existingTags: _existingTags(
          syntax,
          token: '',
          splitOnSpaces: splitOnSpaces,
        ),
        limit: limit.clamp(1, CompletionResultLimits.all),
        locale: locale,
      );
    }
    final (isTypingAlias, partialAlias, aliasStart) =
        AliasParser.detectPartialAlias(text, cursor);
    if (isTypingAlias) {
      var replacementEnd = cursor;
      final closingBracket = text.indexOf('>', cursor);
      final nextLineBreak = text.indexOf(_lineBreak, cursor);
      if (closingBracket >= 0 &&
          (nextLineBreak < 0 || closingBracket < nextLineBreak)) {
        replacementEnd = closingBracket + 1;
      }
      return CompletionQuery(
        fullText: text,
        cursorPosition: cursor,
        token: partialAlias.trim().toLowerCase(),
        replacementRange: TextReplacementRange(
          start: aliasStart,
          end: replacementEnd,
        ),
        existingTags: const {},
        limit: limit.clamp(1, CompletionResultLimits.all),
        locale: locale,
        kind: CompletionQueryKind.libraryAlias,
      );
    }

    final lowerBound = negativeBlock?.contentRange.start ?? 0;
    final upperBound = negativeBlock?.contentRange.end ?? text.length;
    var start = cursor.clamp(lowerBound, upperBound);
    var end = start;

    while (start > lowerBound &&
        !_isSeparator(text.codeUnitAt(start - 1), splitOnSpaces)) {
      start--;
    }
    while (end < upperBound &&
        !_isSeparator(text.codeUnitAt(end), splitOnSpaces)) {
      end++;
    }

    final bounds = _tagBounds(text.substring(start, end));
    var replacementStart = start + bounds.start;
    final replacementEnd = start + bounds.end;
    final categoryPrefix = _artistCategoryPrefix.firstMatch(
      text.substring(replacementStart, replacementEnd),
    );
    final categoryFilter = categoryPrefix == null ? null : TagCategory.artist;
    replacementStart += categoryPrefix?.end ?? 0;
    final token = text
        .substring(replacementStart, replacementEnd)
        .trim()
        .replaceAll(' ', '_')
        .toLowerCase();

    final existingTags = _existingTags(
      syntax,
      token: token,
      splitOnSpaces: splitOnSpaces,
    );

    return CompletionQuery(
      fullText: text,
      cursorPosition: cursor,
      token: token,
      replacementRange: TextReplacementRange(
        start: replacementStart,
        end: replacementEnd,
      ),
      existingTags: existingTags,
      limit: limit.clamp(1, CompletionResultLimits.all),
      locale: locale,
      categoryFilter: categoryFilter,
    );
  }

  /// Builds an insertion query for the complete tag under the caret.
  ///
  /// Unlike normal completion this never replaces the source tag. The result
  /// is inserted after its segment, or after the following comma when one is
  /// already present, so weighted NovelAI syntax remains untouched.
  static CompletionQuery? parseRelated({
    required String text,
    required int cursorPosition,
    required int limit,
    required String locale,
    bool splitOnSpaces = false,
  }) {
    final parsed = parse(
      text: text,
      cursorPosition: cursorPosition,
      limit: limit,
      locale: locale,
      splitOnSpaces: splitOnSpaces,
    );
    if (parsed.kind == CompletionQueryKind.libraryAlias) return null;
    if (parsed.token.isEmpty) {
      final before = text
          .substring(0, parsed.replacementRange.start)
          .trimRight();
      if (!before.endsWith(',') && !before.endsWith('\n')) return null;
      final context = contextTags(
        text: text,
        cursorPosition: parsed.replacementRange.start,
        splitOnSpaces: splitOnSpaces,
      );
      final previous = contextTags(
        text: before,
        cursorPosition: before.length,
        max: 1,
        splitOnSpaces: splitOnSpaces,
      ).firstOrNull;
      if (previous == null) return null;
      return parsed.copyWith(
        relatedTag: previous,
        contextTags: context
            .where((tag) => tag != previous)
            .take(relatedContextTags)
            .toList(),
      );
    }
    if (!_isTag(parsed.token)) return null;

    var insertionPosition = parsed.replacementRange.end;
    final syntax = CharacterPromptBlockParser.parse(text);
    final negativeBlock = syntax.blockContaining(
      parsed.cursorPosition,
      contentOnly: true,
    );
    final upperBound = negativeBlock?.contentRange.end ?? text.length;
    while (insertionPosition < upperBound &&
        !_isSeparator(text.codeUnitAt(insertionPosition), splitOnSpaces)) {
      insertionPosition++;
    }
    if (insertionPosition < upperBound &&
        text.codeUnitAt(insertionPosition) == 0x2c) {
      insertionPosition++;
      while (insertionPosition < upperBound &&
          (text.codeUnitAt(insertionPosition) == 0x20 ||
              text.codeUnitAt(insertionPosition) == 0x09)) {
        insertionPosition++;
      }
    }

    return CompletionQuery(
      fullText: text,
      cursorPosition: insertionPosition,
      token: '',
      replacementRange: TextReplacementRange(
        start: insertionPosition,
        end: insertionPosition,
      ),
      existingTags: {...parsed.existingTags, parsed.token},
      limit: parsed.limit,
      locale: parsed.locale,
      relatedTag: parsed.token,
      contextTags: contextTags(
        text: text,
        cursorPosition: parsed.replacementRange.start,
        splitOnSpaces: splitOnSpaces,
      ).where((tag) => tag != parsed.token).take(relatedContextTags).toList(),
    );
  }

  /// Types ", " at [cursorPosition] to end the tag before it, so tags can be
  /// split without an English keyboard. Next to a comma it only moves past
  /// it, never doubling it; with nothing before the caret it does nothing.
  static ({String text, int cursorPosition}) insertSeparator({
    required String text,
    required int cursorPosition,
  }) {
    final caret = cursorPosition.clamp(0, text.length);
    final before = text.substring(0, caret).trimRight();
    final after = text.substring(caret);
    if (before.isEmpty) return (text: text, cursorPosition: caret);
    if (before.endsWith(',')) {
      return (
        text: '$before ${after.trimLeft()}',
        cursorPosition: before.length + 1,
      );
    }
    if (after.trimLeft().startsWith(',')) {
      var end = caret + after.indexOf(',') + 1;
      while (end < text.length && text.codeUnitAt(end) == 0x20) {
        end++;
      }
      return (text: text, cursorPosition: end);
    }
    return (
      text: '$before, ${after.trimLeft()}',
      cursorPosition: before.length + 2,
    );
  }

  /// Whether the caret sits where a new tag would go after earlier ones:
  /// an empty slot following a comma or line break.
  static bool isContinuationSlot({
    required String text,
    required int cursorPosition,
    bool splitOnSpaces = false,
  }) {
    final parsed = parse(
      text: text,
      cursorPosition: cursorPosition,
      limit: 1,
      locale: '',
      splitOnSpaces: splitOnSpaces,
    );
    if (parsed.kind != CompletionQueryKind.tag ||
        parsed.token.isNotEmpty ||
        parsed.categoryFilter != null) {
      return false;
    }
    final before = text.substring(0, parsed.replacementRange.start).trimRight();
    return before.endsWith(',') || (before.isNotEmpty && before.endsWith('\n'));
  }

  /// Tags written around [cursorPosition], nearest first: those before it,
  /// then those after it. Disabled tags and weight syntax are left out.
  static List<String> contextTags({
    required String text,
    required int cursorPosition,
    int max = 6,
    bool splitOnSpaces = false,
  }) {
    final cursor = cursorPosition.clamp(0, text.length);
    final separator = splitOnSpaces ? _tagSeparatorWithSpaces : _tagSeparator;
    List<String> tags(String part) => part
        .replaceAll(_disabledSpan, ',')
        .split(separator)
        .map(_normalizeExistingTag)
        .where(_isTag)
        .toList(growable: false);
    final result = <String>[];
    for (final tag in [
      ...tags(text.substring(0, cursor)).reversed,
      ...tags(text.substring(cursor)),
    ]) {
      if (result.length >= max) break;
      if (!result.contains(tag)) result.add(tag);
    }
    return result;
  }

  /// Returns whether an edit changed the tag fragment at the caret.
  ///
  /// Structural edits around a tag (line breaks, commas, boundary whitespace,
  /// or weight delimiters) must not query an untouched neighboring tag.
  static bool editChangesActiveToken({
    required String previousText,
    required int previousCursorPosition,
    required String currentText,
    required int currentCursorPosition,
    bool splitOnSpaces = false,
  }) {
    if (previousText == currentText) return false;

    final previous = parse(
      text: previousText,
      cursorPosition: previousCursorPosition,
      limit: 1,
      locale: '',
      splitOnSpaces: splitOnSpaces,
    );
    final current = parse(
      text: currentText,
      cursorPosition: currentCursorPosition,
      limit: 1,
      locale: '',
      splitOnSpaces: splitOnSpaces,
    );
    if (current.kind == CompletionQueryKind.tag &&
        current.token.isEmpty &&
        current.categoryFilter == null) {
      return false;
    }

    if (previous.categoryFilter != current.categoryFilter) return true;

    var prefixLength = 0;
    final sharedLength = previousText.length < currentText.length
        ? previousText.length
        : currentText.length;
    while (prefixLength < sharedLength &&
        previousText.codeUnitAt(prefixLength) ==
            currentText.codeUnitAt(prefixLength)) {
      prefixLength++;
    }

    var suffixLength = 0;
    while (suffixLength < previousText.length - prefixLength &&
        suffixLength < currentText.length - prefixLength &&
        previousText.codeUnitAt(previousText.length - suffixLength - 1) ==
            currentText.codeUnitAt(currentText.length - suffixLength - 1)) {
      suffixLength++;
    }
    final previousChangeEnd = previousText.length - suffixLength;
    final currentChangeEnd = currentText.length - suffixLength;
    final removed = previousText.substring(prefixLength, previousChangeEnd);
    final inserted = currentText.substring(prefixLength, currentChangeEnd);
    final changedCodeUnits = [...removed.codeUnits, ...inserted.codeUnits];
    if (changedCodeUnits.every(
      (unit) => unit == 0x2c || unit == 0x0a || unit == 0x0d,
    )) {
      return false;
    }

    final sameActiveToken =
        previous.kind == current.kind &&
        previous.token == current.token &&
        previous.categoryFilter == current.categoryFilter;
    if (sameActiveToken) {
      return !_sameSemanticTags(previousText, currentText, splitOnSpaces);
    }

    final insertedTouchesCurrentToken =
        currentChangeEnd > prefixLength &&
        prefixLength < current.replacementRange.end &&
        currentChangeEnd > current.replacementRange.start;
    if (insertedTouchesCurrentToken) return true;

    final removedTouchesPreviousToken =
        prefixLength < previous.replacementRange.end &&
        previousChangeEnd > previous.replacementRange.start;
    if (!removedTouchesPreviousToken) return false;

    final removedWholePreviousToken =
        prefixLength <= previous.replacementRange.start &&
        previousChangeEnd >= previous.replacementRange.end;
    return !removedWholePreviousToken;
  }

  static ({String text, int cursorPosition}) apply({
    required String text,
    required CompletionQuery query,
    required String canonicalTag,
    required bool autoInsertComma,
    required bool replaceUnderscores,
  }) {
    final tag = query.kind == CompletionQueryKind.libraryAlias
        ? '<$canonicalTag>'
        : replaceUnderscores && !_isEmoticon(canonicalTag)
        ? canonicalTag.replaceAll('_', ' ')
        : canonicalTag;
    final range = query.replacementRange;
    final before = text.substring(0, range.start);
    var after = text.substring(range.end);
    final parsedSyntax = CharacterPromptBlockParser.parse(text);
    final negativeBlock = parsedSyntax.blockContaining(
      range.start,
      contentOnly: true,
    );

    if (query.relatedTag != null && range.start == range.end) {
      final alreadySeparated =
          before.trimRight().endsWith(',') ||
          before.trimRight().endsWith('\n') ||
          before.trimRight().endsWith('\r');
      final prefix = before.isEmpty || alreadySeparated ? '' : ', ';
      final contentAfter = negativeBlock == null
          ? after
          : text.substring(range.end, negativeBlock.contentRange.end);
      final hasFollowingTag = contentAfter.trimLeft().isNotEmpty;
      final suffix = autoInsertComma || hasFollowingTag ? ', ' : '';
      final insertion = '$prefix$tag$suffix';
      final result = '$before$insertion$after';
      return (text: result, cursorPosition: before.length + insertion.length);
    }

    var insertion = tag;
    if (autoInsertComma) {
      final syntaxEnd = negativeBlock == null
          ? after.length
          : (negativeBlock.contentRange.end - range.end).clamp(0, after.length);
      final syntaxSuffix = _syntaxSuffix
          .firstMatch(after.substring(0, syntaxEnd))!
          .group(0)!;
      final contentAfterSyntax = after.substring(syntaxSuffix.length);
      final existingComma = _leadingComma.firstMatch(contentAfterSyntax);
      if (existingComma == null) {
        insertion = '$insertion$syntaxSuffix, ';
        after = contentAfterSyntax;
      } else {
        insertion = '$insertion$syntaxSuffix${existingComma.group(0)}';
        after = contentAfterSyntax.substring(existingComma.end);
      }
    }

    final result = '$before$insertion$after';
    return (text: result, cursorPosition: before.length + insertion.length);
  }

  static bool _sameSemanticTags(
    String previousText,
    String currentText,
    bool splitOnSpaces,
  ) {
    List<String> tags(String text) {
      final parsed = CharacterPromptBlockParser.parse(text);
      final separator = splitOnSpaces ? _tagSeparatorWithSpaces : _tagSeparator;
      return _semanticText(parsed)
          .split(separator)
          .map(_normalizeExistingTag)
          .where((tag) => tag.isNotEmpty)
          .toList(growable: false);
    }

    final previousTags = tags(previousText);
    final currentTags = tags(currentText);
    if (previousTags.length != currentTags.length) return false;
    for (var index = 0; index < previousTags.length; index++) {
      if (previousTags[index] != currentTags[index]) return false;
    }
    return true;
  }

  static bool _isSeparator(int codeUnit, bool splitOnSpaces) =>
      codeUnit == 0x2c ||
      codeUnit == 0x0a ||
      codeUnit == 0x0d ||
      (splitOnSpaces && (codeUnit == 0x20 || codeUnit == 0x09));

  /// Whether the underscores of [tag] draw a face (`>_<`, `^_^`, `o_o`,
  /// `<o>_<o>`) rather than join words: no part of it has two letters.
  static bool _isEmoticon(String tag) => tag
      .split('_')
      .every((part) => _letterOrDigit.allMatches(part).length <= 1);

  /// Whether [tag] can be looked up as a written tag: a fragment of one
  /// letter is not, a one-symbol tag such as `?` is.
  static bool _isTag(String tag) =>
      tag.length >= 2 || (tag.length == 1 && !_letterOrDigit.hasMatch(tag));

  /// Where the tag itself sits inside one separator-delimited [raw] segment:
  /// within the spaces, weight brackets, numeric weight (`1.2::tag::`) and
  /// bracketed weight number (`(tag:1.2)`) around it.
  ///
  /// Tags hold brackets of their own (`tippy_(gochiusa)`, `(o)_(o)`). A
  /// bracket is syntax only when its partner is not inside the tag: the pair
  /// wraps the whole segment, or the partner sits in another segment of a
  /// group. A `)` after `:` or `;` is an emoticon's mouth (`;)`, `>:)`).
  static ({int start, int end}) _tagBounds(String raw) {
    final partner = List<int>.filled(raw.length, -1);
    final open = <int>[];
    for (var index = 0; index < raw.length; index++) {
      final unit = raw.codeUnitAt(index);
      if (_closerOf(unit) != null) {
        open.add(index);
      } else if (open.isNotEmpty &&
          _closerOf(raw.codeUnitAt(open.last)) == unit) {
        partner[index] = open.last;
        partner[open.removeLast()] = index;
      }
    }

    var start = 0;
    var end = raw.length;
    var wrapped = false;
    while (true) {
      final startBefore = start;
      final endBefore = end;
      // As far as the closing brackets at the end could reach.
      var closers = end;
      while (closers > start && _isSpaceOrCloser(raw.codeUnitAt(closers - 1))) {
        closers--;
      }
      while (start < end) {
        final unit = raw.codeUnitAt(start);
        final wraps =
            _closerOf(unit) != null &&
            (partner[start] < 0 || partner[start] >= closers);
        if (!wraps && !_isSpace(unit)) break;
        wrapped |= !_isSpace(unit);
        start++;
      }
      final numeric = _numericWeightOpening.matchAsPrefix(raw, start);
      if (numeric != null && numeric.end <= end) start = numeric.end;
      while (end > start) {
        final unit = raw.codeUnitAt(end - 1);
        final mouth =
            unit == 0x29 &&
            partner[end - 1] < 0 &&
            end - 2 >= start &&
            (raw.codeUnitAt(end - 2) == 0x3a ||
                raw.codeUnitAt(end - 2) == 0x3b);
        final closes = _isCloser(unit) && partner[end - 1] < start && !mouth;
        if (!closes && !_isSpace(unit)) break;
        wrapped |= !_isSpace(unit);
        end--;
      }
      if (end - start > 2 && raw.startsWith('::', end - 2)) end -= 2;
      if (start == startBefore && end == endBefore) break;
    }
    if (wrapped) {
      // A number after a colon is a weight only inside brackets, with a tag
      // before it and at a size weights have: `(reverse:1999)` is a name.
      final number = _weightNumberSuffix.firstMatch(raw.substring(start, end));
      if (number != null &&
          number.start > 0 &&
          (double.tryParse(number.group(0)!.substring(1).trim()) ?? 0).abs() <=
              100) {
        end = start + number.start;
      }
    }
    return (start: start, end: end);
  }

  static int? _closerOf(int opener) => switch (opener) {
    0x28 => 0x29,
    0x5b => 0x5d,
    0x7b => 0x7d,
    _ => null,
  };

  static bool _isCloser(int unit) =>
      unit == 0x29 || unit == 0x5d || unit == 0x7d;

  static bool _isSpace(int unit) =>
      unit == 0x20 || unit == 0x09 || unit == 0x0a || unit == 0x0d;

  static bool _isSpaceOrCloser(int unit) => _isSpace(unit) || _isCloser(unit);

  static String _normalizeExistingTag(String raw) {
    final bounds = _tagBounds(raw);
    return raw
        .substring(bounds.start, bounds.end)
        .replaceFirst(_artistCategoryPrefix, '')
        .trim()
        .replaceAll(' ', '_')
        .toLowerCase();
  }

  static Set<String> _existingTags(
    CharacterPromptBlockParseResult parsed, {
    required String token,
    required bool splitOnSpaces,
  }) {
    final tags = <String>{};
    final separator = splitOnSpaces ? _tagSeparatorWithSpaces : _tagSeparator;
    for (final segment in _semanticText(parsed).split(separator)) {
      final normalized = _normalizeExistingTag(segment);
      if (normalized.isNotEmpty && normalized != token) tags.add(normalized);
    }
    return tags;
  }

  static String _semanticText(CharacterPromptBlockParseResult parsed) => [
    parsed.positivePrompt,
    parsed.negativePrompt,
  ].where((part) => part.isNotEmpty).join(', ');
}
