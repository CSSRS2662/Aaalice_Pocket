import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/constants/storage_keys.dart';
import '../../core/utils/app_logger.dart';
import '../../data/models/gallery/nai_image_metadata.dart';
import '../../data/models/fixed_tag/fixed_tag_usage_snapshot.dart';
import '../providers/generation/generated_image_file_cache.dart';
import '../providers/generation/generation_models.dart';

/// Tests and embedders opt in explicitly so independently-created provider
/// containers cannot leak history into one another through a shared Hive box.
final generationSessionPersistenceEnabledProvider = Provider<bool>(
  (ref) => false,
);

final generationHistoryStorageServiceProvider =
    Provider<GenerationHistoryStorageService>(
      (ref) => GenerationHistoryStorageService(
        enabled: ref.watch(generationSessionPersistenceEnabledProvider),
      ),
    );

/// Durable backing store for the bounded generation history.
///
/// Each PNG lives in its own file in [directory]; Hive keeps the order index
/// and one small metadata record per image, so loading the history does not
/// read every image into memory. The order index is committed last; an
/// interrupted write can therefore leave only an orphan record or file,
/// which is removed during the next load without losing an indexed image.
/// Records from before files carry the PNG themselves and move to files on
/// their first load.
class GenerationHistoryStorageService {
  GenerationHistoryStorageService({
    this.enabled = true,
    Future<Directory> Function()? directory,
  }) : _resolveDirectory = directory ?? _defaultDirectory;

  static const _orderKey = 'generation_history_v1_order';
  static const _recordPrefix = 'generation_history_v1_record_';
  static const _fileKey = 'file';

  /// History keeps the newest results; older ones are deleted for good.
  static const maxEntries = 200;

  final bool enabled;
  final Future<Directory> Function() _resolveDirectory;
  Future<Directory>? _directory;
  Future<void> _pendingWrite = Future<void>.value();

  static Future<Directory> _defaultDirectory() async => Directory(
    p.join((await getApplicationSupportDirectory()).path, 'generation_history'),
  );

  Future<Directory> get _imageDirectory => _directory ??= () async {
    final directory = await _resolveDirectory();
    await directory.create(recursive: true);
    return directory;
  }();

  Box<dynamic>? get _box {
    if (!enabled || !Hive.isBoxOpen(StorageKeys.historyBox)) {
      return null;
    }
    return Hive.box<dynamic>(StorageKeys.historyBox);
  }

  Future<List<GeneratedImage>> load() async {
    final box = _box;
    if (box == null) return const [];
    final directory = await _imageDirectory;

    final rawOrder = box.get(_orderKey);
    final order = rawOrder is List
        ? rawOrder.whereType<String>().take(maxEntries).toList()
        : <String>[];
    final images = <GeneratedImage>[];
    final validIds = <String>[];
    var migrated = false;

    for (final id in order) {
      try {
        final raw = box.get('$_recordPrefix$id');
        if (raw is! Map) continue;
        final record = Map<dynamic, dynamic>.from(raw);
        if (record[_fileKey] is! String) {
          if (!await _moveBytesToFile(box, directory, id, record)) continue;
          migrated = true;
        }
        final path = p.join(directory.path, record[_fileKey] as String);
        if (!await File(path).exists()) continue;
        final image = _decodeRecord(id, record, path);
        if (image == null) continue;
        images.add(image);
        validIds.add(id);
      } catch (error, stackTrace) {
        AppLogger.w(
          'Skipping invalid persisted generation image $id: $error',
          'GenerationHistory',
        );
        AppLogger.d(stackTrace.toString(), 'GenerationHistory');
      }
    }

    final indexedKeys = validIds.map((id) => '$_recordPrefix$id').toSet();
    final staleKeys = box.keys
        .whereType<String>()
        .where(
          (key) => key.startsWith(_recordPrefix) && !indexedKeys.contains(key),
        )
        .toList();
    if (staleKeys.isNotEmpty || validIds.length != order.length) {
      await box.put(_orderKey, validIds);
      await box.deleteAll(staleKeys);
    }
    // Queued behind pending writes, so a file being written is never swept.
    await _enqueue(() async {
      final indexed = (box.get(_orderKey) as List?)?.whereType<String>();
      await _deleteOrphanFiles(directory, {
        for (final id in indexed ?? const <String>[]) _fileName(id),
      });
    });
    // Records that carried their PNG leave the box full of free space.
    if (migrated || staleKeys.isNotEmpty) await box.compact();

    return images;
  }

  /// Writes the images in [changedImages] that are still in [order] and
  /// returns where each one's PNG now lives, keyed by image id.
  Future<Map<String, String>> persistImages({
    required Iterable<GeneratedImage> changedImages,
    required List<String> order,
  }) {
    final boundedOrder = List<String>.unmodifiable(
      order.toSet().take(maxEntries),
    );
    final retained = boundedOrder.toSet();
    final changed = [
      for (final image in changedImages)
        if (retained.contains(image.id)) image,
    ];
    final stored = <String, String>{};

    return _enqueue(() async {
      final box = _box;
      if (box == null) return;
      final directory = await _imageDirectory;

      final previousOrder =
          (box.get(_orderKey) as List?)?.whereType<String>().toSet() ??
          const <String>{};
      final records = <String, Map<String, dynamic>>{};
      for (final image in changed) {
        final path = p.join(directory.path, _fileName(image.id));
        if (image.storedPath != path && !await File(path).exists()) {
          await _writeAtomically(path, image.bytes);
        }
        records['$_recordPrefix${image.id}'] = _encodeRecord(image);
        stored[image.id] = path;
      }
      if (records.isNotEmpty) {
        await box.putAll(records);
      }
      await box.put(_orderKey, boundedOrder);

      final evicted = previousOrder.difference(retained);
      if (evicted.isNotEmpty) {
        await box.deleteAll(evicted.map((id) => '$_recordPrefix$id'));
        for (final id in evicted) {
          await _deleteImageFile(p.join(directory.path, _fileName(id)));
        }
      }
    }).then((_) => stored);
  }

  Future<void> clear() {
    return _enqueue(() async {
      final box = _box;
      if (box == null) return;
      final recordKeys = box.keys
          .whereType<String>()
          .where((key) => key.startsWith(_recordPrefix))
          .toList();
      await box.delete(_orderKey);
      if (recordKeys.isNotEmpty) {
        await box.deleteAll(recordKeys);
      }
      await _deleteOrphanFiles(await _imageDirectory, const {});
    });
  }

  Future<void> flush() => _pendingWrite;

  Future<void> _enqueue(Future<void> Function() operation) {
    final next = _pendingWrite.then((_) => operation());
    _pendingWrite = next.catchError((Object error, StackTrace stackTrace) {
      AppLogger.e('Failed to persist generation history', error, stackTrace);
    });
    return next;
  }

  static String _fileName(String id) => '$id.png';

  Future<bool> _moveBytesToFile(
    Box<dynamic> box,
    Directory directory,
    String id,
    Map<dynamic, dynamic> record,
  ) async {
    final raw = record['bytes'];
    final bytes = raw is Uint8List
        ? raw
        : raw is List<int>
        ? Uint8List.fromList(raw)
        : null;
    if (bytes == null || bytes.isEmpty) return false;
    await _writeAtomically(p.join(directory.path, _fileName(id)), bytes);
    record
      ..remove('bytes')
      ..[_fileKey] = _fileName(id);
    await box.put('$_recordPrefix$id', record);
    return true;
  }

  static Future<void> _writeAtomically(String path, Uint8List bytes) async {
    final partial = File('$path.part');
    await partial.writeAsBytes(bytes, flush: true);
    await partial.rename(path);
  }

  static Future<void> _deleteImageFile(String path) async {
    GeneratedImageFileCache.evict(path);
    try {
      await File(path).delete();
    } on PathNotFoundException {
      // Already gone.
    }
  }

  static Future<void> _deleteOrphanFiles(
    Directory directory,
    Set<String> keep,
  ) async {
    if (!await directory.exists()) return;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || keep.contains(p.basename(entity.path))) continue;
      await _deleteImageFile(entity.path);
    }
  }

  static Map<String, dynamic> _encodeRecord(GeneratedImage image) {
    return <String, dynamic>{
      _fileKey: _fileName(image.id),
      'width': image.width,
      'height': image.height,
      'createdAt': image.createdAt.toIso8601String(),
      'kind': image.kind.name,
      'metadata': image.metadata == null
          ? null
          : jsonEncode(image.metadata!.toJson()),
      'fixedTagUsageSnapshot': image.fixedTagUsageSnapshot == null
          ? null
          : jsonEncode(image.fixedTagUsageSnapshot!.toJson()),
      'preserveOriginalBytesOnSave': image.preserveOriginalBytesOnSave,
      'filePath': image.filePath,
    };
  }

  static GeneratedImage? _decodeRecord(
    String id,
    Map<dynamic, dynamic> raw,
    String storedPath,
  ) {
    final width = raw['width'];
    final height = raw['height'];
    if (width is! int || width <= 0 || height is! int || height <= 0) {
      return null;
    }

    final createdAt =
        DateTime.tryParse(raw['createdAt'] as String? ?? '') ?? DateTime.now();
    final kindName = raw['kind'] as String?;
    final kind = GeneratedImageKind.values.firstWhere(
      (value) => value.name == kindName,
      orElse: () => GeneratedImageKind.completed,
    );

    NaiImageMetadata? metadata;
    final metadataJson = raw['metadata'];
    if (metadataJson is String && metadataJson.isNotEmpty) {
      final decoded = jsonDecode(metadataJson);
      if (decoded is Map<String, dynamic>) {
        metadata = NaiImageMetadata.fromJson(decoded);
      } else if (decoded is Map) {
        metadata = NaiImageMetadata.fromJson(
          Map<String, dynamic>.from(decoded),
        );
      }
    }

    FixedTagUsageSnapshot? fixedTagUsageSnapshot;
    final fixedTagUsageJson = raw['fixedTagUsageSnapshot'];
    if (fixedTagUsageJson is String && fixedTagUsageJson.isNotEmpty) {
      final decoded = jsonDecode(fixedTagUsageJson);
      if (decoded is Map) {
        fixedTagUsageSnapshot = FixedTagUsageSnapshot.fromJson(
          Map<String, dynamic>.from(decoded),
        );
      }
    }

    return GeneratedImage.stored(
      id: id,
      storedPath: storedPath,
      width: width,
      height: height,
      createdAt: createdAt,
      kind: kind,
      metadata: metadata,
      fixedTagUsageSnapshot: fixedTagUsageSnapshot,
      preserveOriginalBytesOnSave:
          raw['preserveOriginalBytesOnSave'] as bool? ?? false,
      filePath: raw['filePath'] as String?,
    );
  }
}
