import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/services/android_foreground_task_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/foreground');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<String> calls;
  late AndroidForegroundTaskService service;

  setUp(() {
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
    service = AndroidForegroundTaskService(
      supported: true,
      channel: channel,
      requestNotificationPermission: () async {},
    );
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'generation and Agent keep service until the last owner finishes',
    () async {
      final releases = await Future.wait([
        service.acquire(),
        service.acquire(),
      ]);
      expect(calls, ['start']);
      await releases.first();
      await releases.first();
      expect(calls, ['start']);
      await releases.last();
      expect(calls, ['start', 'stop']);
    },
  );

  test('new owner waits for pending stop before starting again', () async {
    final stop = Completer<void>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'stop') await stop.future;
      return null;
    });
    final release = await service.acquire();
    final stopping = release();
    final next = service.acquire();
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['start', 'stop']);
    stop.complete();
    await stopping;
    final releaseNext = await next;
    expect(calls, ['start', 'stop', 'start']);
    await releaseNext();
  });

  test(
    'progress follows the queue and falls back to the active owner',
    () async {
      final updates = <Object?>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'updateProgress') updates.add(call.arguments);
        return null;
      });
      final agent = await service.acquire();
      final batch = await service.acquireGeneration();
      final queue = await service.acquireGeneration(queue: true);

      batch.update(current: 1, total: 3, progress: 0.16);
      queue.update(current: 1, total: 4, progress: 0.1);
      queue.update(current: 2, total: 4, progress: 0.34);
      await Future<void>.delayed(const Duration(milliseconds: 310));
      expect(updates, [
        {'current': 2, 'total': 4, 'percent': 34, 'queue': true},
      ]);

      batch.update(current: 2, total: 3, progress: 0.45);
      await Future<void>.delayed(const Duration(milliseconds: 310));
      expect(updates, hasLength(1));

      await queue.release();
      expect(updates.last, {
        'current': 2,
        'total': 3,
        'percent': 45,
        'queue': false,
      });
      await batch.release();
      expect(updates.last, isNull);

      batch.update(current: 3, total: 3, progress: 1);
      await Future<void>.delayed(const Duration(milliseconds: 310));
      expect(updates, hasLength(3));
      expect(calls, isNot(contains('stop')));
      await agent();
      expect(calls.last, 'stop');
    },
  );

  test('failed start is reported and does not acquire an owner', () async {
    var failed = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (!failed) {
        failed = true;
        throw PlatformException(code: 'start_failed');
      }
      return null;
    });
    await expectLater(service.acquire(), throwsA(isA<PlatformException>()));
    final release = await service.acquire();
    await release();
    expect(calls, ['start', 'start', 'stop']);
  });

  test(
    'failed stop reaches the owner and a subsequent task can start',
    () async {
      var failed = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'stop' && !failed) {
          failed = true;
          throw PlatformException(code: 'stop_failed');
        }
        return null;
      });
      final release = await service.acquire();
      await expectLater(release(), throwsA(isA<PlatformException>()));
      final next = await service.acquire();
      await next();
      expect(calls, ['start', 'stop', 'start', 'stop']);
    },
  );

  test(
    'unsupported platforms do not invoke permissions or native methods',
    () async {
      final service = AndroidForegroundTaskService(
        supported: false,
        channel: channel,
        requestNotificationPermission: () async =>
            fail('unexpected permission request'),
      );
      final release = await service.acquire();
      await release();
      expect(calls, isEmpty);
    },
  );
}
