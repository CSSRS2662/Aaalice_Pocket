import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import '../utils/app_logger.dart';

final androidForegroundTaskServiceProvider = Provider(
  (ref) => AndroidForegroundTaskService(),
);

typedef AndroidGenerationTask = ({
  void Function({
    required int current,
    required int total,
    required double progress,
  })
  update,
  Future<void> Function() release,
});

typedef _GenerationProgress = ({
  int current,
  int total,
  int percent,
  bool queue,
});

/// Shares Android's foreground execution between generation and Agent runs.
class AndroidForegroundTaskService {
  AndroidForegroundTaskService({
    bool? supported,
    MethodChannel channel = const MethodChannel(
      'com.aaalice.nai_launcher/generation_service',
    ),
    Future<void> Function()? requestNotificationPermission,
  }) : _supported = supported ?? (!kIsWeb && Platform.isAndroid),
       _channel = channel,
       _requestNotificationPermission =
           requestNotificationPermission ?? _requestPermission;

  final bool _supported;
  final MethodChannel _channel;
  final Future<void> Function() _requestNotificationPermission;
  Future<void> _pending = Future<void>.value();
  int _owners = 0;
  final _generationProgress = <Object, _GenerationProgress>{};
  _GenerationProgress? _publishedProgress;
  Timer? _progressUpdate;

  /// The returned release is idempotent and belongs to this invocation only.
  Future<Future<void> Function()> acquire() async {
    if (!_supported) return () async {};
    await _serialize(() async {
      if (_owners == 0) {
        await _requestNotificationPermission();
        await _channel.invokeMethod<void>('start');
      }
      _owners++;
    });
    Future<void>? released;
    return () => released ??= _serialize(() async {
      _owners--;
      if (_owners == 0) {
        _progressUpdate?.cancel();
        _progressUpdate = null;
        _publishedProgress = null;
        await _channel.invokeMethod<void>('stop');
      }
    });
  }

  Future<AndroidGenerationTask> acquireGeneration({bool queue = false}) async {
    final release = await acquire();
    final owner = Object();
    Future<void>? released;
    return (
      update:
          ({
            required int current,
            required int total,
            required double progress,
          }) {
            if (!_supported || released != null || total < 2) return;
            final next = (
              current: current.clamp(1, total),
              total: total,
              percent: (progress * 100).floor().clamp(0, 99),
              queue: queue,
            );
            if (_generationProgress[owner] == next) return;
            _generationProgress[owner] = next;
            _progressUpdate ??= Timer(const Duration(milliseconds: 300), () {
              _progressUpdate = null;
              unawaited(_serialize(_publishProgress));
            });
          },
      release: () {
        if (released != null) return released!;
        final hadProgress = _generationProgress.remove(owner) != null;
        return released = release().whenComplete(() async {
          if (hadProgress) await _serialize(_publishProgress);
        });
      },
    );
  }

  Future<void> _publishProgress() async {
    if (_owners == 0) return;
    _GenerationProgress? next;
    for (final progress in _generationProgress.values) {
      next = progress;
      if (progress.queue) break;
    }
    if (next == _publishedProgress) return;
    try {
      await _channel.invokeMethod<void>(
        'updateProgress',
        next == null
            ? null
            : {
                'current': next.current,
                'total': next.total,
                'percent': next.percent,
                'queue': next.queue,
              },
      );
      _publishedProgress = next;
    } catch (error, stackTrace) {
      AppLogger.e(
        'Unable to update the generation notification',
        error,
        stackTrace,
      );
    }
  }

  Future<void> _serialize(Future<void> Function() operation) {
    final result = _pending.then((_) => operation());
    // A failed platform call must reach its caller without poisoning later
    // owners' cleanup or acquisition.
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  static Future<void> _requestPermission() async {
    final notificationStatus = await ph.Permission.notification.status;
    if (notificationStatus.isDenied) {
      await ph.Permission.notification.request();
    }
  }
}
