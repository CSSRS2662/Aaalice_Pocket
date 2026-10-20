import 'package:flutter/foundation.dart';

/// Lets an enclosing editor consume Back before ending the active edit, and
/// ask for related tags without a keyboard shortcut.
class AutocompleteOverlayHandle extends ChangeNotifier {
  AutocompleteOverlayHandle({this.hostHandlesBack = false});

  /// The editor passes Back to [dismiss] itself while the popup [isOpen],
  /// so the popup adds no Back handler of its own (one Back would otherwise
  /// leave multi-select and close the popup at once).
  final bool hostHandlesBack;

  VoidCallback? _dismiss;
  VoidCallback? _showRelated;
  void Function({required bool quiet})? _suggestNext;
  bool get isOpen => _dismiss != null;

  /// Whether an autocomplete wrapper can show related tags right now.
  bool get canShowRelated => _showRelated != null;

  /// Shows tags related to the one at the caret, like Ctrl+Shift+Space.
  void showRelated() => _showRelated?.call();

  void bindRelated(VoidCallback show) => _showRelated = show;

  void unbindRelated(VoidCallback show) {
    if (_showRelated == show) _showRelated = null;
  }

  /// Suggests what to write next from the tags around the caret (the 联想
  /// key), showing the popup even when nothing fits.
  void suggestNext() => _suggestNext?.call(quiet: false);

  /// The same after the editor typed a separator itself (the 分词 key); the
  /// popup only opens when something fits.
  void continueAfterSeparator() => _suggestNext?.call(quiet: true);

  void bindSuggestNext(void Function({required bool quiet}) suggest) =>
      _suggestNext = suggest;

  void unbindSuggestNext(void Function({required bool quiet}) suggest) {
    if (_suggestNext == suggest) _suggestNext = null;
  }

  void attach(VoidCallback dismiss) {
    _dismiss = dismiss;
    notifyListeners();
  }

  void detach(VoidCallback dismiss) {
    if (_dismiss != dismiss) return;
    _dismiss = null;
    notifyListeners();
  }

  /// Steps the popup back: leaves multi-select first, then closes it.
  void dismiss() => _dismiss?.call();
}
