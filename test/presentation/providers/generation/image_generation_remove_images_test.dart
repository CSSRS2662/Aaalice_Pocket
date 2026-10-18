import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_lib;
import 'package:nai_launcher/core/storage/local_storage_service.dart';
import 'package:nai_launcher/data/models/gallery/gallery_index_admission.dart';
import 'package:nai_launcher/data/models/image/image_params.dart';
import 'package:nai_launcher/data/models/image/image_stream_chunk.dart';
import 'package:nai_launcher/presentation/providers/image_generation_provider.dart';
import 'package:nai_launcher/presentation/providers/local_gallery_provider.dart';
import 'package:nai_launcher/presentation/providers/system_album_provider.dart';
import 'package:nai_launcher/presentation/services/generation_history_storage_service.dart';

import '../../../helpers/memory_system_album.dart';

void main() {
  late Directory directory;
  late ProviderContainer container;
  late _RecordingGalleryNotifier gallery;
  late _RecordingHistoryStorage historyStorage;
  late MemoryAlbumTarget album;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('nai_remove_images_');
    gallery = _RecordingGalleryNotifier();
    historyStorage = _RecordingHistoryStorage();
    album = MemoryAlbumTarget();
  });

  tearDown(() async {
    container.dispose();
    await historyStorage.flush();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  ImageGenerationNotifier notifierWith(ImageGenerationState initial) {
    container = ProviderContainer(
      overrides: [
        imageGenerationNotifierProvider.overrideWith(
          () => _SeededImageGenerationNotifier(initial),
        ),
        localGalleryNotifierProvider.overrideWith(() => gallery),
        localStorageServiceProvider.overrideWithValue(_MemoryStorage()),
        generationHistoryStorageServiceProvider.overrideWithValue(
          historyStorage,
        ),
        systemAlbumProvider.overrideWithValue(memorySystemAlbum(album)),
      ],
    );
    return container.read(imageGenerationNotifierProvider.notifier);
  }

  Future<String> savedFile(String name) async {
    final file = File('${directory.path}/$name');
    await file.writeAsBytes(_pngBytes);
    return file.path;
  }

  test('从当前批次、历史与中央预览移除，收藏进图库的文件保留', () async {
    final linkedPath = await savedFile('linked.png');
    final removed = _image('removed').copyWithFilePath(linkedPath);
    final kept = _image('kept');
    final notifier = notifierWith(
      ImageGenerationState(
        status: GenerationStatus.error,
        errorMessage: 'previous failure',
        currentImages: [removed, kept],
        history: [removed, kept],
        displayImages: [removed, kept],
        completionPreviews: {
          'removed': StreamPreviewFrame(bytes: _pngBytes),
          'kept': StreamPreviewFrame(bytes: _pngBytes),
        },
      ),
    );

    final result = await notifier.removeImages(['removed']);

    final state = container.read(imageGenerationNotifierProvider);
    expect(state.currentImages, [kept]);
    expect(state.history, [kept]);
    expect(state.displayImages, [kept]);
    expect(state.completionPreviews.keys, ['kept']);
    expect(state.errorMessage, 'previous failure');
    expect(result.removedCount, 1);
    // 图库只放收藏，只有取消收藏才删文件。
    expect(await File(linkedPath).exists(), isTrue);
    expect(gallery.removals, isEmpty);
    expect(gallery.refreshCount, 0);
    await historyStorage.flush();
    expect(historyStorage.lastOrder, ['kept']);
  });

  test('只移除记录时不触碰图库', () async {
    final notifier = notifierWith(
      ImageGenerationState(history: [_image('a'), _image('b')]),
    );

    final result = await notifier.removeImages(['a']);

    expect(
      container.read(imageGenerationNotifierProvider).history.map((i) => i.id),
      ['b'],
    );
    expect(result.removedCount, 1);
    expect(gallery.removals, isEmpty);
    expect(gallery.refreshCount, 0);
  });

  test('未知 id 不改动状态', () async {
    final initial = ImageGenerationState(history: [_image('a')]);
    final notifier = notifierWith(initial);

    final result = await notifier.removeImages(['missing']);

    expect(result.removedCount, 0);
    expect(container.read(imageGenerationNotifierProvider), same(initial));
  });

  test('删除后才回写的收藏路径不再挂回记录，收藏的文件保留', () async {
    final notifier = notifierWith(
      ImageGenerationState(history: [_image('a'), _image('b')]),
    );
    await notifier.removeImages(['a']);
    final latePath = await savedFile('late.png');

    notifier.updateImageFilePath('a', latePath);

    final state = container.read(imageGenerationNotifierProvider);
    expect(state.findImageById('a'), isNull);
    expect(await File(latePath).exists(), isTrue);
    expect(gallery.removals, isEmpty);
  });

  test('排队保存期间被删除的结果不再写进系统相册', () async {
    final notifier = notifierWith(const ImageGenerationState());
    // 收藏写入同一张图时，自动保存排在它后面；排队期间删除这条结果。
    final favoriteWrite = Completer<void>();
    final subscription = container.listen<ImageGenerationState>(
      imageGenerationNotifierProvider,
      (previous, next) {
        if (next.history.isEmpty || (previous?.history.isNotEmpty ?? false)) {
          return;
        }
        final id = next.history.first.id;
        unawaited(notifier.queueImageSave(id, () => favoriteWrite.future));
        scheduleMicrotask(() async {
          await notifier.removeImages([id]);
          favoriteWrite.complete();
        });
      },
    );
    addTearDown(subscription.close);

    final savedPath = await notifier.registerExternalImage(
      _pngBytes,
      params: const ImageParams(seed: 123),
      saveToLocal: true,
      embedNaiMetadata: false,
    );

    expect(savedPath, isNull);
    expect(container.read(imageGenerationNotifierProvider).history, isEmpty);
    expect(album.images, isEmpty);
  });

  test('保存只写系统相册，返回相册里的位置', () async {
    final notifier = notifierWith(const ImageGenerationState());

    final savedPath = await notifier.registerExternalImage(
      _pngBytes,
      params: const ImageParams(seed: 123),
      saveToLocal: true,
      embedNaiMetadata: false,
    );

    expect(savedPath, album.images.keys.single);
    expect(gallery.admissions, isEmpty);
    final remaining = await directory
        .list(recursive: true)
        .where((entity) => entity is File)
        .toList();
    expect(remaining, isEmpty);
  });
}

final _pngBytes = Uint8List.fromList(
  image_lib.encodePng(image_lib.Image(width: 2, height: 2)),
);

GeneratedImage _image(String id) =>
    GeneratedImage(id: id, bytes: _pngBytes, width: 2, height: 2);

class _SeededImageGenerationNotifier extends ImageGenerationNotifier {
  _SeededImageGenerationNotifier(this.initial);

  final ImageGenerationState initial;

  @override
  ImageGenerationState build() {
    super.build();
    return initial;
  }
}

class _RecordingGalleryNotifier extends LocalGalleryNotifier {
  var refreshCount = 0;
  final removals = <List<String>>[];
  final admissions = <List<String>>[];

  @override
  LocalGalleryState build() => const LocalGalleryState(isInitialized: true);

  @override
  Future<void> refresh({bool scan = true}) async => refreshCount++;

  @override
  Future<void> removeDeletedImages(List<String> filePaths) async =>
      removals.add(filePaths);

  @override
  Future<GalleryIndexAdmission> addNewlySavedImages(
    List<String> filePaths,
  ) async {
    admissions.add(filePaths);
    return GalleryIndexAdmission.added;
  }
}

class _RecordingHistoryStorage extends GenerationHistoryStorageService {
  _RecordingHistoryStorage() : super(enabled: false);

  List<String>? lastOrder;

  @override
  Future<Map<String, String>> persistImages({
    required Iterable<GeneratedImage> changedImages,
    required List<String> order,
  }) {
    lastOrder = order;
    return super.persistImages(changedImages: changedImages, order: order);
  }
}

class _MemoryStorage extends LocalStorageService {
  final values = <String, Object?>{};

  @override
  T? getSetting<T>(String key, {T? defaultValue}) =>
      (values[key] as T?) ?? defaultValue;

  @override
  Future<void> setSetting<T>(String key, T value) async {
    values[key] = value;
  }
}
