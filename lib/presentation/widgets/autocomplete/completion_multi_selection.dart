import 'package:flutter/foundation.dart';

import '../../../core/autocomplete/completion_models.dart';

/// The popup's multi-select mode: the tags picked so far, in the order they
/// were picked, which is the order they are written in.
///
/// A long press on a tile starts it; taps then pick and drop tiles until
/// the picks are inserted together or the mode is left. Dropping the last
/// pick leaves it as well. Picks survive re-queries while the user keeps
/// typing, so tags can be gathered from several searches.
class CompletionMultiSelection extends ChangeNotifier {
  List<CompletionCandidate>? _picked;
  CompletionQueryKind? _kind;

  bool get active => _picked != null;

  /// The query kind the picks were made for; they are written in its syntax.
  CompletionQueryKind? get kind => _kind;

  List<CompletionCandidate> get picked => List.unmodifiable(_picked ?? []);

  int get count => _picked?.length ?? 0;

  /// The picked tiles, by [CompletionCandidate.stableId]; null outside the
  /// mode.
  Set<String>? get pickedIds => _picked == null
      ? null
      : {for (final candidate in _picked!) candidate.stableId};

  bool isPicked(CompletionCandidate candidate) =>
      _picked?.any((value) => value.stableId == candidate.stableId) ?? false;

  /// Starts the mode with [first] picked.
  void start(CompletionCandidate first, CompletionQueryKind kind) {
    if (first.isExisting) return;
    _picked = [first];
    _kind = kind;
    notifyListeners();
  }

  /// Picks or drops [candidate]; dropping the last pick leaves the mode.
  void toggle(CompletionCandidate candidate) {
    final picked = _picked;
    if (picked == null || candidate.isExisting) return;
    final index = picked.indexWhere(
      (value) => value.stableId == candidate.stableId,
    );
    if (index < 0) {
      picked.add(candidate);
    } else {
      picked.removeAt(index);
      if (picked.isEmpty) {
        _picked = null;
        _kind = null;
      }
    }
    notifyListeners();
  }

  void end() {
    if (_picked == null) return;
    _picked = null;
    _kind = null;
    notifyListeners();
  }
}
