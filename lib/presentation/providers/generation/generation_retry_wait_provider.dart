import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How generation waits while the account's concurrent generation slot is
/// busy (429). Failed requests themselves are retried at once. Tests replace
/// it to continue without waiting.
final generationRetryWaitProvider = Provider<Future<void> Function(Duration)>(
  (ref) => Future<void>.delayed,
);
