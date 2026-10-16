import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/presentation/providers/generation/generated_image_save_queue.dart';

void main() {
  test('a save of the same image waits for the one still writing', () async {
    final queue = GeneratedImageSaveQueue();
    final autoSave = Completer<void>();
    final order = <String>[];

    final first = queue.run(['a', 'b'], () async {
      order.add('auto start');
      await autoSave.future;
      order.add('auto end');
    });
    final favorite = queue.run(['a'], () async => order.add('favorite'));
    final other = queue.run(['c'], () async => order.add('other'));

    await other;
    expect(order, ['auto start', 'other']);

    autoSave.complete();
    await Future.wait([first, favorite]);
    expect(order, ['auto start', 'other', 'auto end', 'favorite']);
  });

  test('a failed save still lets the next one run', () async {
    final queue = GeneratedImageSaveQueue();
    final failed = queue.run<void>(['a'], () async => throw StateError('x'));
    final next = queue.run(['a'], () async => 'saved');

    await expectLater(failed, throwsStateError);
    expect(await next, 'saved');
  });
}
