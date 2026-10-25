import 'package:flutter/foundation.dart';

/// Which prompt of the image a tag is shown in.
enum DetailTagSide { positive, negative }

/// Tags picked in the image details to copy together.
///
/// Picking starts with a long press on a tag or from the copy menu; taps
/// then pick and drop tags until they are copied or picking is left.
/// Dropping the last pick keeps picking on, so it can start empty. Tags are
/// copied in prompt order, whatever order they were picked in.
class DetailTagPicks extends ChangeNotifier {
  final _picked = <DetailTagSide, Map<int, String>>{};
  var _active = false;

  bool get active => _active;

  int get count => _picked.values.fold(0, (sum, side) => sum + side.length);

  int countOf(DetailTagSide side) => _picked[side]?.length ?? 0;

  bool isPicked(DetailTagSide side, int index) =>
      _picked[side]?.containsKey(index) ?? false;

  /// Turns picking on with nothing picked.
  void start() {
    if (_active) return;
    _active = true;
    notifyListeners();
  }

  /// Picks or drops the tag at [index] of [side]; turns picking on first.
  void toggle(DetailTagSide side, int index, String tag) {
    _active = true;
    final picks = _picked.putIfAbsent(side, () => {});
    if (picks.remove(index) == null) picks[index] = tag;
    notifyListeners();
  }

  /// Picks every one of [tags] of [side], or drops them all.
  void setAll(DetailTagSide side, List<String> tags, {required bool picked}) {
    _active = true;
    _picked[side] = picked ? Map.of(tags.asMap()) : {};
    notifyListeners();
  }

  /// Leaves picking and drops every pick.
  void end() {
    if (!_active && _picked.isEmpty) return;
    _active = false;
    _picked.clear();
    notifyListeners();
  }

  /// The picks as clipboard text; see [formatPickedTags].
  String get text => formatPickedTags(
    positive: _inPromptOrder(DetailTagSide.positive),
    negative: _inPromptOrder(DetailTagSide.negative),
  );

  List<String> _inPromptOrder(DetailTagSide side) {
    final picks = _picked[side];
    if (picks == null || picks.isEmpty) return const [];
    final indexes = picks.keys.toList()..sort();
    return [for (final index in indexes) picks[index]!];
  }
}

/// Picked tags of one prompt as a plain comma list. Tags of both prompts
/// use the two-line form of the full tag copy, so a paste keeps them apart.
String formatPickedTags({
  required List<String> positive,
  required List<String> negative,
}) {
  final positiveText = positive.join(', ');
  final negativeText = negative.join(', ');
  if (negative.isEmpty) return positiveText;
  if (positive.isEmpty) return negativeText;
  return 'positive: $positiveText\nnegative: $negativeText';
}
