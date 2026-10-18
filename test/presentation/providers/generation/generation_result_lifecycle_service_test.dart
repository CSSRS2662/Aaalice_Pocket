import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:image/image.dart' as image_lib;
import 'package:nai_launcher/data/models/image/image_params.dart';
import 'package:nai_launcher/core/utils/image_save_utils.dart';
import 'package:nai_launcher/data/models/fixed_tag/fixed_tag_entry.dart';
import 'package:nai_launcher/data/models/fixed_tag/fixed_tag_prompt_type.dart';
import 'package:nai_launcher/data/models/fixed_tag/fixed_tag_usage_snapshot.dart';
import 'package:nai_launcher/data/models/gallery/gallery_index_admission.dart';
import 'package:nai_launcher/data/services/fixed_tag/fixed_tag_usage_record_store.dart';
import 'package:nai_launcher/data/services/metadata/hash_calculator.dart';
import 'package:nai_launcher/data/services/metadata/unified_metadata_parser.dart';
import 'package:nai_launcher/presentation/providers/generation/generation_models.dart';
import 'package:nai_launcher/presentation/providers/generation/generation_result_lifecycle_service.dart';
import 'package:nai_launcher/presentation/services/generation_history_storage_service.dart';

import '../../../helpers/memory_system_album.dart';

void main() {
  Uint8List pngBytes(int width) => Uint8List.fromList(
    image_lib.encodePng(image_lib.Image(width: width, height: 2)),
  );

  GeneratedImage result(Uint8List bytes) => GeneratedImage.create(
    bytes,
    width: 2,
    height: 2,
    preserveOriginalBytesOnSave: true,
  );

  GenerationResultLifecycleService serviceWith(MemoryAlbumTarget album) =>
      GenerationResultLifecycleService(
        GenerationResultLifecycleDependencies(
          historyStorage: GenerationHistoryStorageService(enabled: false),
          systemAlbum: memorySystemAlbum(album),
        ),
      );

  test('自动保存只写系统相册，逐张写入', () async {
    final album = MemoryAlbumTarget();
    final first = pngBytes(2);
    final second = pngBytes(3);

    final saved = await serviceWith(album).saveImages(
      [result(first), result(second)],
      const ImageParams(seed: 123),
      snapshot: const GenerationSaveSnapshot(),
    );

    expect(saved.albumLocations, album.images.keys.toList());
    expect(album.images.values, [first, second]);
    expect(album.fileNames, everyElement(endsWith('-123.png')));
    expect(saved.systemGalleryExportFailureCount, 0);
    // 图库只放收藏，自动保存不给结果挂图库路径。
    expect(saved.images.map((image) => image.filePath), [null, null]);
  });

  test('相册里已有的同一张图记为重复，不写第二份', () async {
    final album = MemoryAlbumTarget();
    final bytes = pngBytes(2);
    final service = serviceWith(album);

    final saved = await service.saveImages(
      [result(bytes), result(bytes)],
      const ImageParams(seed: 7),
      snapshot: const GenerationSaveSnapshot(),
    );

    expect(album.images, hasLength(1));
    expect(saved.albumLocations, [
      album.images.keys.single,
      album.images.keys.single,
    ]);
  });

  test('写入失败计入失败数，不影响其余结果', () async {
    final album = MemoryAlbumTarget()..failNextWrite = StateError('denied');

    final saved = await serviceWith(album).saveImages(
      [result(pngBytes(2)), result(pngBytes(3))],
      const ImageParams(seed: 456),
      snapshot: const GenerationSaveSnapshot(),
    );

    expect(saved.systemGalleryExportFailureCount, 1);
    expect(saved.albumLocations, hasLength(1));
    expect(album.images, hasLength(1));
  });

  group('固定词使用记录', () {
    late Directory hiveDirectory;

    setUp(() async {
      hiveDirectory = await Directory.systemTemp.createTemp(
        'nai_generation_fixed_usage_hive_',
      );
      Hive.init(hiveDirectory.path);
    });

    tearDown(() async {
      await Hive.close();
      await hiveDirectory.delete(recursive: true);
    });

    Future<Uint8List> novelAiBytes() =>
        ImageSaveUtils.rebuildImageBytesWithMetadata(
          imageBytes: pngBytes(2),
          params: const ImageParams(
            prompt: 'masterpiece, subject',
            width: 2,
            height: 2,
          ),
          actualSeed: 321,
        );

    test('自动保存不改写 NAI 字节，快照写入旁路记录库', () async {
      final album = MemoryAlbumTarget();
      final bytes = await novelAiBytes();
      const generatedSnapshot = FixedTagUsageSnapshot(
        entries: [
          FixedTagUsageEntry(
            fixedTagId: 'a',
            name: 'A',
            content: 'masterpiece',
            weight: 1,
            renderedContent: 'masterpiece',
            position: FixedTagPosition.prefix,
            promptType: FixedTagPromptType.positive,
            order: 0,
          ),
        ],
      );

      await serviceWith(album).saveImages(
        [
          GeneratedImage.create(
            bytes,
            width: 2,
            height: 2,
            fixedTagUsageSnapshot: generatedSnapshot,
          ),
        ],
        const ImageParams(prompt: 'changed later', seed: 999),
        snapshot: const GenerationSaveSnapshot(
          fixedTagUsageSnapshot: FixedTagUsageSnapshot(),
        ),
      );
      final saved = album.images.values.single;

      expect(saved, orderedEquals(bytes));
      final metadata = UnifiedMetadataParser.parseFromPng(saved).metadata!;
      expect(metadata.fixedTagUsageData, isNull);
      expect(
        FixedTagUsageRecordStore()
            .lookup(FileHashCalculator().calculateFromBytes(bytes))
            ?.entries
            .single
            .fixedTagId,
        'a',
      );
    });

    test('未启用固定词时同样记录空快照', () async {
      final album = MemoryAlbumTarget();
      final bytes = await novelAiBytes();

      await serviceWith(album).saveImages(
        [GeneratedImage.create(bytes, width: 2, height: 2)],
        const ImageParams(seed: 321),
        snapshot: const GenerationSaveSnapshot(
          fixedTagUsageSnapshot: FixedTagUsageSnapshot(),
        ),
      );

      expect(album.images, hasLength(1));
      final recorded = FixedTagUsageRecordStore().lookup(
        FileHashCalculator().calculateFromBytes(bytes),
      );
      expect(recorded, isNotNull);
      expect(recorded!.entries, isEmpty);
    });
  });

  group('GalleryIndexAdmission', () {
    test('批量结果取最坏的一项', () {
      expect(
        GalleryIndexAdmission.added.merge(GalleryIndexAdmission.alreadyIndexed),
        GalleryIndexAdmission.added,
      );
      expect(
        GalleryIndexAdmission.added.merge(GalleryIndexAdmission.failed),
        GalleryIndexAdmission.failed,
      );
      expect(
        GalleryIndexAdmission.deferred.merge(GalleryIndexAdmission.added),
        GalleryIndexAdmission.deferred,
      );
      expect(
        GalleryIndexAdmission.alreadyIndexed.merge(
          GalleryIndexAdmission.alreadyIndexed,
        ),
        GalleryIndexAdmission.alreadyIndexed,
      );
    });

    test('只有 failed 需要全量重扫', () {
      for (final admission in GalleryIndexAdmission.values) {
        expect(
          admission.requiresFullRescan,
          admission == GalleryIndexAdmission.failed,
          reason: '$admission',
        );
      }
    });

    test('索引已包含新图时才重取当前页', () {
      expect(GalleryIndexAdmission.added.isIndexed, isTrue);
      expect(GalleryIndexAdmission.alreadyIndexed.isIndexed, isTrue);
      expect(GalleryIndexAdmission.deferred.isIndexed, isFalse);
      expect(GalleryIndexAdmission.failed.isIndexed, isFalse);
    });
  });
}
