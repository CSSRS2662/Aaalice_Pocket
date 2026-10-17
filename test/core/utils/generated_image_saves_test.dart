import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
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

  Future<SavedResultImage> save(
    String root,
    Uint8List bytes,
    String source, {
    int seed = 433141965,
    bool allowDuplicate = false,
  }) => ImageSaveUtils.saveResultImage(
    rootPath: root,
    imageBytes: bytes,
    preserveOriginalBytes: true,
    rebuild: () async => fail('preserved bytes must not be rebuilt'),
    source: source,
    seed: seed,
    allowDuplicate: allowDuplicate,
  );

  /// A file a dated save wrote before this run, which no registry knows.
  Future<String> earlierSave(Directory root, Uint8List bytes, int seed) async {
    final folder = Directory(p.join(root.path, '2026-10-01'));
    await folder.create(recursive: true);
    final file = File(p.join(folder.path, '08-30-00-$seed.png'));
    await file.writeAsBytes(bytes);
    return file.path;
  }

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

  test('a copy saved before this run is found by its seed', () async {
    final root = await createRoot();
    final bytes = png(8);
    final earlier = await earlierSave(root, bytes, 7001);

    final saved = await save(root.path, bytes, 'detail-save', seed: 7001);

    expect(saved.reused, isTrue);
    expect(saved.path, earlier);
    expect(await savedFiles(root), [earlier]);
  });

  test('a file with the same seed but other bytes is not a copy', () async {
    final root = await createRoot();
    final earlier = await earlierSave(root, png(9), 7002);

    final saved = await save(root.path, png(10), 'detail-save', seed: 7002);

    expect(saved.reused, isFalse);
    expect(await savedFiles(root), unorderedEquals([earlier, saved.path]));
  });

  test('saving anyway writes a second copy', () async {
    final root = await createRoot();
    final bytes = png(11);
    final first = await save(root.path, bytes, 'card-save');

    final again = await save(
      root.path,
      bytes,
      'card-save',
      allowDuplicate: true,
    );

    expect(again.reused, isFalse);
    expect(again.path, isNot(first.path));
    expect(await savedFiles(root), unorderedEquals([first.path, again.path]));
  });
}
