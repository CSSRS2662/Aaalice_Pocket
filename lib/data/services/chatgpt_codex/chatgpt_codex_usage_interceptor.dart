import 'package:dio/dio.dart';

import 'chatgpt_codex_usage.dart';

/// Reads the quota headers of every Codex response, so the quota display
/// follows real use without extra requests. Error responses carry them too.
class ChatGptCodexUsageInterceptor extends Interceptor {
  ChatGptCodexUsageInterceptor(this._onUsage, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final void Function(String accountId, ChatGptCodexUsage usage) _onUsage;
  final DateTime Function() _clock;

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    _capture(response);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.response case final response?) _capture(response);
    handler.next(err);
  }

  void _capture(Response<dynamic> response) {
    final request = response.requestOptions;
    if (!request.uri.path.endsWith('/codex/responses')) return;
    final accountId = request.headers['chatgpt-account-id'];
    if (accountId is! String || accountId.isEmpty) return;
    final usage = ChatGptCodexUsage.fromHeaders(response.headers.map, _clock());
    if (usage != null) _onUsage(accountId, usage);
  }
}
