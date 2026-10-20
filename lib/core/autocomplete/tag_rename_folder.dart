import 'dart:async';

import 'completion_models.dart';
import 'tag_catalog_repository.dart';

/// Shows a renamed Danbooru tag under its current name.
///
/// Dictionaries and the semantic pack still know many tags by their old
/// names (`black_shoes`, now `black_footwear`); listing both splits one tag
/// into two rows and puts the stale one, which still carries a translation,
/// first. Folded rows keep how they matched, name the old tag as the matched
/// alias and leave the translation to the shared resolver of the new name.
///
/// Completion never waits for the rename map: until it has loaded, rows pass
/// through unchanged while it loads in the background.
class TagRenameFolder {
  TagRenameFolder(this._renamedTags);

  final Future<Map<String, TagCatalogRecord>> Function() _renamedTags;
  Map<String, TagCatalogRecord>? _renamed;
  Map<String, List<String>> _formerNames = const {};
  Future<void>? _loading;

  /// Loads the rename map; a failed load is retried on a later call.
  Future<void> ready() => _loading ??= _renamedTags().then<void>(
    (renamed) {
      final inverted = <String, List<String>>{};
      for (final MapEntry(key: old, value: current) in renamed.entries) {
        (inverted[current.canonicalTag.toLowerCase()] ??= []).add(old);
      }
      for (final names in inverted.values) {
        names.sort();
      }
      _formerNames = inverted;
      _renamed = renamed;
    },
    onError: (Object _) {
      _loading = null;
    },
  );

  Map<String, TagCatalogRecord>? _loaded() {
    final renamed = _renamed;
    if (renamed == null) unawaited(ready());
    return renamed;
  }

  Future<List<CompletionCandidate>> fold(
    List<CompletionCandidate> candidates,
  ) async {
    final renamed = _loaded();
    if (renamed == null ||
        !candidates.any((row) => renamed.containsKey(row.stableId))) {
      return candidates;
    }
    return [
      for (final row in candidates)
        if (renamed[row.stableId] case final current?)
          CompletionCandidate(
            canonicalTag: current.canonicalTag,
            category: current.category,
            postCount: current.postCount,
            matchKind: row.matchKind,
            sources: row.sources,
            aliases: row.aliases,
            matchedAlias: row.matchedAlias ?? row.canonicalTag,
            isExisting: row.isExisting,
            isTranslating: row.isTranslating,
            relatedScore: row.relatedScore,
            cooccurrenceCount: row.cooccurrenceCount,
            semanticScore: row.semanticScore,
            matchHint: row.matchHint,
            matchQuality: row.matchQuality,
          )
        else
          row,
    ];
  }

  /// The old names of each of [tags], for borrowing their translations.
  Future<Map<String, List<String>>> formerNames(Iterable<String> tags) async {
    if (_loaded() == null) return const {};
    return {
      for (final tag in tags)
        if (_formerNames[tag.toLowerCase()] case final names?)
          tag.toLowerCase(): names,
    };
  }
}
