import 'dart:async';
import 'dart:io';

import '../../../core/cloud_sync/oauth/oauth_pkce.dart';
import 'chatgpt_codex_credentials.dart';

/// Receives the browser login redirect on `localhost:1455`, the only redirect
/// the Codex client accepts. Ported from Pi's `startLocalOAuthServer`.
class ChatGptCodexCallbackServer {
  ChatGptCodexCallbackServer._(this._server, this._state) {
    _subscription = _server.listen(_handle);
  }

  final HttpServer _server;
  final String _state;
  late final StreamSubscription<HttpRequest> _subscription;
  final _code = Completer<String?>();

  /// Starts listening, or returns null when the port is taken; the user can
  /// still paste the redirect address by hand.
  static Future<ChatGptCodexCallbackServer?> start({
    required String state,
    int port = ChatGptCodexAuth.callbackPort,
  }) async {
    try {
      final server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        port,
      );
      return ChatGptCodexCallbackServer._(server, state);
    } on SocketException {
      return null;
    }
  }

  int get port => _server.port;

  /// Completes with the authorization code, or null once [cancel] is called.
  Future<String?> get code => _code.future;

  void cancel() {
    if (!_code.isCompleted) _code.complete(null);
  }

  Future<void> close() async {
    cancel();
    await _subscription.cancel();
    await _server.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    final uri = request.uri;
    final response = request.response
      ..headers.contentType = ContentType.html;
    if (uri.path != '/auth/callback') {
      response.statusCode = HttpStatus.notFound;
      response.write(_page('Callback route not found.'));
    } else if (!OAuthPkce.secureEquals(
      _state,
      uri.queryParameters['state'] ?? '',
    )) {
      response.statusCode = HttpStatus.badRequest;
      response.write(_page('State mismatch.'));
    } else if (uri.queryParameters['code'] case final code?
        when code.isNotEmpty) {
      response.statusCode = HttpStatus.ok;
      response.write(
        _page(
          'ChatGPT 登录完成，可以回到 Aaalice Pocket。<br>'
          'Login complete. You can return to Aaalice Pocket.',
        ),
      );
      if (!_code.isCompleted) _code.complete(code);
    } else {
      response.statusCode = HttpStatus.badRequest;
      response.write(_page('Missing authorization code.'));
    }
    await response.close();
  }

  static String _page(String message) =>
      '<!doctype html><html><head><meta charset="utf-8">'
      '<meta name="viewport" content="width=device-width,initial-scale=1">'
      '<title>Aaalice Pocket</title></head>'
      '<body style="font-family:sans-serif;padding:32px;line-height:1.6">'
      '<p>$message</p></body></html>';
}
