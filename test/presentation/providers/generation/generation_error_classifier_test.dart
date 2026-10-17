import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/presentation/providers/generation/generation_error_classifier.dart';

void main() {
  DioException http(int status) => DioException(
    requestOptions: RequestOptions(path: '/generate-image'),
    response: Response<void>(
      requestOptions: RequestOptions(path: '/generate-image'),
      statusCode: status,
    ),
  );

  test('transient failures are retried', () {
    for (final error in <Object>[
      'API_ERROR_500|Server error',
      'API_ERROR_503|Service unavailable',
      'API_ERROR_HTTP_502|Bad gateway',
      'API_ERROR_429|Too many requests',
      'API_ERROR_TIMEOUT|Timeout',
      'API_ERROR_NETWORK|Connection error',
      'No final image received from stream',
      StateError('temporary failure'),
      http(500),
      http(408),
      http(429),
      DioException(
        requestOptions: RequestOptions(path: '/generate-image'),
        type: DioExceptionType.connectionError,
      ),
    ]) {
      expect(isRetryableGenerationError(error), isTrue, reason: '$error');
    }
  });

  test('client errors that would fail again are not retried', () {
    for (final error in <Object>[
      'API_ERROR_400|invalid size',
      'API_ERROR_401|Unauthorized',
      'API_ERROR_402|Payment required',
      'API_ERROR_HTTP_403|Forbidden',
      Exception('API_ERROR_402|Not enough Anlas'),
      http(400),
      http(401),
      http(402),
      http(404),
    ]) {
      expect(isRetryableGenerationError(error), isFalse, reason: '$error');
    }
  });
}
