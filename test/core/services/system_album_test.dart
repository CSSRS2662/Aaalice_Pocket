import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/services/system_album.dart';
import 'package:path/path.dart' as p;

import '../../helpers/memory_system_album.dart';

void main() {
  Uint8List bytes(int value) => Uint8List.fromList([value, value + 1]);

  group('SystemAlbum', () {
    late MemoryAlbumTarget target;
    late MemorySettingsStorage storage;
    late SystemAlbum album;

    setUp(() {
      target = MemoryAlbumTarget();
      storage = MemorySettingsStorage();
      album = SystemAlbum(storage: storage, target: target);
    });

    Future<SystemAlbumSave> save(
      Uint8List data, {
      Uint8List? identity,
      bool allowDuplicate = false,
    }) => album.save(
      bytes: data,
      identity: identity,
      fileName: 'image.png',
      source: 'test',
      allowDuplicate: allowDuplicate,
    );

    test('同一张图只写一次，再次保存报告重复与原位置', () async {
      final first = await save(bytes(1));
      final second = await save(bytes(1));

      expect(first.duplicate, isFalse);
      expect(second.duplicate, isTrue);
      expect(second.location, first.location);
      expect(target.images, hasLength(1));
    });

    test('按来源字节判重：重建元数据后的字节不同也算同一张', () async {
      final source = bytes(1);
      await save(bytes(10), identity: source);

      final again = await save(bytes(20), identity: source);

      expect(again.duplicate, isTrue);
      expect(target.images, hasLength(1));
    });

    test('用户从相册删掉后，再保存会重新写入', () async {
      final first = await save(bytes(1));
      target.images.remove(first.location);

      final again = await save(bytes(1));

      expect(again.duplicate, isFalse);
      expect(again.location, isNot(first.location));
      expect(target.images.keys, [again.location]);
    });

    test('依然保存时写入另一份', () async {
      await save(bytes(1));

      final copy = await save(bytes(1), allowDuplicate: true);

      expect(copy.duplicate, isFalse);
      expect(target.images, hasLength(2));
    });

    test('同时保存同一张图只写一次', () async {
      final results = await Future.wait([save(bytes(1)), save(bytes(1))]);

      expect(results.where((result) => result.duplicate), hasLength(1));
      expect(results.first.location, results.last.location);
      expect(target.images, hasLength(1));
    });

    test('写入失败不留下记录，下次照常保存', () async {
      target.failNextWrite = StateError('denied');
      await expectLater(save(bytes(1)), throwsStateError);

      final retry = await save(bytes(1));

      expect(retry.duplicate, isFalse);
      expect(target.images, hasLength(1));
    });

    test('去重记录存在本机设置里，换一个实例仍然有效', () async {
      final first = await save(bytes(1));

      final reopened = SystemAlbum(storage: storage, target: target);
      final again = await reopened.save(
        bytes: bytes(1),
        fileName: 'image.png',
        source: 'test',
      );

      expect(again.duplicate, isTrue);
      expect(again.location, first.location);
    });
  });

  group('FolderAlbumTarget', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('system_album_test_');
    });

    tearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    test('写进文件夹，重名时加序号而不覆盖', () async {
      final target = FolderAlbumTarget(
        () async => Directory(p.join(directory.path, 'album')),
      );

      final first = await target.write(bytes(1), 'image.png');
      final second = await target.write(bytes(2), 'image.png');

      expect(p.basename(first), 'image.png');
      expect(p.basename(second), 'image-2.png');
      expect(await File(first).readAsBytes(), bytes(1));
      expect(await File(second).readAsBytes(), bytes(2));
      expect(target.isPhotoAlbum, isFalse);
      expect(await target.contains(first), isTrue);

      await File(first).delete();
      expect(await target.contains(first), isFalse);
    });
  });
}
