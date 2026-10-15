import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// An unsigned JWT shaped like a ChatGPT access token.
String fakeChatGptToken({
  String accountId = 'acc_1',
  String? plan = 'plus',
  String? email = 'me@example.com',
  String tag = 'a',
}) {
  String segment(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return [
    segment({'alg': 'none'}),
    segment({
      'https://api.openai.com/auth': {
        'chatgpt_account_id': accountId,
        'chatgpt_plan_type': ?plan,
      },
      'https://api.openai.com/profile': {'email': ?email},
      'tag': tag,
    }),
    'sig',
  ].join('.');
}

class FakeRequest {
  FakeRequest(this.options);

  final RequestOptions options;

  String get path => options.uri.path;
  Object? get data => options.data;
}

typedef FakeHandler = ResponseBody Function(FakeRequest request);

/// Answers by URL path; records every request.
class RoutedHttpAdapter implements HttpClientAdapter {
  RoutedHttpAdapter(this.routes);

  final Map<String, FakeHandler> routes;
  final requests = <FakeRequest>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final request = FakeRequest(options);
    requests.add(request);
    final handler = routes[options.uri.path];
    if (handler == null) {
      return ResponseBody.fromString('not found', 404);
    }
    return handler(request);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonBody(
  Object body, {
  int status = 200,
  Map<String, List<String>> headers = const {},
}) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
    ...headers,
  },
);

ResponseBody sseBody(
  List<Map<String, Object?>> events, {
  Map<String, List<String>> headers = const {},
}) => ResponseBody.fromString(
  [
    for (final event in events)
      'event: ${event['type']}\ndata: ${jsonEncode(event)}\n\n',
  ].join(),
  200,
  headers: {
    Headers.contentTypeHeader: ['text/event-stream'],
    ...headers,
  },
);
