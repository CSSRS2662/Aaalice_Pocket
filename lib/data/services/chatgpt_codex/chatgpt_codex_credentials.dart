import 'dart:convert';
import 'dart:io';

/// Endpoints and identifiers of the Codex CLI's public OAuth client, ported
/// from Pi (`@earendil-works/pi-ai` `auth/oauth/openai-codex.js`).
abstract final class ChatGptCodexAuth {
  static const clientId = 'app_EMoamEEZ73f0CkXaXp7hrann';
  static const authBaseUrl = 'https://auth.openai.com';
  static const authorizeUrl = '$authBaseUrl/oauth/authorize';
  static const tokenUrl = '$authBaseUrl/oauth/token';
  static const scope = 'openid profile email offline_access';
  static const callbackPort = 1455;
  static const browserRedirectUri = 'http://localhost:1455/auth/callback';
  static const deviceUserCodeUrl =
      '$authBaseUrl/api/accounts/deviceauth/usercode';
  static const deviceTokenUrl = '$authBaseUrl/api/accounts/deviceauth/token';
  static const deviceVerificationUri = '$authBaseUrl/codex/device';
  static const deviceRedirectUri = '$authBaseUrl/deviceauth/callback';
  static const deviceCodeTimeout = Duration(minutes: 15);
  static const backendBaseUrl = 'https://chatgpt.com/backend-api';

  /// Sent with the authorize URL and every backend request. Pi identifies
  /// itself the same way, so the backend accepts a client's own name.
  static const originator = 'aaalice_pocket';

  /// API root for a provider's base URL: [backendBaseUrl] when empty, and a
  /// base that already names the Codex path is cut back to the root.
  static String backendBase(String baseUrl) {
    var base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty) return backendBaseUrl;
    for (final suffix in const ['/codex/responses', '/codex']) {
      if (base.endsWith(suffix)) {
        base = base.substring(0, base.length - suffix.length);
      }
    }
    return base;
  }

  static String get userAgent =>
      'aaalice_pocket (${Platform.operatingSystem} '
      '${Platform.operatingSystemVersion.split(' ').first})';

  static const _authClaim = 'https://api.openai.com/auth';
  static const _profileClaim = 'https://api.openai.com/profile';
}

/// The account facts carried by a ChatGPT access token.
class ChatGptCodexClaims {
  const ChatGptCodexClaims({required this.accountId, this.planType, this.email});

  final String accountId;
  final String? planType;
  final String? email;

  /// Reads the JWT payload without verifying it; the backend does that.
  static ChatGptCodexClaims? parse(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      if (payload is! Map) return null;
      final auth = payload[ChatGptCodexAuth._authClaim];
      final profile = payload[ChatGptCodexAuth._profileClaim];
      final accountId = auth is Map ? auth['chatgpt_account_id'] : null;
      if (accountId is! String || accountId.isEmpty) return null;
      final plan = auth is Map ? auth['chatgpt_plan_type'] : null;
      final email = profile is Map ? profile['email'] : payload['email'];
      return ChatGptCodexClaims(
        accountId: accountId,
        planType: plan is String && plan.isNotEmpty ? plan : null,
        email: email is String && email.isNotEmpty ? email : null,
      );
    } on FormatException {
      return null;
    }
  }
}

/// OAuth tokens for one ChatGPT login. Kept only in secure storage.
class ChatGptCodexCredentials {
  const ChatGptCodexCredentials({
    required this.access,
    required this.refresh,
    required this.expiresAt,
    required this.accountId,
    this.planType,
    this.email,
  });

  /// Refreshes this long before expiry, so a request never starts with a
  /// token about to lapse.
  static const refreshMargin = Duration(minutes: 5);

  final String access;
  final String refresh;
  final DateTime expiresAt;
  final String accountId;
  final String? planType;
  final String? email;

  bool needsRefresh(DateTime now) =>
      !now.isBefore(expiresAt.subtract(refreshMargin));

  bool isExpired(DateTime now) => !now.isBefore(expiresAt);

  /// Builds credentials from a token response; throws when the access token
  /// carries no ChatGPT account, as Pi does.
  static ChatGptCodexCredentials fromTokens({
    required String access,
    required String refresh,
    required int expiresInSeconds,
    required DateTime now,
  }) {
    final claims = ChatGptCodexClaims.parse(access);
    if (claims == null) {
      throw const FormatException('Failed to extract accountId from token');
    }
    return ChatGptCodexCredentials(
      access: access,
      refresh: refresh,
      expiresAt: now.add(Duration(seconds: expiresInSeconds)),
      accountId: claims.accountId,
      planType: claims.planType,
      email: claims.email,
    );
  }

  Map<String, Object?> toJson() => {
    'version': 1,
    'access': access,
    'refresh': refresh,
    'expiresAt': expiresAt.toUtc().millisecondsSinceEpoch,
    'accountId': accountId,
    if (planType != null) 'planType': planType,
    if (email != null) 'email': email,
  };

  static ChatGptCodexCredentials? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final access = raw['access'];
    final refresh = raw['refresh'];
    final expiresAt = raw['expiresAt'];
    final accountId = raw['accountId'];
    if (access is! String ||
        refresh is! String ||
        expiresAt is! int ||
        accountId is! String) {
      return null;
    }
    return ChatGptCodexCredentials(
      access: access,
      refresh: refresh,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresAt, isUtc: true),
      accountId: accountId,
      planType: raw['planType'] as String?,
      email: raw['email'] as String?,
    );
  }
}
