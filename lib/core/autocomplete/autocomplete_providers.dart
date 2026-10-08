import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/services/service_providers.dart';
import '../storage/local_storage_service.dart';
import '../network/network_failure_diagnostics.dart';
import '../network/network_client_provider.dart';
import 'autocomplete_cache_database.dart';
import 'autocomplete_settings.dart';
import 'cooccurrence_completion_source.dart';
import 'completion_models.dart';
import 'completion_orchestrator.dart';
import 'danbooru_completion_source.dart';
import 'fast_tag_service_provider.dart';
import 'lexical/tag_pair_history.dart';

export 'fast_tag_service_provider.dart'
    show
        fastTagServiceProvider,
        tagCatalogRepositoryProvider,
        zhDictionaryServiceProvider;

final autocompleteCacheDatabaseProvider = Provider<AutocompleteCacheDatabase>((
  ref,
) {
  final cache = AutocompleteCacheDatabase();
  unawaited(cache.initialize().then((_) => cache.prune()));
  ref.onDispose(() => unawaited(cache.dispose()));
  return cache;
});

final autocompleteCacheStatisticsProvider =
    FutureProvider.autoDispose<Map<String, int>>((ref) {
      return ref.watch(autocompleteCacheDatabaseProvider).statistics();
    });

final danbooruCompletionSourceProvider = Provider<DanbooruCompletionSource>((
  ref,
) {
  final dio = ref
      .watch(networkClientFactoryProvider)
      .createDio(
        BaseOptions(
          baseUrl: 'https://danbooru.donmai.us',
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 15),
          headers: const {
            'Accept': 'application/json',
            'User-Agent': 'Aaalice-NAI-Launcher/Autocomplete',
          },
        ),
      );
  addNetworkFailureDiagnostics(dio, scope: 'Danbooru autocomplete');
  ref.onDispose(dio.close);
  return DanbooruCompletionSource(
    dio: dio,
    cache: ref.watch(autocompleteCacheDatabaseProvider),
  );
});

class AutocompleteServices {
  const AutocompleteServices({
    required this.localSources,
    required this.dictionaryTranslations,
    required this.llmTranslations,
    required this.danbooru,
    this.tagLookupSources = const [],
    this.libraryAliases,
    this.semanticSource,
    this.supplementalSources = const [],
    this.rankingSignals,
  });

  final List<CompletionSource> localSources;
  final List<CompletionSource> tagLookupSources;
  final TranslationResolver dictionaryTranslations;
  final TranslationResolver llmTranslations;
  final DanbooruCompletionSource danbooru;
  final CompletionSource? libraryAliases;
  final CompletionSource? semanticSource;

  /// Pinyin, approximate, cross-lingual and spelling fallbacks.
  final List<SupplementalCompletionSource> supplementalSources;

  /// Context and habit boosts.
  final CompletionRankingSignals? rankingSignals;

  CompletionOrchestrator createOrchestrator() => CompletionOrchestrator(
    localSources: localSources,
    tagLookupSources: tagLookupSources,
    dictionaryTranslations: dictionaryTranslations,
    llmTranslations: llmTranslations,
    danbooru: danbooru,
    libraryAliases: libraryAliases,
    semanticSource: semanticSource,
    supplementalSources: supplementalSources,
    rankingSignals: rankingSignals,
  );
}

/// Device-local record of tags written next to each other; never synced.
final tagPairHistoryProvider = Provider<TagPairHistory>(
  (ref) => TagPairHistory(ref.read(localStorageServiceProvider)),
);

final cooccurrenceCompletionSourceProvider =
    Provider<CooccurrenceCompletionSource>((ref) {
      final dataSource = ref.watch(cooccurrenceDataSourceProvider.future);
      final pairs = ref.watch(tagPairHistoryProvider);
      return CooccurrenceCompletionSource.withLoader(
        () => dataSource,
        catalog: ref.watch(tagCatalogRepositoryProvider),
        // Turning learning off stops using the record but keeps it.
        personalPairs: (context) =>
            ref.read(autocompleteSettingsProvider).pairLearningEnabled
            ? pairs.scores(context)
            : const {},
      );
    });

final autocompleteLocalSourcesProvider = Provider<List<CompletionSource>>((
  ref,
) {
  return <CompletionSource>[
    ref.watch(fastTagServiceProvider),
    ref.watch(cooccurrenceCompletionSourceProvider),
  ];
});
