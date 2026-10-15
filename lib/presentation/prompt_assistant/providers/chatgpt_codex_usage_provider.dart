import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/app_logger.dart';
import '../../../data/models/prompt_assistant/prompt_assistant_models.dart';
import '../../../data/services/chatgpt_codex/chatgpt_codex_credentials.dart';
import '../../../data/services/chatgpt_codex/chatgpt_codex_usage.dart';
import '../services/prompt_assistant_service.dart';
import 'chatgpt_codex_account_provider.dart';

/// Latest Codex quota per ChatGPT account id. Kept in memory only: it goes
/// stale within hours and belongs to the account, not the device settings.
final chatGptCodexUsageProvider =
    StateNotifierProvider<
      ChatGptCodexUsageNotifier,
      Map<String, ChatGptCodexUsage>
    >((ref) => ChatGptCodexUsageNotifier(ref));

class ChatGptCodexUsageNotifier
    extends StateNotifier<Map<String, ChatGptCodexUsage>> {
  ChatGptCodexUsageNotifier(this._ref, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now,
      super(const {});

  /// The usage endpoint is read at most this often per account.
  static const refreshInterval = Duration(seconds: 60);

  final Ref _ref;
  final DateTime Function() _clock;
  final Map<String, DateTime> _fetchedAt = {};
  final Map<String, Future<void>> _fetching = {};

  void record(String accountId, ChatGptCodexUsage usage) {
    state = {...state, accountId: usage.withDetailsFrom(state[accountId])};
  }

  /// Reads `GET /wham/usage` for the account behind [provider], unless it
  /// was read within [refreshInterval]; a user's explicit refresh passes
  /// [force].
  Future<void> refresh(ProviderConfig provider, {bool force = false}) async {
    final accounts = _ref.read(chatGptCodexAccountProvider.notifier);
    final account = await accounts.load(provider.id);
    if (account == null || account.needsLogin) return;
    final accountId = account.accountId;
    final last = _fetchedAt[accountId];
    if (!force &&
        last != null &&
        _clock().difference(last) < refreshInterval) {
      return;
    }
    await (_fetching[accountId] ??= _fetch(
      provider,
      accountId,
    ).whenComplete(() {
      // remove() returns this future; whenComplete must not wait on it.
      _fetching.remove(accountId);
    }));
  }

  Future<void> _fetch(ProviderConfig provider, String accountId) async {
    final token = await _ref
        .read(chatGptCodexAccountProvider.notifier)
        .accessToken(provider.id);
    if (token == null) return;
    _fetchedAt[accountId] = _clock();
    try {
      final response = await _ref
          .read(promptAssistantDioProvider)
          .get<dynamic>(
            '${ChatGptCodexAuth.backendBase(provider.baseUrl)}/wham/usage',
            options: Options(
              headers: {
                'Authorization': 'Bearer $token',
                'chatgpt-account-id': accountId,
                'originator': ChatGptCodexAuth.originator,
                'User-Agent': ChatGptCodexAuth.userAgent,
                'accept': 'application/json',
              },
              receiveTimeout: const Duration(seconds: 20),
            ),
          );
      final usage = ChatGptCodexUsage.fromJson(response.data, _clock());
      if (usage != null && mounted) {
        state = {...state, accountId: usage};
      }
    } on DioException catch (error) {
      AppLogger.w(
        'ChatGPT usage read failed: HTTP ${error.response?.statusCode} '
            '${error.type.name}',
        'ChatGptCodex',
      );
    }
  }
}
