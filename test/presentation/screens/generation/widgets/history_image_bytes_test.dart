import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/presentation/providers/generation/generated_image_file_cache.dart';
import 'package:nai_launcher/presentation/providers/generation/generation_models.dart';
import 'package:nai_launcher/presentation/screens/generation/widgets/history_image_bytes.dart';

Future<List<Uint8List>> _pump(WidgetTester tester, GeneratedImage image) async {
  final built = <Uint8List>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Center(
        child: SizedBox.square(
          dimension: 120,
          child: HistoryImageBytes(
            image: image,
            builder: (bytes) {
              built.add(bytes);
              return const SizedBox.expand(key: ValueKey('history-card'));
            },
          ),
        ),
      ),
    ),
  );
  return built;
}

void main() {
  tearDown(GeneratedImageFileCache.clear);

  testWidgets('an image held in memory builds its card at once', (
    tester,
  ) async {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final built = await _pump(
      tester,
      GeneratedImage(id: 'a', bytes: bytes, width: 8, height: 8),
    );

    expect(built.single, same(bytes));
    expect(find.byKey(const ValueKey('history-card')), findsOneWidget);
  });

  testWidgets('a cached file builds its card without reading the file', (
    tester,
  ) async {
    const path = 'never/read/b.png';
    final bytes = Uint8List.fromList([4, 5]);
    GeneratedImageFileCache.remember(path, bytes);

    final built = await _pump(
      tester,
      GeneratedImage.stored(
        id: 'b',
        storedPath: path,
        width: 8,
        height: 8,
        createdAt: DateTime(2026),
      ),
    );

    expect(built.single, same(bytes));
    expect(find.byKey(const ValueKey('history-image-loading')), findsNothing);
  });

  testWidgets('a card keeps its bytes after the cache evicts them', (
    tester,
  ) async {
    const path = 'never/read/c.png';
    final bytes = Uint8List.fromList([6]);
    GeneratedImageFileCache.remember(path, bytes);
    final image = GeneratedImage.stored(
      id: 'c',
      storedPath: path,
      width: 8,
      height: 8,
      createdAt: DateTime(2026),
    );
    final built = await _pump(tester, image);

    GeneratedImageFileCache.evict(path);
    built.addAll(await _pump(tester, image));

    expect(built, hasLength(2));
    expect(built.last, same(bytes));
    expect(find.byKey(const ValueKey('history-image-loading')), findsNothing);
  });
}
