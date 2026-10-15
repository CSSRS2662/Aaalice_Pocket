import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/cloud_sync/oauth/loopback_oauth_client.dart';
import '../../../../core/cloud_sync/oauth/oauth_pkce.dart';
import '../../../../data/services/chatgpt_codex/chatgpt_codex_callback_server.dart';
import '../../../../data/services/chatgpt_codex/chatgpt_codex_credentials.dart';
import '../../../../data/services/chatgpt_codex/chatgpt_codex_oauth_client.dart';

enum ChatGptCodexLoginMethod { deviceCode, browser }

sealed class ChatGptCodexLoginPhase {
  const ChatGptCodexLoginPhase();
}

class ChatGptCodexLoginChoosing extends ChatGptCodexLoginPhase {
  const ChatGptCodexLoginChoosing();
}

class ChatGptCodexLoginStarting extends ChatGptCodexLoginPhase {
  const ChatGptCodexLoginStarting();
}

/// Waiting for the user to enter [userCode] on the verification page.
class ChatGptCodexLoginDeviceCode extends ChatGptCodexLoginPhase {
  const ChatGptCodexLoginDeviceCode(this.userCode);

  final String userCode;
}

/// Waiting for the browser redirect, or for the user to paste it.
class ChatGptCodexLoginBrowser extends ChatGptCodexLoginPhase {
  const ChatGptCodexLoginBrowser({required this.url, required this.listening});

  final Uri url;

  /// False when port 1455 was taken: only a pasted address can finish.
  final bool listening;
}

class ChatGptCodexLoginFinishing extends ChatGptCodexLoginPhase {
  const ChatGptCodexLoginFinishing();
}

class ChatGptCodexLoginDone extends ChatGptCodexLoginPhase {
  const ChatGptCodexLoginDone(this.credentials);

  final ChatGptCodexCredentials credentials;
}

class ChatGptCodexLoginFailed extends ChatGptCodexLoginPhase {
  const ChatGptCodexLoginFailed(this.kind, this.message);

  final ChatGptCodexAuthFailure kind;
  final String message;
}

typedef ChatGptCodexCallbackServerStarter =
    Future<ChatGptCodexCallbackServer?> Function(String state);

/// Runs one ChatGPT login, device code or browser, following Pi's
/// `openaiCodexOAuth.login`; [onSignedIn] stores the result.
class ChatGptCodexLoginController extends ChangeNotifier {
  ChatGptCodexLoginController({
    required ChatGptCodexOAuthClient client,
    required Future<void> Function(ChatGptCodexCredentials) onSignedIn,
    OAuthBrowserLauncher browser = const SystemOAuthBrowserLauncher(),
    ChatGptCodexCallbackServerStarter? startServer,
  }) : _client = client,
       _onSignedIn = onSignedIn,
       _browser = browser,
       _startServer =
           startServer ??
           ((state) => ChatGptCodexCallbackServer.start(state: state));

  final ChatGptCodexOAuthClient _client;
  final Future<void> Function(ChatGptCodexCredentials) _onSignedIn;
  final OAuthBrowserLauncher _browser;
  final ChatGptCodexCallbackServerStarter _startServer;

  ChatGptCodexLoginPhase _phase = const ChatGptCodexLoginChoosing();
  CancelToken? _cancelToken;
  ChatGptCodexCallbackServer? _server;
  ChatGptCodexBrowserAuthorization? _authorization;
  Completer<String?>? _pasted;
  bool _disposed = false;

  ChatGptCodexLoginPhase get phase => _phase;

  Future<void> start(ChatGptCodexLoginMethod method) async {
    _reset();
    final cancelToken = _cancelToken = CancelToken();
    _set(const ChatGptCodexLoginStarting());
    try {
      final credentials = switch (method) {
        ChatGptCodexLoginMethod.deviceCode => await _deviceCode(cancelToken),
        ChatGptCodexLoginMethod.browser => await _browserLogin(cancelToken),
      };
      if (credentials == null || cancelToken.isCancelled) return;
      await _onSignedIn(credentials);
      _set(ChatGptCodexLoginDone(credentials));
    } on ChatGptCodexAuthException catch (error) {
      if (cancelToken.isCancelled ||
          error.kind == ChatGptCodexAuthFailure.cancelled) {
        return;
      }
      _set(ChatGptCodexLoginFailed(error.kind, error.message));
    } on DioException catch (error) {
      if (cancelToken.isCancelled) return;
      _set(
        ChatGptCodexLoginFailed(
          ChatGptCodexAuthFailure.failed,
          error.message ?? error.type.name,
        ),
      );
    }
  }

  Future<ChatGptCodexCredentials?> _deviceCode(CancelToken cancelToken) async {
    final device = await _client.startDeviceCode(cancelToken: cancelToken);
    _set(ChatGptCodexLoginDeviceCode(device.userCode));
    return _client.completeDeviceCode(device, cancelToken: cancelToken);
  }

  Future<ChatGptCodexCredentials?> _browserLogin(CancelToken cancelToken) async {
    final authorization = _authorization = _client
        .createBrowserAuthorization();
    final server = _server = await _startServer(authorization.state);
    final pasted = _pasted = Completer<String?>();
    final String? code;
    try {
      _set(
        ChatGptCodexLoginBrowser(
          url: authorization.url,
          listening: server != null,
        ),
      );
      unawaited(openLoginPage());
      code = await Future.any<String?>([
        if (server != null) server.code,
        pasted.future,
      ]);
    } finally {
      // Only this run's server: a restarted login owns the next one.
      if (identical(_server, server)) _server = null;
      await server?.close();
    }
    if (code == null || cancelToken.isCancelled) return null;
    _set(const ChatGptCodexLoginFinishing());
    return _client.exchangeCode(
      code: code,
      verifier: authorization.verifier,
      redirectUri: ChatGptCodexAuth.browserRedirectUri,
      cancelToken: cancelToken,
    );
  }

  /// Opens the browser login page again.
  Future<void> openLoginPage() async {
    final url = _authorization?.url;
    if (url != null) await _browser.open(url);
  }

  Future<void> openVerificationPage() =>
      _browser.open(Uri.parse(ChatGptCodexAuth.deviceVerificationUri));

  /// Accepts the address the browser ended on; returns false when it holds
  /// no usable code.
  bool submitRedirect(String input) {
    final pasted = _pasted;
    final authorization = _authorization;
    if (pasted == null || pasted.isCompleted || authorization == null) {
      return false;
    }
    final parsed = ChatGptCodexOAuthClient.parseAuthorizationInput(input);
    final code = parsed.code;
    if (code == null || code.isEmpty) return false;
    if (parsed.state case final state?
        when !OAuthPkce.secureEquals(authorization.state, state)) {
      return false;
    }
    pasted.complete(code);
    return true;
  }

  void cancel() {
    _reset();
    _set(const ChatGptCodexLoginChoosing());
  }

  void _reset() {
    _cancelToken?.cancel('Login cancelled');
    _cancelToken = null;
    _server?.cancel();
    final pasted = _pasted;
    if (pasted != null && !pasted.isCompleted) pasted.complete(null);
    _pasted = null;
    _authorization = null;
  }

  void _set(ChatGptCodexLoginPhase phase) {
    if (_disposed) return;
    _phase = phase;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _reset();
    super.dispose();
  }
}
