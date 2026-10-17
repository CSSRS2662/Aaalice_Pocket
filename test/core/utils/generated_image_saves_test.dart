import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nai_launcher/core/utils/generated_image_saves.dart';
import 'package:nai_launcher/core/utils/image_save_utils.dart';

void main() {
  Future<Directory> createRoot() async {
    final root = await Directory.systemTemp.createTemp('generated-saves-');
    addTearDown(() => root.delete(recursive: true));
    return root;
  }

  Uint8List png(int width) =>
      Uint8List.fromList(img.encodePng(img.Image(width: width, height: 2)));

  Future<SavedResultImage> save(String root, Uint8List bytes, String source) =>
      ImageSaveUtils.saveResultImage(
        rootPath: root,
        imageBytes: bytes,
        preserveOriginalBytes: true,
        rebuild: () async => fail('preserved bytes must not be rebuilt'),
        source: source,
        seed: 433141965,
      );

  Future<List<String>> savedFiles(Directory root) async => [
    await for (final entity in root.list(recursive: true))
      if (entity is File) entity.path,
  ];

  test('concurrent saves of one image write one file', () async {
    final root = await createRoot();
    final bytes = png(3);

    final results = await Future.wait([
      save(root.path, bytes, 'auto-save'),
      save(root.path, Uint8List.fromList(bytes), 'file-link'),
    ]);

    expect(await savedFiles(root), [results.first.path]);
    expect(results.last.path, results.first.path);
    expect([for (final result in results) result.reused], [false, true]);
    expect(results.last.bytes, orderedEquals(bytes));
  });

  test('a later save reuses the file until it is deleted', () async {
    final root = await createRoot();
    final bytes = png(4);

    final first = await save(root.path, bytes, 'auto-save');
    final again = await save(root.path, bytes, 'detail-save');
    expect(again.path, first.path);
    expect(again.reused, isTrue);

    await File(first.path).delete();
    final rewritten = await save(root.path, bytes, 'detail-save');
    expect(rewritten.reused, isFalse);
    expect(await savedFiles(root), [rewritten.path]);
  });

  test('different images and roots each get their own file', () async {
    final root = await createRoot();
    final otherRoot = await createRoot();
    final bytes = png(5);

    final first = await save(root.path, bytes, 'auto-save');
    final other = await save(root.path, png(6), 'auto-save');
    final elsewhere = await save(otherRoot.path, bytes, 'auto-save');

    expect(other.path, isNot(first.path));
    expect(other.reused, isFalse);
    expect(elsewhere.reused, isFalse);
    expect(await savedFiles(root), unorderedEquals([first.path, other.path]));
  });

  test('a failed save lets the next one write', () async {
    final root = await createRoot();
    final bytes = png(7);

    await expectLater(
      GeneratedImageSaves.saveOnce(
        rootPath: root.path,
        sourceBytes: bytes,
        source: 'card-save',
        write: () async => throw const FileSystemException('disk full'),
      ),
      throwsA(isA<FileSystemException>()),
    );
    final saved = await save(root.path, bytes, 'card-save');

    expect(saved.reused, isFalse);
    expect(await savedFiles(root), [saved.path]);
  });
}
