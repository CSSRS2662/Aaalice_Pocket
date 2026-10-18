import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:image/image.dart' as img;
import 'package:nai_launcher/core/constants/storage_keys.dart';
import 'package:nai_launcher/data/models/fixed_tag/fixed_tag_entry.dart';
import 'package:nai_launcher/data/models/fixed_tag/fixed_tag_prompt_type.dart';
import 'package:nai_launcher/data/models/fixed_tag/fixed_tag_usage_snapshot.dart';
import 'package:nai_launcher/presentation/providers/generation/generated_image_file_cache.dart';
import 'package:nai_launcher/presentation/providers/generation/generation_models.dart';
import 'package:nai_launcher/presentation/services/generation_history_storage_service.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory hiveDirectory;
  late Directory imageDirectory;
  late Box<dynamic> historyBox;

  setUp(() async {
    hiveDirectory = await Directory.systemTemp.createTemp(
      'generation-history-storage-test-',
    );
    imageDirectory = Directory(p.join(hiveDirectory.path, 'images'));
    Hive.init(hiveDirectory.path);
    historyBox = await Hive.openBox<dynamic>(StorageKeys.historyBox);
  });

  tearDown(() async {
    GeneratedImageFileCache.clear();
    await Hive.close();
    if (await hiveDirectory.exists()) {
      await hiveDirectory.delete(recursive: true);
    }
  });

  GenerationHistoryStorageService storage({bool enabled = true}) =>
      GenerationHistoryStorageService(
        enabled: enabled,
        directory: () async => imageDirectory,
      );

  File imageFile(String id) => File(p.join(imageDirectory.path, '$id.png'));

  List<String> storedFiles() => imageDirectory.existsSync()
      ? (imageDirectory
            .listSync()
            .whereType<File>()
            .map((file) => p.basename(file.path))
            .toList()
          ..sort())
      : const [];

  GeneratedImage image(String id, {int byte = 1}) {
    return GeneratedImage(
      id: id,
      bytes: Uint8List.fromList([byte, byte + 1, byte + 2]),
      width: 64,
      height: 96,
      createdAt: DateTime.utc(2026, 8, 26, 12, byte),
      filePath: '/images/$id.png',
      preserveOriginalBytesOnSave: true,
      fixedTagUsageSnapshot: const FixedTagUsageSnapshot(
        entries: [
          FixedTagUsageEntry(
            fixedTagId: 'fixed-a',
            name: 'A',
            content: 'masterpiece',
            weight: 1,
            renderedContent: 'masterpiece',
            position: FixedTagPosition.prefix,
            promptType: FixedTagPromptType.positive,
            order: 0,
          ),
        ],
      ),
    );
  }

  test('每张图存成独立文件，记录只留元数据，并按顺序恢复', () async {
    final service = storage();
    final first = image('first', byte: 3);
    final second = image('second', byte: 7);

    final stored = await service.persistImages(
      changedImages: [first, second],
      order: [second.id, first.id],
    );

    expect(stored, {
      'first': imageFile('first').path,
      'second': imageFile('second').path,
    });
    expect(await imageFile('second').readAsBytes(), second.bytes);
    final record = Map<dynamic, dynamic>.from(
      historyBox.get('generation_history_v1_record_second') as Map,
    );
    expect(record, isNot(contains('bytes')));
    expect(record['file'], 'second.png');

    final restored = await storage().load();
    expect(restored.map((item) => item.id), ['second', 'first']);
    expect(restored.first.isStored, isTrue);
    expect(restored.first.storedPath, imageFile('second').path);
    expect(restored.first.bytes, second.bytes);
    expect(restored.first.width, second.width);
    expect(restored.first.height, second.height);
    expect(restored.first.createdAt, second.createdAt);
    expect(restored.first.filePath, second.filePath);
    expect(restored.first.preserveOriginalBytesOnSave, isTrue);
    expect(
      restored.first.fixedTagUsageSnapshot?.entries.single.fixedTagId,
      'fixed-a',
    );
  });

  test('已经存成文件的图再次保存时不重写文件', () async {
    final service = storage();
    await service.persistImages(
      changedImages: [image('a')],
      order: const ['a'],
    );
    final restored = (await service.load()).single;
    final writtenAt = imageFile('a').lastModifiedSync();

    await service.persistImages(changedImages: [restored], order: const ['a']);

    expect(imageFile('a').lastModifiedSync(), writtenAt);
    expect(storedFiles(), ['a.png']);
  });

  test('comparison source is not persisted or restored with history', () async {
    final sourceBytes = Uint8List.fromList(
      img.encodePng(img.Image(width: 32, height: 48)),
    );
    final persisted = GeneratedImage(
      id: 'comparison',
      bytes: Uint8List.fromList([1, 2, 3]),
      width: 64,
      height: 96,
      comparisonSource: ImageComparisonSource.fromBytes(sourceBytes),
    );

    await storage().persistImages(
      changedImages: [persisted],
      order: [persisted.id],
    );

    final raw = Map<dynamic, dynamic>.from(
      historyBox.get('generation_history_v1_record_comparison') as Map,
    );
    expect(raw, isNot(contains('comparisonSource')));
    expect(raw, isNot(contains('comparisonSourceBytes')));

    final restored = await storage().load();
    expect(restored, hasLength(1));
    expect(restored.single.comparisonSource, isNull);
  });

  test('重叠写入按顺序执行，移出顺序的记录连文件一起删除', () async {
    final service = storage();

    final initialWrite = service.persistImages(
      changedImages: [image('first', byte: 1)],
      order: const ['first'],
    );
    final replacementWrite = service.persistImages(
      changedImages: [image('second', byte: 5)],
      order: const ['second'],
    );
    await Future.wait([initialWrite, replacementWrite]);

    expect((await service.load()).map((item) => item.id), ['second']);
    expect(
      historyBox.containsKey('generation_history_v1_record_first'),
      isFalse,
    );
    expect(storedFiles(), ['second.png']);
  });

  test('最多保留 200 条，超出的最旧结果永久删除', () async {
    final service = storage();
    final ids = [for (var i = 0; i < 200; i++) 'image-$i'];
    await service.persistImages(
      changedImages: [for (final id in ids) image(id)],
      order: ids,
    );
    expect(storedFiles(), hasLength(200));

    // 新结果排在最前，最旧的一条被挤出。
    await service.persistImages(
      changedImages: [image('newest')],
      order: ['newest', ...ids],
    );

    expect(GenerationHistoryStorageService.maxEntries, 200);
    expect(storedFiles(), hasLength(200));
    expect(imageFile('newest').existsSync(), isTrue);
    expect(imageFile('image-199').existsSync(), isFalse);
    expect(
      historyBox.containsKey('generation_history_v1_record_image-199'),
      isFalse,
    );
    final restored = await service.load();
    expect(restored, hasLength(200));
    expect(restored.first.id, 'newest');
    expect(restored.last.id, 'image-198');
  });

  test('旧版把图片字节存在记录里，首次加载时迁移成文件', () async {
    final bytes = Uint8List.fromList([4, 5, 6]);
    await historyBox.put('generation_history_v1_order', ['legacy']);
    await historyBox.put('generation_history_v1_record_legacy', {
      'bytes': bytes,
      'width': 32,
      'height': 48,
      'createdAt': DateTime.utc(2026, 8, 26).toIso8601String(),
      'kind': GeneratedImageKind.completed.name,
    });

    final restored = await storage().load();

    expect(restored.single.id, 'legacy');
    expect(restored.single.bytes, bytes);
    expect(await imageFile('legacy').readAsBytes(), bytes);
    final record = Map<dynamic, dynamic>.from(
      historyBox.get('generation_history_v1_record_legacy') as Map,
    );
    expect(record, isNot(contains('bytes')));
    expect(record['file'], 'legacy.png');

    // 迁移后再加载直接读文件。
    GeneratedImageFileCache.clear();
    expect((await storage().load()).single.bytes, bytes);
  });

  test('加载时丢弃无效、孤立的记录和没有记录的文件', () async {
    await imageDirectory.create(recursive: true);
    await imageFile('valid').writeAsBytes([1, 2, 3]);
    await imageFile('stray').writeAsBytes([7]);
    await File('${imageFile('half').path}.part').writeAsBytes([8]);
    await historyBox.put('generation_history_v1_order', [
      'valid',
      'missing',
      'invalid',
      'gone',
    ]);
    await historyBox.put('generation_history_v1_record_valid', {
      'file': 'valid.png',
      'width': 32,
      'height': 48,
      'createdAt': DateTime.utc(2026, 8, 26).toIso8601String(),
      'kind': GeneratedImageKind.completed.name,
    });
    await historyBox.put('generation_history_v1_record_invalid', {
      'bytes': Uint8List(0),
      'width': 0,
      'height': 0,
    });
    // 记录还在，文件已经没了。
    await historyBox.put('generation_history_v1_record_gone', {
      'file': 'gone.png',
      'width': 1,
      'height': 1,
    });
    await historyBox.put('generation_history_v1_record_orphan', {
      'file': 'orphan.png',
      'width': 1,
      'height': 1,
    });

    final service = storage();
    final restored = await service.load();
    await service.flush();

    expect(restored.map((item) => item.id), ['valid']);
    expect(historyBox.get('generation_history_v1_order'), ['valid']);
    for (final id in ['invalid', 'gone', 'orphan']) {
      expect(
        historyBox.containsKey('generation_history_v1_record_$id'),
        isFalse,
        reason: id,
      );
    }
    expect(storedFiles(), ['valid.png']);
  });

  test('清空历史同时删除图片文件', () async {
    final service = storage();
    await service.persistImages(
      changedImages: [image('a'), image('b')],
      order: const ['a', 'b'],
    );

    await service.clear();

    expect(await service.load(), isEmpty);
    expect(storedFiles(), isEmpty);
  });

  test('disabled storage remains a no-op', () async {
    final service = storage(enabled: false);

    final stored = await service.persistImages(
      changedImages: [image('ignored')],
      order: const ['ignored'],
    );
    await service.clear();

    expect(stored, isEmpty);
    expect(await service.load(), isEmpty);
    expect(historyBox.keys, isEmpty);
    expect(storedFiles(), isEmpty);
  });
}
