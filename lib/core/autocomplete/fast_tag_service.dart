import 'ame_zh_lexicon.dart';
import 'completion_models.dart';
import 'completion_ranker.dart';
import 'tag_catalog_repository.dart';
import 'tag_rename_folder.dart';
import 'zh_dictionary_service.dart';

/// Reusable local tag search and translation boundary.
///
/// Consumers do not need to know which bundled or optional database owns a
/// result. Search and translation precedence live here so autocomplete,
/// prompt tools, and future modules share the same behavior.
class FastTagService implements CompletionSource, TranslationResolver {
  const FastTagService({
    required TagCatalogRepository catalog,
    required ZhDictionaryService dictionary,
    TranslationResolver? fallbackTranslations,
    AmeZhLexicon? lexicon,
    TagRenameFolder? renames,
  }) : _catalog = catalog,
       _dictionary = dictionary,
       _fallbackTranslations = fallbackTranslations,
       _lexicon = lexicon,
       _renames = renames;

  final TagCatalogRepository _catalog;
  final ZhDictionaryService _dictionary;
  final TranslationResolver? _fallbackTranslations;
  final AmeZhLexicon? _lexicon;
  final TagRenameFolder? _renames;

  @override
  Future<List<CompletionCandidate>> search(CompletionQuery query) async {
    final bundledBatches = await Future.wait([
      _catalog.search(query),
      _catalog.searchTranslations(query),
    ]);
    final dictionaryResults = await _searchOptionalDictionary(query);
    final lexiconResults = await _searchLexicon(query);
    final rows = [
      ...bundledBatches.expand((batch) => batch),
      ...dictionaryResults,
      ...lexiconResults,
    ];
    // Old names merge into the current tag before ranking.
    return CompletionRanker.mergeAndSort(
      await _renames?.fold(rows) ?? rows,
      query: query,
    );
  }

  /// Resolves reviewed corrections before ffdkj and bundled gap-fillers after
  /// it. A later ffdkj update can therefore replace an ordinary fallback but
  /// cannot reintroduce a confirmed mistranslation. The bundled AME lexicon
  /// only fills what every other source left empty. A renamed tag that is
  /// still untranslated borrows the label of its old name.
  @override
  Future<Map<String, String>> resolve(
    List<String> canonicalTags, {
    required String locale,
  }) async {
    if (!locale.toLowerCase().startsWith('zh') || canonicalTags.isEmpty) {
      return const {};
    }
    final normalized = canonicalTags
        .map((tag) => tag.trim().toLowerCase().replaceAll(' ', '_'))
        .where((tag) => tag.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (normalized.isEmpty) return const {};
    final resolved = await _resolveNames(normalized, locale: locale);
    final missing = normalized.where((tag) => !resolved.containsKey(tag));
    final renames = _renames;
    if (renames == null || missing.isEmpty) return resolved;
    final formerNames = await renames.formerNames(missing);
    if (formerNames.isEmpty) return resolved;
    final labels = await _resolveNames(
      formerNames.values.expand((names) => names).toSet().toList(),
      locale: locale,
    );
    for (final MapEntry(key: tag, value: names) in formerNames.entries) {
      for (final name in names) {
        final label = labels[name];
        if (label != null) {
          resolved[tag] = label;
          break;
        }
      }
    }
    return resolved;
  }

  Future<Map<String, String>> _resolveNames(
    List<String> normalized, {
    required String locale,
  }) async {
    final overrides = await _catalog.resolveTranslations(
      normalized,
      mode: BundledTranslationMode.override,
    );
    final dictionaryTags = normalized
        .where((tag) => !overrides.containsKey(tag))
        .toList(growable: false);
    final dictionary = await _resolveOptionalDictionary(
      dictionaryTags,
      locale: locale,
    );
    final missingTags = dictionaryTags
        .where((tag) => !dictionary.containsKey(tag))
        .toList(growable: false);
    final fallbacks = await _catalog.resolveTranslations(
      missingTags,
      mode: BundledTranslationMode.missing,
    );
    final resolved = {...overrides, ...dictionary, ...fallbacks};
    final remaining = normalized
        .where((tag) => !resolved.containsKey(tag))
        .toList(growable: false);
    if (remaining.isNotEmpty && _fallbackTranslations != null) {
      try {
        final labels = await _fallbackTranslations.resolve(
          remaining,
          locale: locale,
        );
        for (final tag in remaining) {
          final label = labels[tag]?.trim();
          if (label != null && label.isNotEmpty) resolved[tag] = label;
        }
      } catch (_) {
        // Optional corpus labels must not break installed dictionary results.
      }
    }
    final unresolved = normalized
        .where((tag) => !resolved.containsKey(tag))
        .toList(growable: false);
    if (unresolved.isNotEmpty && _lexicon != null) {
      try {
        final labels = await _lexicon.resolve(unresolved, locale: locale);
        for (final tag in unresolved) {
          final label = labels[tag]?.trim();
          if (label != null && label.isNotEmpty) resolved[tag] = label;
        }
      } catch (_) {
        // The bundled lexicon is a last resort and never blocks other labels.
      }
    }
    return resolved;
  }

  Future<Map<String, String>> resolveFuzzy(List<String> canonicalTags) async {
    try {
      return await _dictionary.resolveFuzzy(canonicalTags);
    } catch (_) {
      return const {};
    }
  }

  Future<List<CompletionCandidate>> _searchOptionalDictionary(
    CompletionQuery query,
  ) async {
    try {
      return await _dictionary.search(query);
    } catch (_) {
      // ffdkj is user-installed optional data; bundled completion must remain
      // available when that database is absent, outdated, or damaged.
      return const [];
    }
  }

  Future<List<CompletionCandidate>> _searchLexicon(
    CompletionQuery query,
  ) async {
    final lexicon = _lexicon;
    if (lexicon == null) return const [];
    try {
      return await lexicon.search(query);
    } catch (_) {
      // Missing or damaged bundled lexicon only removes extra Chinese keys.
      return const [];
    }
  }

  Future<Map<String, String>> _resolveOptionalDictionary(
    List<String> canonicalTags, {
    required String locale,
  }) async {
    try {
      return await _dictionary.resolve(canonicalTags, locale: locale);
    } catch (_) {
      // The bundled fallback is independently usable without ffdkj.
      return const {};
    }
  }
}
