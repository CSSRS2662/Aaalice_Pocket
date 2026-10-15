import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/agent/agent_types.dart';
import '../../../core/autocomplete/autocomplete_settings.dart';
import '../../../core/autocomplete/completion_models.dart';
import '../../../core/utils/app_logger.dart';
import '../../providers/autocomplete_services_provider.dart';
import 'agent_tag_lookup.dart';
import 'defined_agent_tool.dart';

/// 标签数据工具集：与提示词输入框的联想走同一套本地流程（内置标签库、拼音与
/// 自然码双拼、中文译名、语义搜索、按上下文打分的相关标签），不联网。
///
/// - `search_tags`：统一入口，mode = search（英文、中文、拼音或描述查标签）/
///   suggest（相关标签，可按角色、作品、一般分类筛选）；translate 与 search
///   相同，保留给旧调用；`queries` 批量查询，每项独立成组。
class TagToolbox {
  TagToolbox(this._ref, {AgentTagLookup Function()? lookup})
    : _lookupOverride = lookup;

  final Ref _ref;
  final AgentTagLookup Function()? _lookupOverride;

  /// Related tags can be narrowed to these, as in the editor's filter.
  static const _categoryNames = {
    'character': TagCategory.character,
    'copyright': TagCategory.copyright,
    'general': TagCategory.general,
  };

  static const int _maxBatchQueries = 10;
  static const Set<String> _modes = {'auto', 'search', 'translate', 'suggest'};

  List<AgentTool> tools() {
    return [
      DefinedAgentTool(
        name: 'search_tags',
        label: 'Search Tags',
        description:
            'Look up danbooru tags in the built-in databases as a '
            'reference, with the same local search the prompt editor uses. '
            'Modes: "search" (default) finds tags for an English tag or '
            'alias, a Chinese word, pinyin, or a short description, and '
            'returns each tag with its category, post count and Chinese '
            'name; "translate" is the same as search. "suggest" recommends '
            'tags that go with the given tags taken together: the first tag '
            'is the anchor (Chinese or an alias is resolved), the others '
            'weigh the ranking; pass "categories" to keep only characters, '
            'series (copyright) or general tags, for example the characters '
            'of a series. Requirements: pass either '
            '"query" (one term) or "queries" (up to $_maxBatchQueries terms '
            'resolved independently, each returned as its own group); '
            '"limit" 1-30 (default 10) caps every group. In search and '
            'translate a comma-separated term is split into independent '
            'lookups, so batch several tags in one call instead of guessing; '
            'in suggest the commas stay one context group. Results are '
            'evidence for verifying canonical spellings, aliases and category. '
            'For a named character, use this after researching its identity '
            'and before inspecting gallery tags. Do not guess canonical tags '
            'from model memory. Natural-language prompts remain supported.',
        parameters: const {
          'type': 'object',
          'properties': {
            'query': {
              'type': 'string',
              'description':
                  'Single search term, merged with "queries" when both are '
                  'given. For suggest mode: comma-separated existing tags '
                  'used together as one context. For more than one term use '
                  'queries in a single call.',
            },
            'queries': {
              'type': 'array',
              'items': {'type': 'string'},
              'maxItems': _maxBatchQueries,
              'description':
                  'Batch form, up to $_maxBatchQueries terms. Each entry is '
                  'looked up independently and returned as its own group, so '
                  'prefer this over repeating the call per tag.',
            },
            'mode': {
              'type': 'string',
              'enum': ['auto', 'search', 'translate', 'suggest'],
              'description':
                  'auto (default) and translate search; suggest lists '
                  'related tags.',
            },
            'categories': {
              'type': 'array',
              'items': {
                'type': 'string',
                'enum': ['character', 'copyright', 'general'],
              },
              'description':
                  'suggest only: keep related tags of these categories.',
            },
            'limit': {
              'type': 'integer',
              'minimum': 1,
              'maximum': 30,
              'description': 'Max results per group, 1-30. Default 10.',
            },
          },
        },
        executeFn: (_, params) => _searchTags(params),
      ),
    ];
  }

  // -------------------------------------------------------------------------
  // search_tags
  // -------------------------------------------------------------------------

  Future<AgentToolResult> _searchTags(Map<String, dynamic> args) async {
    final mode = (args['mode'] as String?)?.trim() ?? 'auto';
    if (!_modes.contains(mode)) {
      return agentToolError(
        'invalid_mode',
        'Unknown mode "$mode". Use auto / search / translate / suggest.',
      );
    }
    final limit = ((args['limit'] as num?)?.toInt() ?? 10).clamp(1, 30);
    final categories = <TagCategory>{};
    if (args['categories'] case final Object raw?) {
      if (raw is! List) {
        return agentToolError(
          'invalid_categories',
          'Parameter "categories" must be an array.',
        );
      }
      for (final name in raw) {
        final category = _categoryNames[name];
        if (category == null) {
          return agentToolError(
            'invalid_categories',
            'Unknown category "$name". Use character / copyright / general.',
          );
        }
        categories.add(category);
      }
    }

    final rawQueries = args['queries'];
    final batched = rawQueries != null;
    // 两个参数同时给出时合并，避免静默丢弃其中一个。
    final terms = <String>[if (args['query'] case final String single) single];
    if (batched) {
      if (rawQueries is! List) {
        return agentToolError(
          'invalid_queries',
          'Parameter "queries" must be an array of search terms.',
        );
      }
      for (final entry in rawQueries) {
        if (entry is! String) {
          return agentToolError(
            'invalid_queries',
            'Parameter "queries" must contain only strings.',
          );
        }
        terms.add(entry);
      }
    }

    final requests = _expand(terms, mode);
    if (requests.isEmpty) {
      return agentToolError(
        'missing_query',
        batched
            ? 'Parameter "queries" needs at least one search term.'
            : 'Parameter "query" is required.',
      );
    }
    if (requests.length > _maxBatchQueries) {
      return agentToolError(
        'too_many_queries',
        'At most $_maxBatchQueries terms per call, got ${requests.length}. '
            'Split the remainder into another call.',
      );
    }

    // 串行执行：底层 catalog / 共现服务都是懒初始化，并发首调会重复 initialize。
    final lookup = _lookupOverride?.call() ?? _createLookup();
    final outcomes = <_TagQueryOutcome>[];
    for (final request in requests) {
      outcomes.add(await _run(lookup, request, limit, categories));
    }

    if (!batched && requests.length == 1) {
      final only = outcomes.single;
      if (only.errorCode != null) {
        return agentToolError(only.errorCode!, only.errorMessage!);
      }
      return agentToolJsonResult({
        'ok': true,
        if (only.anchor != null) 'anchor': only.anchor,
        'results': only.results,
        if (only.note != null) 'note': only.note,
      });
    }
    final unmatched = [
      for (var index = 0; index < requests.length; index++)
        if (outcomes[index].results.isEmpty) requests[index].term,
    ];
    return agentToolJsonResult({
      'ok': true,
      'groups': [
        for (var index = 0; index < requests.length; index++)
          {
            'query': requests[index].term,
            'mode': requests[index].mode,
            if (outcomes[index].anchor != null) 'anchor': outcomes[index].anchor,
            'results': outcomes[index].results,
            if (outcomes[index].note != null) 'note': outcomes[index].note,
            if (outcomes[index].errorCode != null) ...{
              'error': outcomes[index].errorCode,
              'message': outcomes[index].errorMessage,
            },
          },
      ],
      // 不叫 result_count：该名字在 web_search 等工具里表示分页总数。
      'returned_count': outcomes.fold<int>(
        0,
        (total, outcome) => total + outcome.results.length,
      ),
      // 空组只在组内可见，顶层汇总一次避免整体摘要看起来全部命中。
      if (unmatched.isNotEmpty)
        'note': 'No results for: ${unmatched.join(', ')}.',
    });
  }

  /// 展开成实际执行的查询：suggest 的逗号是一组上下文，其余模式按逗号拆分。
  static List<_TagQuery> _expand(List<String> terms, String mode) {
    final requests = <_TagQuery>[];
    for (final term in terms) {
      if (mode == 'suggest') {
        final trimmed = term.trim();
        if (trimmed.isNotEmpty) requests.add(_TagQuery(trimmed, 'suggest'));
        continue;
      }
      for (final part in term.split(',')) {
        final trimmed = part.trim();
        if (trimmed.isEmpty) continue;
        requests.add(_TagQuery(trimmed, _resolveMode(mode, trimmed)));
      }
    }
    return requests;
  }

  /// One local search serves English, Chinese and pinyin alike.
  static String _resolveMode(String requested, String term) =>
      requested == 'suggest' ? 'suggest' : 'search';

  AgentTagLookup _createLookup() => AgentTagLookup(
    services: _ref.read(autocompleteServicesProvider),
    settings: _ref.read(autocompleteSettingsProvider),
  );

  Future<_TagQueryOutcome> _run(
    AgentTagLookup lookup,
    _TagQuery request,
    int limit,
    Set<TagCategory> categories,
  ) async {
    final suggest = request.mode == 'suggest';
    try {
      final AgentTagLookupResult result;
      if (suggest) {
        final tags = [
          for (final part in request.term.split(','))
            if (part.trim().isNotEmpty) part.trim(),
        ];
        if (tags.isEmpty) {
          return const _TagQueryOutcome(
            errorCode: 'invalid_query',
            errorMessage: 'Parameter "query" needs at least one tag.',
          );
        }
        result = await lookup.related(
          tags,
          limit: limit,
          categories: categories,
        );
      } else {
        result = await lookup.search(request.term, limit: limit);
      }
      return _TagQueryOutcome(
        results: [
          for (final candidate in result.candidates)
            _candidateJson(candidate, related: suggest),
        ],
        note: _note(request, result, suggest: suggest),
        anchor: suggest ? result.relatedAnchor : null,
      );
    } catch (e) {
      AppLogger.w('search_tags(${request.mode}) failed: $e', 'AgentChat');
      return _TagQueryOutcome(
        errorCode: suggest ? 'tag_suggestion_failed' : 'tag_search_failed',
        errorMessage: 'Tag lookup failed: $e',
      );
    }
  }

  static Map<String, dynamic> _candidateJson(
    CompletionCandidate candidate, {
    required bool related,
  }) => {
    'tag': candidate.canonicalTag,
    'category': candidate.category.name,
    'post_count': candidate.postCount,
    if (candidate.translation case final chinese? when chinese.isNotEmpty)
      'chinese': chinese,
    if (candidate.matchedAlias case final alias?) 'matched_alias': alias,
    // How a non-literal row matched, so the model can weigh it.
    if (_looseMatches.contains(candidate.matchKind))
      'match': candidate.matchKind.name,
    if (related && candidate.cooccurrenceCount != null)
      'cooccurrence': candidate.cooccurrenceCount,
  };

  static const _looseMatches = {
    CompletionMatchKind.fullText,
    CompletionMatchKind.homophone,
    CompletionMatchKind.spellCorrected,
    CompletionMatchKind.englishVariant,
    CompletionMatchKind.pinyin,
    CompletionMatchKind.shuangpin,
    CompletionMatchKind.crossLingual,
    CompletionMatchKind.approximate,
    CompletionMatchKind.fuzzyPinyin,
    CompletionMatchKind.pinyinInitials,
  };

  static String? _note(
    _TagQuery request,
    AgentTagLookupResult result, {
    required bool suggest,
  }) {
    if (suggest && result.relatedAnchor == null) {
      return 'The first tag of "${request.term}" is not an exact tag, so '
          'these are search results for it. Call suggest again with one of '
          'them first.';
    }
    if (result.candidates.isNotEmpty) {
      return result.partial
          ? 'Meaning search did not finish in time; results may be incomplete.'
          : null;
    }
    if (suggest) {
      return 'No related tags for "${request.term}". The co-occurrence data '
          'pack may still be downloading, or the tag is too rare to have '
          'related data.';
    }
    return 'No catalog match for "${request.term}".';
  }
}

class _TagQuery {
  const _TagQuery(this.term, this.mode);

  final String term;
  final String mode;
}

/// errorCode 非空表示这一项失败，批量时其余项仍照常返回。
class _TagQueryOutcome {
  const _TagQueryOutcome({
    this.results = const [],
    this.note,
    this.errorCode,
    this.errorMessage,
    this.anchor,
  });

  /// The canonical tag suggestions were scored for.
  final String? anchor;

  final List<Map<String, dynamic>> results;
  final String? note;
  final String? errorCode;
  final String? errorMessage;
}
