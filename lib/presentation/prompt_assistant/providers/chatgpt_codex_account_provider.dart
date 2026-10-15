import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/secure_storage_service.dart';
import '../../../core/utils/app_logger.dart';
import '../../../data/services/chatgpt_codex/chatgpt_codex_credentials.dart';
import '../../../data/services/chatgpt_codex/chatgpt_codex_oauth_client.dart';
import '../services/prompt_assistant_service.dart';

final chatGptCodexOAuthClientProvider = Provider<ChatGptCodexOAuthClient>(
  (ref) => ChatGptCodexOAuthClient(ref.watch(promptAssistantDioProvider)),
);

/// What the UI may show about a ChatGPT login; tokens never leave the
/// notifier.
class ChatGptCodexAccount {
  const ChatGptCodexAccount({
    required this.accountId,
    required this.expiresAt,
    this.email,
    this.planType,
    this.needsLogin = false,
  });

  final String accountId;
  final DateTime expiresAt;
  final String? email;
  final String? planType;

  /// The refresh token was rejected; the user has to sign in again.
  final bool needsLogin;
}

/// ChatGPT logins keyed by provider id.
final chatGptCodexAccountProvider =
    StateNotifierProvider<
      ChatGptCodexAccountNotifier,
      Map<String, ChatGptCodexAccount>
    >((ref) => ChatGptCodexAccountNotifier(ref));

class ChatGptCodexAccountNotifier
    extends StateNotifier<Map<String, ChatGptCodexAccount>> {
  ChatGptCodexAccountNotifier(this._ref, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now,
      super(const {});

  final Ref _ref;
  final DateTime Function() _clock;
  final Map<String, ChatGptCodexCredentials> _credentials = {};
  final Map<String, Future<void>> _loading = {};
  final Map<String, Future<ChatGptCodexCredentials?>> _refreshing = {};

  SecureStorageService get _secure => _ref.read(secureStorageServiceProvider);

  /// Reads the stored login once per provider.
  Future<ChatGptCodexAccount?> load(String providerId) async {
    await (_loading[providerId] ??= _read(providerId));
    return state[providerId];
  }

  Future<void> _read(String providerId) async {
    final raw = await _secure.getChatGptCodexCredentials(providerId);
    if (raw == null || raw.isEmpty) return;
    ChatGptCodexCredentials? credentials;
    try {
      credentials = ChatGptCodexCredentials.fromJson(jsonDecode(raw));
    } on FormatException {
      credentials = null;
    }
    if (credentials == null) return;
    _credentials[providerId] = credentials;
    _publish(providerId, credentials);
  }

  Future<void> saveLogin(
    String providerId,
    ChatGptCodexCredentials credentials,
  ) async {
    await _secure.saveChatGptCodexCredentials(
      providerId,
      jsonEncode(credentials.toJson()),
    );
    _loading[providerId] = Future.value();
    _credentials[providerId] = credentials;
    _publish(providerId, credentials);
  }

  Future<void> logout(String providerId) async {
    await _secure.deleteChatGptCodexCredentials(providerId);
    _loading[providerId] = Future.value();
    _credentials.remove(providerId);
    if (state.containsKey(providerId)) {
      state = {...state}..remove(providerId);
    }
  }

  /// A usable access token, refreshed when close to expiry; null when not
  /// signed in or the login was revoked.
  Future<String?> accessToken(String providerId) async {
    await load(providerId);
    final credentials = _credentials[providerId];
    if (credentials == null) return null;
    if (state[providerId]?.needsLogin ?? false) return null;
    if (!credentials.needsRefresh(_clock())) return credentials.access;
    final refreshed = await (_refreshing[providerId] ??= _refresh(
      providerId,
      credentials,
    ).whenComplete(() {
      // A block body: remove() returns this very future, which
      // whenComplete would otherwise wait on forever.
      _refreshing.remove(providerId);
    }));
    return refreshed?.access;
  }

  Future<ChatGptCodexCredentials?> _refresh(
    String providerId,
    ChatGptCodexCredentials credentials,
  ) async {
    try {
      final next = await _ref
          .read(chatGptCodexOAuthClientProvider)
          .refresh(credentials.refresh);
      await saveLogin(providerId, next);
      return next;
    } on ChatGptCodexAuthException catch (error) {
      AppLogger.w('ChatGPT token refresh rejected: $error', 'ChatGptCodex');
      if (!credentials.isExpired(_clock())) return credentials;
      state = {
        ...state,
        providerId: ChatGptCodexAccount(
          accountId: credentials.accountId,
          expiresAt: credentials.expiresAt,
          email: credentials.email,
          planType: credentials.planType,
          needsLogin: true,
        ),
      };
      return null;
    } on DioException catch (error) {
      // A network failure is not a revoked login: keep the token while it
      // still works and surface the failure otherwise.
      if (!credentials.isExpired(_clock())) return credentials;
      throw StateError('ChatGPT token refresh failed: ${error.message}');
    }
  }

  void _publish(String providerId, ChatGptCodexCredentials credentials) {
    state = {
      ...state,
      providerId: ChatGptCodexAccount(
        accountId: credentials.accountId,
        expiresAt: credentials.expiresAt,
        email: credentials.email,
        planType: credentials.planType,
      ),
    };
  }
}
