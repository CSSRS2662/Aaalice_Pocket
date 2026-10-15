import 'dart:async';

import '../../../core/autocomplete/autocomplete_providers.dart';
import '../../../core/autocomplete/autocomplete_settings.dart';
import '../../../core/autocomplete/completion_models.dart';
import '../../../core/autocomplete/prompt_token_parser.dart';

class AgentTagLookupResult {
  const AgentTagLookupResult(
    this.candidates, {
    this.error,
    this.partial = false,
    this.relatedAnchor,
  });

  final List<CompletionCandidate> candidates;

  /// The tag related suggestions were scored for, after resolving a Chinese
  /// word or alias; null when the anchor matched no tag exactly, in which
  /// case [candidates] are search results for it instead.
  final String? relatedAnchor;

  /// Failures of individual local sources; the other sources still answered.
  final String? error;

  /// The slow sources (E5 meaning search) had not finished in time.
  final bool partial;
}

/// Looks tags up exactly as the prompt editor's suggestions do, minus the
/// network: the catalog, pinyin and Ziranma, Chinese labels, meaning search,
/// and related tags scored against the other tags with category filters.
class AgentTagLookup {
  AgentTagLookup({
    required AutocompleteServices services,
    required AutocompleteSettings settings,
    this.timeout = const Duration(seconds: 10),
  }) : _services = services,
       // The agent reads local data only, whatever the editor is set to.
       _settings = settings.copyWith(
         enabled: true,
         danbooruEnabled: false,
         llmTranslationEnabled: false,
         relatedTagsEnabled: true,
         showTranslations: true,
       );

  final AutocompleteServices _services;
  final AutocompleteSettings _settings;
  final Duration timeout;

  static const _locale = 'zh';

  /// Tags matching [term]: English, Chinese, pinyin or a description.
  Future<AgentTagLookupResult> search(String term, {required int limit}) {
    final text = term.trim();
    return _run(
      PromptTokenParser.parse(
        text: text,
        cursorPosition: text.length,
        limit: limit,
        locale: _locale,
      ),
    );
  }

  /// Tags that go with [tags] taken together. The first tag is the anchor and
  /// may be Chinese or an alias; the rest weigh the ranking. [categories]
  /// narrows the suggestions as the editor's related filter does.
  Future<AgentTagLookupResult> related(
    List<String> tags, {
    required int limit,
    Set<TagCategory> categories = const {},
  }) {
    final normalized = [
      for (final tag in tags)
        if (tag.trim().isNotEmpty) tag.trim().toLowerCase().replaceAll(' ', '_'),
    ];
    final text = normalized.join(', ');
    final anchor = normalized.first;
    return _run(
      CompletionQuery(
        fullText: text,
        cursorPosition: text.length,
        token: '',
        replacementRange: TextReplacementRange(
          start: text.length,
          end: text.length,
        ),
        existingTags: normalized.toSet(),
        limit: limit,
        locale: _locale,
        relatedTag: anchor,
        contextTags: normalized.skip(1).take(6).toList(growable: false),
        relatedCategories: categories,
      ),
      // Resolves an anchor written in Chinese or as an alias.
      relatedFallback: PromptTokenParser.parse(
        text: anchor,
        cursorPosition: anchor.length,
        limit: limit,
        locale: _locale,
      ),
    );
  }

  Future<AgentTagLookupResult> _run(
    CompletionQuery query, {
    CompletionQuery? relatedFallback,
  }) async {
    final orchestrator = _services.createOrchestrator();
    final settled = Completer<void>();
    var querying = false;
    void onChange() {
      if (!querying || settled.isCompleted) return;
      if (_isSettled(orchestrator.state)) settled.complete();
    }

    orchestrator.addListener(onChange);
    try {
      querying = true;
      await orchestrator.query(
        query,
        _settings,
        relatedFallbackQuery: relatedFallback,
      );
      if (_isSettled(orchestrator.state) && !settled.isCompleted) {
        settled.complete();
      }
      var partial = false;
      await settled.future.timeout(timeout, onTimeout: () => partial = true);
      final state = orchestrator.state;
      return AgentTagLookupResult(
        state.candidates
            .where((candidate) => !candidate.isExisting)
            .take(query.limit)
            .toList(growable: false),
        error: state.localError,
        partial: partial,
        relatedAnchor: state.query?.token.isEmpty ?? false
            ? state.query?.relatedTag
            : null,
      );
    } finally {
      orchestrator.removeListener(onChange);
      orchestrator.dispose();
    }
  }

  static bool _isSettled(CompletionState state) =>
      !state.isLocalLoading && !state.isRemoteLoading;
}
