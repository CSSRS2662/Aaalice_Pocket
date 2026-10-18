import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/presentation/providers/generation/generated_image_file_cache.dart';
import 'package:nai_launcher/presentation/providers/generation/generation_models.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('file_cache_test_');
  });

  tearDown(() async {
    GeneratedImageFileCache.clear();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  Future<String> file(String name, List<int> content) async {
    final path = p.join(directory.path, name);
    await File(path).writeAsBytes(content);
    return path;
  }

  test('读过的图留在缓存里，不再读文件', () async {
    final path = await file('a.png', [1, 2, 3]);

    expect(GeneratedImageFileCache.read(path), [1, 2, 3]);
    await File(path).delete();

    expect(GeneratedImageFileCache.isCached(path), isTrue);
    expect(GeneratedImageFileCache.read(path), [1, 2, 3]);
  });

  test('读不到的文件返回空字节', () {
    expect(GeneratedImageFileCache.read(p.join(directory.path, 'x.png')), []);
  });

  test('预读在后台把文件放进缓存', () async {
    final path = await file('b.png', [4, 5]);

    await GeneratedImageFileCache.prefetch([path]);

    expect(GeneratedImageFileCache.isCached(path), isTrue);
  });

  test('超出预算时先淘汰最久没用的图', () {
    const half = GeneratedImageFileCache.budgetBytes ~/ 2;
    GeneratedImageFileCache.remember('old', Uint8List(half));
    GeneratedImageFileCache.remember('small', Uint8List(1));
    // 读一次 old，让 small 成为最久没用的。
    GeneratedImageFileCache.read('old');

    GeneratedImageFileCache.remember('new', Uint8List(half));

    expect(GeneratedImageFileCache.isCached('small'), isFalse);
    expect(GeneratedImageFileCache.isCached('old'), isTrue);
    expect(GeneratedImageFileCache.isCached('new'), isTrue);
  });

  test('存在文件里的历史图按需从缓存读取字节', () async {
    final path = await file('c.png', [7, 8, 9]);
    final image = GeneratedImage.stored(
      id: 'c',
      storedPath: path,
      width: 1,
      height: 1,
      createdAt: DateTime(2026),
    );

    expect(image.isStored, isTrue);
    expect(image.bytes, [7, 8, 9]);
    expect(GeneratedImageFileCache.isCached(path), isTrue);
  });
}
