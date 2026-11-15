import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../utils/app_logger.dart';
import 'autocomplete_settings.dart';
import 'completion_models.dart';
import 'completion_ranker.dart';
import 'danbooru_completion_source.dart';
import 'related_tag_scorer.dart';

class CompletionOrchestrator extends ChangeNotifier {
  CompletionOrchestrator({
    required List<CompletionSource> localSources,
    required TranslationResolver dictionaryTranslations,
    required TranslationResolver llmTranslations,
    required DanbooruCompletionSource danbooru,
    DanbooruCompletionSource? aibooru,
    List<CompletionSource> tagLookupSources = const [],
    CompletionSource? libraryAliases,
    CompletionSource? semanticSource,
    List<SupplementalCompletionSource> supplementalSources = const [],
    CompletionRankingSignals? rankingSignals,
    Future<TagCategory?> Function(String tag)? tagCategory,
    Future<List<CompletionCandidate>> Function(List<CompletionCandidate> rows)?
    foldRenamedTags,
    Duration llmDebounceDuration = const Duration(milliseconds: 400),
  }) : _localSources = localSources,
       _tagLookupSources = tagLookupSources,
       _dictionaryTranslations = dictionaryTranslations,
       _llmTranslations = llmTranslations is ScopedTranslationResolver
           ? llmTranslations.createScope()
           : llmTranslations,
       _danbooru = danbooru,
       _aibooru = aibooru,
       _libraryAliases = libraryAliases,
       _semanticSource = semanticSource,
       _supplementalSources = supplementalSources,
       _rankingSignals = rankingSignals,
       _tagCategory = tagCategory,
       _foldRenamedTags = foldRenamedTags,
       _llmDebounceDuration = llmDebounceDuration;

  final List<CompletionSource> _localSources;
  final List<CompletionSource> _tagLookupSources;
  final TranslationResolver _dictionaryTranslations;
  final TranslationResolver _llmTranslations;
  final DanbooruCompletionSource _danbooru;
  final DanbooruCompletionSource? _aibooru;
  final CompletionSource? _libraryAliases;
  final CompletionSource? _semanticSource;
  final List<SupplementalCompletionSource> _supplementalSources;
  final CompletionRankingSignals? _rankingSignals;

  /// The catalog category of a tag, to hold online related rows to the rule
  /// the local ones follow.
  final Future<TagCategory?> Function(String tag)? _tagCategory;

  /// Moves rows under renamed Danbooru names onto the current tag.
  final Future<List<CompletionCandidate>> Function(
    List<CompletionCandidate> rows,
  )?
  _foldRenamedTags;

  Future<List<CompletionCandidate>> _fold(List<CompletionCandidate> rows) =>
      _foldRenamedTags?.call(rows) ?? Future.value(rows);
  Timer? _semanticDebounce;

  /// Context and habit boosts of the current query, used by every merge.
  Map<String, double> _boosts = const {};
  bool _semanticPending = false;
  bool _supplementPending = false;
  List<CompletionCandidate>? _typedPrimary;
  List<CompletionCandidate> _typedSupplements = const [];
  List<CompletionCandidate> _typedSemantic = const [];
  List<CompletionCandidate> _typedRemote = const [];
  final Duration _llmDebounceDuration;

  CompletionState _state = const CompletionState();
  CompletionState get state => _state;

  Timer? _remoteDebounce;
  Timer? _llmDebounce;
  int _sequence = 0;
  final Set<String> _llmRequested = {};
  List<String> _pendingLlmTags = const [];
  bool _llmInFlight = false;
  bool _disposed = false;

  /// Stops every in-flight completion branch and clears the visible snapshot.
  ///
  /// Closing a popup is an interaction decision, not merely a presentation
  /// change. Invalidating the sequence prevents a delayed local or remote result
  /// from reopening a popup that the user already dismissed.
  void cancel() {
    _semanticDebounce?.cancel();
    _sequence++;
    _cancelPendingLlmTranslation();
    _remoteDebounce?.cancel();
    _cancelRemoteRequests();
    _clearTypedCandidates();
    _emit(const CompletionState());
  }

  void _clearTypedCandidates() {
    _typedPrimary = null;
    _typedSupplements = const [];
    _typedSemantic = const [];
    _typedRemote = const [];
  }

  void _cancelRemoteRequests() {
    _danbooru.cancelPending();
    _aibooru?.cancelPending();
  }

  DanbooruCompletionSource? _remoteSource(OnlineTagProvider provider) =>
      switch (provider) {
        OnlineTagProvider.danbooru => _danbooru,
        OnlineTagProvider.aibooru => _aibooru,
      };

  Future<void> query(
    CompletionQuery query,
    AutocompleteSettings settings, {
    CompletionQuery? relatedFallbackQuery,
  }) async {
    final sequence = ++_sequence;
    _semanticDebounce?.cancel();
    _cancelPendingLlmTranslation();
    _remoteDebounce?.cancel();
    _cancelRemoteRequests();
    _boosts = const {};
    _semanticPending = false;
    _supplementPending = false;
    _clearTypedCandidates();
    final requestedRelatedQuery =
        query.relatedTag != null && query.token.isEmpty;
    if (!settings.enabled ||
        (query.token.isEmpty &&
            query.relatedTag == null &&
            query.categoryFilter == null &&
            query.kind != CompletionQueryKind.libraryAlias) ||
        (requestedRelatedQuery && !settings.relatedTagsEnabled)) {
      _emit(CompletionState(query: query));
      return;
    }

    var effectiveQuery = query;
    if (requestedRelatedQuery &&
        relatedFallbackQuery != null &&
        _tagLookupSources.isNotEmpty) {
      final resolution = await _resolveRelatedTag(relatedFallbackQuery);
      if (!_isCurrent(sequence)) return;
      if (resolution != null) {
        effectiveQuery = resolution.isExact
            ? query.copyWith(relatedTag: resolution.canonicalTag)
            : relatedFallbackQuery;
      }
    }

    final isRelatedQuery =
        effectiveQuery.relatedTag != null && effectiveQuery.token.isEmpty;
    final isLibraryAlias =
        effectiveQuery.kind == CompletionQueryKind.libraryAlias;

    final remoteSource =
        !isLibraryAlias &&
            settings.danbooruEnabled &&
            ((!effectiveQuery.isChinese && effectiveQuery.token.length >= 2) ||
                isRelatedQuery)
        ? _remoteSource(settings.onlineTagProvider)
        : null;
    final canLoadRemote = remoteSource != null;
    _emit(
      CompletionState(
        query: effectiveQuery,
        candidates: const [],
        isLocalLoading: true,
        isRemoteLoading: canLoadRemote,
        remoteProvider: canLoadRemote ? settings.onlineTagProvider : null,
      ),
    );
    final activeLocalSources = isLibraryAlias
        ? [_libraryAliases].whereType<CompletionSource>()
        : _localSources;
    final expandsRelatedResults =
        isRelatedQuery &&
        effectiveQuery.limit > CompletionResultLimits.initialRelatedTags;
    final initialQuery = expandsRelatedResults
        ? effectiveQuery.copyWith(
            limit: CompletionResultLimits.initialRelatedTags,
          )
        : effectiveQuery;
    final isTyped =
        !isLibraryAlias &&
        !isRelatedQuery &&
        effectiveQuery.token.trim().length >= 2;
    final canSupplement = isTyped && _supplementalSources.isNotEmpty;
    final semanticEligible =
        isTyped &&
        effectiveQuery.isChinese &&
        (effectiveQuery.typedCategoryScope?.contains(TagCategory.general) ??
            true) &&
        _semanticSource != null;
    final poolQuery =
        (canSupplement || semanticEligible) &&
            !CompletionResultLimits.isAll(initialQuery.limit)
        ? initialQuery.copyWith(limit: math.max(60, initialQuery.limit))
        : initialQuery;
    final boosts = isLibraryAlias || isRelatedQuery
        ? Future.value(const <String, double>{})
        : _rankingBoosts(effectiveQuery);
    final localResults = await Future.wait(
      activeLocalSources.map((source) async {
        try {
          return _LocalSourceResult(await source.search(poolQuery));
        } catch (error) {
          return _LocalSourceResult(
            const <CompletionCandidate>[],
            error: '${source.runtimeType}: $error',
          );
        }
      }),
    );
    // Library aliases are entry names, not tags.
    final localBatches = await Future.wait(
      localResults.map(
        (result) async => _filterCategory(
          isLibraryAlias ? result.candidates : await _fold(result.candidates),
          effectiveQuery,
        ),
      ),
    );
    final localErrors = localResults
        .map((result) => result.error)
        .whereType<String>()
        .toList(growable: false);
    final resolvedBoosts = await boosts;
    if (!_isCurrent(sequence)) return;
    _boosts = resolvedBoosts;
    var candidates = isLibraryAlias
        ? localBatches
              .expand((batch) => batch)
              .take(effectiveQuery.limit)
              .toList(growable: false)
        : CompletionRanker.mergeAndSort(
            localBatches.expand((batch) => batch),
            query: poolQuery,
            boosts: _boosts,
          );
    final canLoadSemantic =
        semanticEligible &&
        candidates
                .where(
                  (row) =>
                      row.matchKind == CompletionMatchKind.chineseExact ||
                      row.matchKind == CompletionMatchKind.chinesePrefix,
                )
                .take(8)
                .length <
            8;
    if (canSupplement || canLoadSemantic) _typedPrimary = candidates;
    if (poolQuery.limit != initialQuery.limit) {
      candidates = candidates.take(initialQuery.limit).toList(growable: false);
    }
    if (isRelatedQuery) {
      candidates = candidates
          .where((candidate) => !candidate.isExisting)
          .toList(growable: false);
    }
    candidates = await _applyDictionaryTranslations(
      candidates,
      initialQuery,
      sequence,
      settings,
    );
    candidates = await _applyCachedLlmTranslations(
      candidates,
      initialQuery,
      sequence,
      settings,
    );
    if (!_isCurrent(sequence)) return;
    _semanticPending = canLoadSemantic;
    _supplementPending = canSupplement;
    _emit(
      _state.copyWith(
        candidates: candidates,
        isLocalLoading:
            expandsRelatedResults || canLoadSemantic || canSupplement,
        localError: localErrors.isEmpty ? null : localErrors.join('\n'),
        clearLocalError: localErrors.isEmpty,
        isRemoteLoading: canLoadRemote,
      ),
    );
    _scheduleLlmTranslations(initialQuery, sequence, settings);
    if (canSupplement) {
      unawaited(
        _loadSupplements(effectiveQuery, sequence, settings, _typedPrimary!),
      );
    }
    if (canLoadSemantic) {
      _semanticDebounce = Timer(const Duration(milliseconds: 250), () {
        unawaited(_loadSemantic(effectiveQuery, sequence, settings));
      });
    }
    if (expandsRelatedResults) {
      unawaited(_expandRelatedLocalResults(effectiveQuery, settings, sequence));
    }

    if (remoteSource == null) {
      _emit(_state.copyWith(isRemoteLoading: false));
      return;
    }
    _remoteDebounce = Timer(const Duration(milliseconds: 250), () {
      unawaited(_loadRemote(effectiveQuery, sequence, settings, remoteSource));
    });
  }

  Future<void> _loadSemantic(
    CompletionQuery query,
    int sequence,
    AutocompleteSettings settings,
  ) async {
    try {
      var rows = await _semanticSource!.search(query.copyWith(limit: 50));
      if (!_isCurrent(sequence)) return;
      // Use the same current dictionary/locale policy as lexical completion.
      // The frozen index labels describe its corpus, not user translation state.
      rows = await _fold(
        rows.map((row) => row.copyWith(clearTranslation: true)).toList(),
      );
      rows = await _applyDictionaryTranslations(
        rows,
        query,
        sequence,
        settings,
      );
      if (!_isCurrent(sequence)) return;
      _semanticPending = false;
      _typedSemantic = rows;
      _emit(
        _state.copyWith(
          isLocalLoading: _supplementPending,
          candidates: _supplementPending
              ? _state.candidates
              : _rankTyped(query),
        ),
      );
    } catch (error) {
      if (_isCurrent(sequence)) {
        _semanticPending = false;
        final existing = _state.localError;
        _emit(
          _state.copyWith(
            isLocalLoading: _supplementPending,
            localError: [
              if (existing != null) existing,
              'E5: $error',
            ].join('\n'),
          ),
        );
      }
    }
  }

  Future<Map<String, double>> _rankingBoosts(CompletionQuery query) async {
    final signals = _rankingSignals;
    if (signals == null) return const {};
    try {
      return await signals.boosts(query);
    } catch (_) {
      return const {};
    }
  }

  /// The literal results are displayed while the lexical fallbacks run.
  Future<void> _loadSupplements(
    CompletionQuery query,
    int sequence,
    AutocompleteSettings settings,
    List<CompletionCandidate> primary,
  ) async {
    final errors = <String>[];
    final batches = await Future.wait(
      _supplementalSources.map((source) async {
        try {
          return await source.supplement(query, primary);
        } catch (error) {
          errors.add('${source.runtimeType}: $error');
          return const <CompletionCandidate>[];
        }
      }),
    );
    if (!_isCurrent(sequence)) return;
    var rows = await _fold(
      batches.expand((batch) => batch).toList(growable: false),
    );
    rows = await _applyDictionaryTranslations(rows, query, sequence, settings);
    rows = await _applyCachedLlmTranslations(rows, query, sequence, settings);
    if (!_isCurrent(sequence)) return;
    _supplementPending = false;
    _typedSupplements = rows;
    final existing = _state.localError;
    _emit(
      _state.copyWith(
        isLocalLoading: _semanticPending,
        candidates: _rankTyped(query),
        localError: errors.isEmpty
            ? existing
            : [if (existing != null) existing, ...errors].join('\n'),
      ),
    );
    if (rows.isNotEmpty) _scheduleLlmTranslations(query, sequence, settings);
  }

  List<CompletionCandidate> _rankTyped(CompletionQuery query) {
    final local = CompletionRanker.mergeAndSort(
      [
        ..._typedPrimary!,
        ..._typedSupplements,
        if (!_supplementPending) ..._typedSemantic,
      ],
      query: query,
      boosts: _boosts,
    );
    return _preserveCurrentTranslationState(
      _typedRemote.isEmpty
          ? local
          : _mergeRemoteWithoutReordering(
              local: local,
              remote: _typedRemote,
              query: query,
            ),
    );
  }

  Future<_RelatedTagResolution?> _resolveRelatedTag(
    CompletionQuery fallbackQuery,
  ) async {
    // Prefix matches must stay in normal completion so an incomplete tag is
    // never guessed as the source of a related-tag query.
    final lookupQuery = fallbackQuery.copyWith(
      limit: math.min(fallbackQuery.limit, 20),
    );
    final results = await Future.wait(
      _tagLookupSources.map((source) async {
        try {
          return await source.search(lookupQuery);
        } catch (_) {
          return const <CompletionCandidate>[];
        }
      }),
    );
    final candidates = CompletionRanker.mergeAndSort(
      results.expand((batch) => batch),
      query: lookupQuery,
    );
    if (candidates.isEmpty) return null;

    // Written tags lead a typed list; the word being resolved is still the
    // best match among the unwritten ones first.
    final ordered = [
      ...candidates.where((candidate) => !candidate.isExisting),
      ...candidates.where((candidate) => candidate.isExisting),
    ];
    final exact = ordered.where(_isExactTagMatch).firstOrNull;
    return _RelatedTagResolution(
      canonicalTag: (exact ?? ordered.first).canonicalTag,
      isExact: exact != null,
    );
  }

  static bool _isExactTagMatch(CompletionCandidate candidate) =>
      switch (candidate.matchKind) {
        CompletionMatchKind.englishExact ||
        CompletionMatchKind.aliasExact ||
        CompletionMatchKind.chineseExact => true,
        _ => false,
      };

  Future<void> _expandRelatedLocalResults(
    CompletionQuery query,
    AutocompleteSettings settings,
    int sequence,
  ) async {
    final localResults = await Future.wait(
      _localSources.map((source) async {
        try {
          return _LocalSourceResult(await source.search(query));
        } catch (error) {
          return _LocalSourceResult(
            const <CompletionCandidate>[],
            error: '${source.runtimeType}: $error',
          );
        }
      }),
    );
    if (!_isCurrent(sequence)) return;

    final localErrors = localResults
        .map((result) => result.error)
        .whereType<String>()
        .toList(growable: false);
    var expanded = CompletionRanker.mergeAndSort(
      localResults.expand(
        (result) => _filterCategory(result.candidates, query),
      ),
      query: query,
    ).where((candidate) => !candidate.isExisting).toList(growable: false);
    expanded = await _applyDictionaryTranslations(
      expanded,
      query,
      sequence,
      settings,
    );
    expanded = await _applyCachedLlmTranslations(
      expanded,
      query,
      sequence,
      settings,
    );
    if (!_isCurrent(sequence)) return;

    final merged = CompletionRanker.mergeAndSort(
      [..._state.candidates, ...expanded],
      query: query,
    ).where((candidate) => !candidate.isExisting).toList(growable: false);
    _emit(
      _state.copyWith(
        candidates: merged,
        isLocalLoading: false,
        localError: localErrors.isEmpty ? null : localErrors.join('\n'),
        clearLocalError: localErrors.isEmpty,
      ),
    );
  }

  Future<List<CompletionCandidate>> _applyDictionaryTranslations(
    List<CompletionCandidate> candidates,
    CompletionQuery query,
    int sequence,
    AutocompleteSettings settings,
  ) async {
    if (query.kind == CompletionQueryKind.libraryAlias ||
        !settings.showTranslations ||
        candidates.isEmpty) {
      return candidates;
    }
    final missing = candidates
        .where((candidate) => candidate.translation?.isNotEmpty != true)
        .map((candidate) => candidate.canonicalTag)
        .toList();
    Map<String, String> translations;
    try {
      translations = await _dictionaryTranslations.resolve(
        missing,
        locale: query.locale,
      );
    } catch (_) {
      return candidates;
    }
    if (!_isCurrent(sequence) || translations.isEmpty) return candidates;
    return candidates
        .map(
          (candidate) => translations[candidate.canonicalTag] == null
              ? candidate
              : candidate.copyWith(
                  translation: translations[candidate.canonicalTag],
                  sources: {
                    ...candidate.sources,
                    CompletionSourceKind.zhDictionary,
                  },
                ),
        )
        .toList(growable: false);
  }

  Future<List<CompletionCandidate>> _applyCachedLlmTranslations(
    List<CompletionCandidate> candidates,
    CompletionQuery query,
    int sequence,
    AutocompleteSettings settings,
  ) async {
    final resolver = _llmTranslations;
    if (resolver is! CachedTranslationResolver ||
        query.kind == CompletionQueryKind.libraryAlias ||
        !settings.showTranslations ||
        !settings.llmTranslationEnabled ||
        !query.locale.toLowerCase().startsWith('zh') ||
        candidates.isEmpty) {
      return candidates;
    }
    final missing = candidates
        .where((candidate) => candidate.translation?.isNotEmpty != true)
        .map((candidate) => candidate.canonicalTag)
        .toList(growable: false);
    if (missing.isEmpty) return candidates;
    Map<String, String> translations;
    try {
      translations = await resolver.resolveCached(
        missing,
        locale: query.locale,
      );
    } catch (_) {
      return candidates;
    }
    if (!_isCurrent(sequence) || translations.isEmpty) return candidates;
    return candidates
        .map((candidate) {
          final translation = translations[candidate.canonicalTag];
          return translation == null
              ? candidate
              : candidate.copyWith(
                  translation: translation,
                  sources: {...candidate.sources, CompletionSourceKind.ai},
                );
        })
        .toList(growable: false);
  }

  Future<void> _loadRemote(
    CompletionQuery query,
    int sequence,
    AutocompleteSettings settings,
    DanbooruCompletionSource primary,
  ) async {
    final related = query.relatedTag != null && query.token.isEmpty;
    var (remote, remoteError) = await _requestRemote(primary, query);
    if (!_isCurrent(sequence)) return;
    final alternate = settings.onlineTagFallback
        ? _remoteSource(settings.onlineTagProvider.alternate)
        : null;
    if (alternate != null &&
        remoteError != null &&
        remote.isEmpty &&
        _state.candidates.isEmpty) {
      _emit(
        _state.copyWith(remoteProvider: settings.onlineTagProvider.alternate),
      );
      (remote, remoteError) = await _requestRemote(alternate, query);
      if (!_isCurrent(sequence)) return;
    }
    if (_typedPrimary != null) {
      remote = await _applyDictionaryTranslations(
        remote,
        query,
        sequence,
        settings,
      );
      remote = await _applyCachedLlmTranslations(
        remote,
        query,
        sequence,
        settings,
      );
      if (!_isCurrent(sequence)) return;
      _typedRemote = remote;
      _emit(
        _state.copyWith(
          candidates: _rankTyped(query),
          isRemoteLoading: false,
          remoteError: remoteError,
          clearRemoteError: remoteError == null,
        ),
      );
      _scheduleLlmTranslations(query, sequence, settings);
      return;
    }
    var merged = _mergeRemoteWithoutReordering(
      local: _state.candidates,
      remote: remote,
      query: query,
    );
    if (related) {
      merged = merged
          .where((candidate) => !candidate.isExisting)
          .toList(growable: false);
    }
    merged = await _applyDictionaryTranslations(
      merged,
      query,
      sequence,
      settings,
    );
    merged = await _applyCachedLlmTranslations(
      merged,
      query,
      sequence,
      settings,
    );
    if (!_isCurrent(sequence)) return;
    merged = _preserveCurrentTranslationState(merged);
    _emit(
      _state.copyWith(
        candidates: merged,
        isRemoteLoading: false,
        remoteError: remoteError,
        clearRemoteError: remoteError == null,
      ),
    );
    _scheduleLlmTranslations(query, sequence, settings);
  }

  Future<(List<CompletionCandidate>, CompletionRemoteError?)> _requestRemote(
    DanbooruCompletionSource source,
    CompletionQuery query,
  ) async {
    try {
      final related = query.relatedTag;
      final rows = related != null && query.token.isEmpty
          ? await source.relatedTags(related, limit: query.limit)
          : await source.search(query);
      final error = source.lastError;
      final filtered = _filterCategory(rows, query);
      return (
        related != null && query.token.isEmpty
            ? await _relatedRowsToSuggest(filtered, query)
            : filtered,
        error,
      );
    } catch (error, stack) {
      AppLogger.e(
        '${source.provider.label} completion failed',
        error,
        stack,
        'Autocomplete',
      );
      return (
        const <CompletionCandidate>[],
        const CompletionRemoteError(CompletionRemoteErrorKind.unexpected),
      );
    }
  }

  List<CompletionCandidate> _preserveCurrentTranslationState(
    List<CompletionCandidate> candidates,
  ) {
    final currentByTag = {
      for (final candidate in _state.candidates)
        candidate.canonicalTag: candidate,
    };
    return candidates
        .map((candidate) {
          final current = currentByTag[candidate.canonicalTag];
          if (current == null) return candidate;
          final currentTranslation = current.translation;
          return candidate.copyWith(
            translation: currentTranslation?.isNotEmpty == true
                ? currentTranslation
                : candidate.translation,
            sources: {...candidate.sources, ...current.sources},
            isTranslating: current.isTranslating,
          );
        })
        .toList(growable: false);
  }

  List<CompletionCandidate> _mergeRemoteWithoutReordering({
    required List<CompletionCandidate> local,
    required List<CompletionCandidate> remote,
    required CompletionQuery query,
  }) {
    final localIds = local.map((candidate) => candidate.stableId).toSet();
    final mergedPool = CompletionRanker.mergeAndSort(
      [...local, ...remote],
      query: query,
      limit: local.length + remote.length,
      boosts: _boosts,
    );
    final byId = {
      for (final candidate in mergedPool) candidate.stableId: candidate,
    };
    final stableLocal = local
        .map((candidate) => byId[candidate.stableId] ?? candidate)
        .toList(growable: false);
    final onlineOnly = mergedPool
        .where((candidate) => !localIds.contains(candidate.stableId))
        .toList(growable: false);

    // Local rows stay in place while online-only tags are appended. Reserving
    // extra rows is the only way to expose new Danbooru tags without replacing
    // the already-visible local list or moving the keyboard selection.
    if (CompletionResultLimits.isAll(query.limit)) {
      return [...stableLocal, ...onlineOnly];
    }
    final baselineGap = math.max(0, query.limit - stableLocal.length);
    final supplementLimit = ((query.limit + 1) ~/ 2).clamp(1, 50);
    final remoteSlots = math.max(baselineGap, supplementLimit);
    return [...stableLocal, ...onlineOnly.take(remoteSlots)];
  }

  /// Online related rows follow the local rule when the user chose no
  /// categories: no names after a general tag.
  Future<List<CompletionCandidate>> _relatedRowsToSuggest(
    List<CompletionCandidate> rows,
    CompletionQuery query,
  ) async {
    final categoryOf = _tagCategory;
    if (categoryOf == null ||
        rows.isEmpty ||
        query.relatedCategories.isNotEmpty) {
      return rows;
    }
    final TagCategory? anchor;
    try {
      anchor = await categoryOf(query.relatedTag!);
    } catch (_) {
      return rows;
    }
    if (anchor != null && !RelatedTagScorer.isGeneral(anchor)) return rows;
    return rows
        .where((row) => RelatedTagScorer.isGeneral(row.category))
        .toList(growable: false);
  }

  static List<CompletionCandidate> _filterCategory(
    List<CompletionCandidate> candidates,
    CompletionQuery query,
  ) {
    final related = query.relatedTag != null && query.token.isEmpty;
    // Typed rows keep to the prefix filter and the chosen categories; related
    // rows to the categories the user narrowed them to.
    final scope = related
        ? (query.relatedCategories.isEmpty ? null : query.relatedCategories)
        : query.typedCategoryScope;
    if (scope == null) return candidates;
    return candidates
        .where((candidate) => scope.contains(candidate.category))
        .toList(growable: false);
  }

  void _scheduleLlmTranslations(
    CompletionQuery query,
    int sequence,
    AutocompleteSettings settings,
  ) {
    if (_llmRequested.isNotEmpty ||
        _llmInFlight ||
        _pendingLlmTags.isNotEmpty) {
      return;
    }
    _queueVisibleLlmTranslations(
      query: query,
      sequence: sequence,
      settings: settings,
      candidates: _state.candidates.take(8),
      delay: _llmDebounceDuration,
    );
  }

  /// Requests translations only for the latest settled viewport.
  ///
  /// Callers debounce scroll movement before invoking this method. Replacing
  /// the pending batch prevents a fast scroll from billing for every row that
  /// merely passed through the viewport.
  void translateVisibleCandidates({
    required int firstIndex,
    required int lastIndex,
    required AutocompleteSettings settings,
  }) {
    final query = _state.query;
    if (query == null || _state.candidates.isEmpty) return;
    final first = firstIndex.clamp(0, _state.candidates.length - 1);
    final last = lastIndex.clamp(first, _state.candidates.length - 1);
    _queueVisibleLlmTranslations(
      query: query,
      sequence: _sequence,
      settings: settings,
      candidates: _state.candidates.getRange(first, last + 1),
      delay: Duration.zero,
    );
  }

  void _queueVisibleLlmTranslations({
    required CompletionQuery query,
    required int sequence,
    required AutocompleteSettings settings,
    required Iterable<CompletionCandidate> candidates,
    required Duration delay,
  }) {
    if (query.kind == CompletionQueryKind.libraryAlias ||
        !settings.showTranslations ||
        !settings.llmTranslationEnabled ||
        !query.locale.toLowerCase().startsWith('zh')) {
      return;
    }
    _llmDebounce?.cancel();
    _llmDebounce = null;
    _pendingLlmTags = candidates
        .where(
          (candidate) =>
              candidate.translation?.isNotEmpty != true &&
              !candidate.isTranslating &&
              !_llmRequested.contains(candidate.canonicalTag),
        )
        .map((candidate) => candidate.canonicalTag)
        .take(8)
        .toList(growable: false);
    if (_pendingLlmTags.isEmpty || _llmInFlight) return;
    _llmDebounce = Timer(delay, () {
      _llmDebounce = null;
      _startPendingLlmTranslation(query, sequence);
    });
  }

  void _startPendingLlmTranslation(CompletionQuery query, int sequence) {
    if (!_isCurrent(sequence) || _llmInFlight) return;
    final missing = _pendingLlmTags
        .where(
          (tag) =>
              !_llmRequested.contains(tag) &&
              _state.candidates.any(
                (candidate) =>
                    candidate.canonicalTag == tag &&
                    candidate.translation?.isNotEmpty != true,
              ),
        )
        .take(8)
        .toList(growable: false);
    _pendingLlmTags = const [];
    if (missing.isEmpty) return;
    _llmInFlight = true;
    _llmRequested.addAll(missing);
    final missingSet = missing.toSet();
    _emit(
      _state.copyWith(
        candidates: _state.candidates
            .map(
              (candidate) => missingSet.contains(candidate.canonicalTag)
                  ? candidate.copyWith(isTranslating: true)
                  : candidate,
            )
            .toList(growable: false),
      ),
    );
    unawaited(_resolveLlm(missing, query, sequence));
  }

  Future<void> _resolveLlm(
    List<String> missing,
    CompletionQuery query,
    int sequence,
  ) async {
    try {
      final translations = await _llmTranslations.resolve(
        missing,
        locale: query.locale,
      );
      if (!_isCurrent(sequence)) return;
      _emit(
        _state.copyWith(
          candidates: _state.candidates
              .map((candidate) {
                if (!missing.contains(candidate.canonicalTag)) return candidate;
                final translation = translations[candidate.canonicalTag];
                return candidate.copyWith(
                  translation: translation,
                  isTranslating: false,
                  sources: translation == null
                      ? candidate.sources
                      : {...candidate.sources, CompletionSourceKind.ai},
                );
              })
              .toList(growable: false),
          clearTranslationError: true,
        ),
      );
    } catch (error) {
      if (!_isCurrent(sequence)) return;
      _emit(
        _state.copyWith(
          candidates: _state.candidates
              .map(
                (candidate) => missing.contains(candidate.canonicalTag)
                    ? candidate.copyWith(isTranslating: false)
                    : candidate,
              )
              .toList(growable: false),
          translationError: error.toString(),
        ),
      );
    } finally {
      if (_isCurrent(sequence)) {
        _llmInFlight = false;
        _startPendingLlmTranslation(query, sequence);
      }
    }
  }

  bool _isCurrent(int sequence) => !_disposed && sequence == _sequence;

  void _cancelPendingLlmTranslation() {
    _llmDebounce?.cancel();
    _llmDebounce = null;
    _llmRequested.clear();
    _pendingLlmTags = const [];
    _llmInFlight = false;
    final resolver = _llmTranslations;
    if (resolver is CancellableTranslationResolver) {
      resolver.cancelPending();
    }
  }

  void _emit(CompletionState value) {
    if (_disposed) return;
    _state = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _semanticDebounce?.cancel();
    _disposed = true;
    _sequence++;
    _cancelPendingLlmTranslation();
    _remoteDebounce?.cancel();
    _cancelRemoteRequests();
    super.dispose();
  }
}

class _LocalSourceResult {
  const _LocalSourceResult(this.candidates, {this.error});

  final List<CompletionCandidate> candidates;
  final String? error;
}

class _RelatedTagResolution {
  const _RelatedTagResolution({
    required this.canonicalTag,
    required this.isExact,
  });

  final String canonicalTag;
  final bool isExact;
}
