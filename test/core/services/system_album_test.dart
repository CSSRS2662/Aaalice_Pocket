import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/services/system_album.dart';
import 'package:nai_launcher/data/services/metadata/hash_calculator.dart';
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

    test('目标文件夹里已有同一张图（不在记录里）也算重复，并记下位置', () async {
      target.images['album://old/2026-09-01_10-00-00-1.png'] = bytes(1);

      final first = await save(bytes(1));
      // 之后命中记录，不再按内容查找。
      target.failFind = StateError('must use the record');
      final second = await save(bytes(1));

      expect(first.duplicate, isTrue);
      expect(first.location, 'album://old/2026-09-01_10-00-00-1.png');
      expect(second.location, first.location);
      expect(target.fileNames, isEmpty);
    });

    test('写入的字节不同时，也按来源字节在文件夹里查找', () async {
      final source = bytes(1);
      target.images['album://old/source.png'] = source;

      final result = await save(bytes(30), identity: source);

      expect(result.duplicate, isTrue);
      expect(result.location, 'album://old/source.png');
    });

    test('查询相册失败时照常保存', () async {
      target.failFind = StateError('query failed');

      final result = await save(bytes(1));

      expect(result.duplicate, isFalse);
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

    test('只在保存文件夹里按内容查找', () async {
      final album = Directory(p.join(directory.path, 'album'));
      final target = FolderAlbumTarget(() async => album);
      final calculator = FileHashCalculator();
      // 文件夹外的同一张图不算。
      await File(p.join(directory.path, 'outside.png')).writeAsBytes(bytes(1));
      expect(
        await target.find(
          bytes: bytes(1),
          sha256: await calculator.calculateFromBytesAsync(bytes(1)),
        ),
        isNull,
      );

      await album.create();
      await File(p.join(album.path, 'other.png')).writeAsBytes(bytes(2));
      await File(p.join(album.path, 'same.png')).writeAsBytes(bytes(1));

      expect(
        await target.find(
          bytes: bytes(1),
          sha256: await calculator.calculateFromBytesAsync(bytes(1)),
        ),
        p.join(album.path, 'same.png'),
      );
    });
  });
}
