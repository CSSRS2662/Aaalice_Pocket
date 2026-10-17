import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How generation waits before retrying a failed request. Tests replace it
/// to retry at once; the number of retries stays the same.
final generationRetryWaitProvider = Provider<Future<void> Function(Duration)>(
  (ref) => Future<void>.delayed,
);
