import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/cloud_sync/oauth/oauth_pkce.dart';
import 'chatgpt_codex_credentials.dart';

enum ChatGptCodexAuthFailure {
  cancelled,
  timedOut,

  /// The account or workspace has device-code login turned off.
  deviceCodeUnavailable,
  failed,
}

class ChatGptCodexAuthException implements Exception {
  const ChatGptCodexAuthException(this.kind, this.message);

  final ChatGptCodexAuthFailure kind;
  final String message;

  @override
  String toString() => message;
}

/// A device code the user types in at [ChatGptCodexAuth.deviceVerificationUri].
class ChatGptCodexDeviceCode {
  const ChatGptCodexDeviceCode({
    required this.deviceAuthId,
    required this.userCode,
    required this.interval,
  });

  final String deviceAuthId;
  final String userCode;
  final Duration interval;
}

/// A browser authorization waiting for its redirect.
class ChatGptCodexBrowserAuthorization {
  const ChatGptCodexBrowserAuthorization({
    required this.url,
    required this.verifier,
    required this.state,
  });

  final Uri url;
  final String verifier;
  final String state;
}

typedef ChatGptCodexSleep =
    Future<void> Function(Duration duration, CancelToken cancelToken);

/// ChatGPT (Codex) OAuth, ported from Pi's `auth/oauth/openai-codex.js` and
/// `device-code.js`: PKCE browser login, device-code login, code exchange and
/// refresh against auth.openai.com.
class ChatGptCodexOAuthClient {
  ChatGptCodexOAuthClient(
    this._dio, {
    DateTime Function()? clock,
    ChatGptCodexSleep? sleep,
    OAuthPkce? pkce,
  }) : _clock = clock ?? DateTime.now,
       _sleep = sleep ?? _cancellableDelay,
       _pkce = pkce ?? OAuthPkce();

  final Dio _dio;
  final DateTime Function() _clock;
  final ChatGptCodexSleep _sleep;
  final OAuthPkce _pkce;

  /// RFC 8628 defaults that Pi applies to every device flow.
  static const _minimumInterval = Duration(seconds: 1);
  static const _defaultInterval = Duration(seconds: 5);
  static const _slowDownIncrement = Duration(seconds: 5);

  static final _allStatuses = Options(validateStatus: (_) => true);

  Future<ChatGptCodexDeviceCode> startDeviceCode({
    CancelToken? cancelToken,
  }) async {
    final response = await _post(
      ChatGptCodexAuth.deviceUserCodeUrl,
      data: {'client_id': ChatGptCodexAuth.clientId},
      json: true,
      cancelToken: cancelToken,
    );
    final status = response.statusCode ?? 0;
    if (status == 404) {
      throw const ChatGptCodexAuthException(
        ChatGptCodexAuthFailure.deviceCodeUnavailable,
        'Device code login is not enabled for this account.',
      );
    }
    if (status < 200 || status >= 300) {
      throw ChatGptCodexAuthException(
        ChatGptCodexAuthFailure.failed,
        'Device code request failed with status $status'
        '${_bodySuffix(response.data)}',
      );
    }
    final json = _asMap(response.data);
    final rawInterval = json?['interval'];
    final interval = rawInterval is String
        ? num.tryParse(rawInterval.trim())
        : rawInterval is num
        ? rawInterval
        : null;
    final deviceAuthId = json?['device_auth_id'];
    final userCode = json?['user_code'];
    if (deviceAuthId is! String ||
        deviceAuthId.isEmpty ||
        userCode is! String ||
        userCode.isEmpty ||
        interval == null ||
        !interval.isFinite ||
        interval < 0) {
      throw ChatGptCodexAuthException(
        ChatGptCodexAuthFailure.failed,
        'Invalid device code response: ${jsonEncode(json)}',
      );
    }
    return ChatGptCodexDeviceCode(
      deviceAuthId: deviceAuthId,
      userCode: userCode,
      interval: Duration(milliseconds: (interval * 1000).floor()),
    );
  }

  /// Polls until the user approves [device], then exchanges the code.
  Future<ChatGptCodexCredentials> completeDeviceCode(
    ChatGptCodexDeviceCode device, {
    required CancelToken cancelToken,
  }) async {
    final deadline = _clock().add(ChatGptCodexAuth.deviceCodeTimeout);
    var interval = _atLeastMinimum(
      device.interval == Duration.zero ? _defaultInterval : device.interval,
    );
    var slowDowns = 0;
    while (_clock().isBefore(deadline)) {
      _throwIfCancelled(cancelToken);
      final result = await _pollDeviceCode(device, cancelToken);
      switch (result) {
        case _DevicePollComplete(:final code, :final verifier):
          return exchangeCode(
            code: code,
            verifier: verifier,
            redirectUri: ChatGptCodexAuth.deviceRedirectUri,
            cancelToken: cancelToken,
          );
        case _DevicePollFailed(:final message):
          throw ChatGptCodexAuthException(
            ChatGptCodexAuthFailure.failed,
            message,
          );
        case _DevicePollSlowDown():
          slowDowns++;
          interval = _atLeastMinimum(interval + _slowDownIncrement);
        case _DevicePollPending():
          break;
      }
      final remaining = deadline.difference(_clock());
      if (remaining <= Duration.zero) break;
      await _sleep(remaining < interval ? remaining : interval, cancelToken);
    }
    throw ChatGptCodexAuthException(
      ChatGptCodexAuthFailure.timedOut,
      slowDowns > 0
          ? 'Device login timed out after slow_down responses; check the '
                'device clock and try again.'
          : 'Device login timed out.',
    );
  }

  Future<_DevicePollResult> _pollDeviceCode(
    ChatGptCodexDeviceCode device,
    CancelToken cancelToken,
  ) async {
    final response = await _post(
      ChatGptCodexAuth.deviceTokenUrl,
      data: {
        'device_auth_id': device.deviceAuthId,
        'user_code': device.userCode,
      },
      json: true,
      cancelToken: cancelToken,
    );
    final status = response.statusCode ?? 0;
    if (status >= 200 && status < 300) {
      final json = _asMap(response.data);
      final code = json?['authorization_code'];
      final verifier = json?['code_verifier'];
      if (code is! String || code.isEmpty || verifier is! String) {
        return _DevicePollFailed(
          'Invalid device auth token response: ${jsonEncode(json)}',
        );
      }
      return _DevicePollComplete(code, verifier);
    }
    if (status == 403 || status == 404) return const _DevicePollPending();
    final error = _asMap(response.data)?['error'];
    final errorCode = error is Map ? error['code'] : error;
    if (errorCode == 'deviceauth_authorization_pending') {
      return const _DevicePollPending();
    }
    if (errorCode == 'slow_down') return const _DevicePollSlowDown();
    return _DevicePollFailed(
      'Device auth failed with status $status${_bodySuffix(response.data)}',
    );
  }

  ChatGptCodexBrowserAuthorization createBrowserAuthorization() {
    final request = _pkce.create();
    final url = Uri.parse(ChatGptCodexAuth.authorizeUrl).replace(
      queryParameters: {
        'response_type': 'code',
        'client_id': ChatGptCodexAuth.clientId,
        'redirect_uri': ChatGptCodexAuth.browserRedirectUri,
        'scope': ChatGptCodexAuth.scope,
        'code_challenge': request.codeChallenge,
        'code_challenge_method': 'S256',
        'state': request.state,
        'id_token_add_organizations': 'true',
        'codex_cli_simplified_flow': 'true',
        'originator': ChatGptCodexAuth.originator,
      },
    );
    return ChatGptCodexBrowserAuthorization(
      url: url,
      verifier: request.codeVerifier,
      state: request.state,
    );
  }

  Future<ChatGptCodexCredentials> exchangeCode({
    required String code,
    required String verifier,
    required String redirectUri,
    CancelToken? cancelToken,
  }) async {
    final response = await _post(
      ChatGptCodexAuth.tokenUrl,
      data: {
        'grant_type': 'authorization_code',
        'client_id': ChatGptCodexAuth.clientId,
        'code': code,
        'code_verifier': verifier,
        'redirect_uri': redirectUri,
      },
      cancelToken: cancelToken,
    );
    return _readTokens(response, 'exchange');
  }

  Future<ChatGptCodexCredentials> refresh(String refreshToken) async {
    final response = await _post(
      ChatGptCodexAuth.tokenUrl,
      data: {
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
        'client_id': ChatGptCodexAuth.clientId,
      },
    );
    return _readTokens(response, 'refresh');
  }

  /// Accepts a pasted redirect URL, `code#state`, a query string or a bare
  /// code, like Pi's `parseAuthorizationInput`.
  static ({String? code, String? state}) parseAuthorizationInput(String input) {
    final value = input.trim();
    if (value.isEmpty) return (code: null, state: null);
    final url = Uri.tryParse(value);
    if (url != null && url.hasScheme && url.host.isNotEmpty) {
      return (
        code: url.queryParameters['code'],
        state: url.queryParameters['state'],
      );
    }
    if (value.contains('#')) {
      final index = value.indexOf('#');
      return (code: value.substring(0, index), state: value.substring(index + 1));
    }
    if (value.contains('code=')) {
      final query = Uri.splitQueryString(
        value.startsWith('?') ? value.substring(1) : value,
      );
      return (code: query['code'], state: query['state']);
    }
    return (code: value, state: null);
  }

  ChatGptCodexCredentials _readTokens(Response<dynamic> response, String step) {
    final status = response.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      throw ChatGptCodexAuthException(
        ChatGptCodexAuthFailure.failed,
        'Token $step failed ($status)${_bodySuffix(response.data)}',
      );
    }
    final json = _asMap(response.data);
    final access = json?['access_token'];
    final refresh = json?['refresh_token'];
    final expiresIn = json?['expires_in'];
    if (access is! String || refresh is! String || expiresIn is! num) {
      throw ChatGptCodexAuthException(
        ChatGptCodexAuthFailure.failed,
        'Token $step response is missing fields.',
      );
    }
    try {
      return ChatGptCodexCredentials.fromTokens(
        access: access,
        refresh: refresh,
        expiresInSeconds: expiresIn.toInt(),
        now: _clock(),
      );
    } on FormatException catch (error) {
      throw ChatGptCodexAuthException(
        ChatGptCodexAuthFailure.failed,
        error.message,
      );
    }
  }

  Future<Response<dynamic>> _post(
    String url, {
    required Map<String, Object?> data,
    bool json = false,
    CancelToken? cancelToken,
  }) async {
    try {
      return await _dio.post<dynamic>(
        url,
        data: json ? data : Uri(queryParameters: _strings(data)).query,
        options: _allStatuses.copyWith(
          contentType: json
              ? Headers.jsonContentType
              : Headers.formUrlEncodedContentType,
        ),
        cancelToken: cancelToken,
      );
    } on DioException catch (error) {
      if (error.type == DioExceptionType.cancel) {
        throw const ChatGptCodexAuthException(
          ChatGptCodexAuthFailure.cancelled,
          'Login cancelled',
        );
      }
      rethrow;
    }
  }

  static Duration _atLeastMinimum(Duration value) =>
      value < _minimumInterval ? _minimumInterval : value;

  static void _throwIfCancelled(CancelToken token) {
    if (token.isCancelled) {
      throw const ChatGptCodexAuthException(
        ChatGptCodexAuthFailure.cancelled,
        'Login cancelled',
      );
    }
  }

  static Future<void> _cancellableDelay(
    Duration duration,
    CancelToken cancelToken,
  ) async {
    final timer = Completer<void>();
    final handle = Timer(duration, timer.complete);
    try {
      await Future.any([timer.future, cancelToken.whenCancel]);
    } finally {
      handle.cancel();
    }
    _throwIfCancelled(cancelToken);
  }

  static Map<String, String> _strings(Map<String, Object?> data) => {
    for (final entry in data.entries)
      if (entry.value != null) entry.key: entry.value.toString(),
  };

  static Map<String, dynamic>? _asMap(Object? data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return data.cast<String, dynamic>();
    if (data is String && data.trim().startsWith('{')) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map) return decoded.cast<String, dynamic>();
      } on FormatException {
        return null;
      }
    }
    return null;
  }

  static String _bodySuffix(Object? data) {
    if (data == null) return '';
    final text = data is String ? data : jsonEncode(data);
    final trimmed = text.trim();
    if (trimmed.isEmpty) return '';
    return ': ${trimmed.length > 300 ? '${trimmed.substring(0, 300)}…' : trimmed}';
  }
}

sealed class _DevicePollResult {
  const _DevicePollResult();
}

class _DevicePollComplete extends _DevicePollResult {
  const _DevicePollComplete(this.code, this.verifier);

  final String code;
  final String verifier;
}

class _DevicePollPending extends _DevicePollResult {
  const _DevicePollPending();
}

class _DevicePollSlowDown extends _DevicePollResult {
  const _DevicePollSlowDown();
}

class _DevicePollFailed extends _DevicePollResult {
  const _DevicePollFailed(this.message);

  final String message;
}
