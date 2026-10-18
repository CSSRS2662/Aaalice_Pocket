import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nai_launcher/data/models/gallery/local_image_record.dart';
import 'package:nai_launcher/data/services/gallery/gallery_filter_service.dart';
import 'package:nai_launcher/data/services/gallery/gallery_image_file_deleter.dart';
import 'package:nai_launcher/data/services/gallery/unified_gallery_service.dart';
import 'package:nai_launcher/presentation/providers/local_gallery_provider.dart';

import '../../helpers/memory_system_album.dart';

void main() {
  late _FavoritesGalleryService service;
  late _RecordingDeleter deleter;

  setUp(() {
    service = _FavoritesGalleryService(
      files: ['a.png', 'b.png', 'c.png'],
      favorites: {'a.png'},
    );
    deleter = _RecordingDeleter();
  });

  ProviderContainer createContainer() {
    final container = ProviderContainer(
      overrides: [
        galleryServiceProvider.overrideWith(() => _StubGalleryService(service)),
        galleryImageFileDeleterProvider.overrideWithValue(deleter),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('图库只放收藏：初始与清除筛选后都保留收藏条件', () async {
    final container = createContainer();
    final notifier = container.read(localGalleryNotifierProvider.notifier);
    FilterCriteria criteria() =>
        container.read(localGalleryNotifierProvider).filterCriteria;

    expect(criteria().showFavoritesOnly, isTrue);
    await notifier.initialize();
    expect(service.applied, isNotEmpty);
    expect(service.applied.first.showFavoritesOnly, isTrue);

    await notifier.setShowFavoritesOnly(false);
    expect(criteria().showFavoritesOnly, isTrue);

    await notifier.setSearchQuery('cat');
    expect(container.read(localGalleryNotifierProvider).hasUserFilters, isTrue);

    await notifier.clearAllFilters();
    expect(criteria(), LocalGalleryNotifier.favoritesOnly);
    expect(
      container.read(localGalleryNotifierProvider).hasUserFilters,
      isFalse,
    );
    expect(
      service.applied.where((applied) => !applied.showFavoritesOnly),
      isEmpty,
    );
  });

  test('取消收藏后等待片刻再删除文件并移出图库', () {
    fakeAsync((async) {
      final container = createContainer();
      final notifier = container.read(localGalleryNotifierProvider.notifier);

      late bool favorite;
      notifier.toggleFavorite('a.png').then((value) => favorite = value);
      async.flushMicrotasks();

      expect(favorite, isFalse);
      expect(notifier.isRemovalPending('a.png'), isTrue);
      async.elapse(
        LocalGalleryNotifier.unfavoriteRemovalDelay -
            const Duration(milliseconds: 1),
      );
      expect(deleter.deleted, isEmpty);

      async.elapse(const Duration(milliseconds: 1));
      async.flushMicrotasks();

      expect(deleter.deleted, ['a.png']);
      expect(service.removed, [
        ['a.png'],
      ]);
      expect(notifier.isRemovalPending('a.png'), isFalse);
    });
  });

  test('撤销（重新收藏）后不删除', () {
    fakeAsync((async) {
      final container = createContainer();
      final notifier = container.read(localGalleryNotifierProvider.notifier);

      notifier.toggleFavorite('a.png');
      async.flushMicrotasks();
      notifier.toggleFavorite('a.png');
      async.flushMicrotasks();

      expect(notifier.isRemovalPending('a.png'), isFalse);
      async.elapse(LocalGalleryNotifier.unfavoriteRemovalDelay * 2);
      async.flushMicrotasks();

      expect(deleter.deleted, isEmpty);
      expect(service.favorites, contains('a.png'));
    });
  });

  test('删除前已在别处重新收藏的图保留', () {
    fakeAsync((async) {
      final container = createContainer();
      final notifier = container.read(localGalleryNotifierProvider.notifier);

      notifier.toggleFavorite('a.png');
      async.flushMicrotasks();
      service.favorites.add('a.png');
      async.elapse(LocalGalleryNotifier.unfavoriteRemovalDelay);
      async.flushMicrotasks();

      expect(deleter.deleted, isEmpty);
    });
  });

  test('一键清理只删除仍未收藏的图片', () async {
    final container = createContainer();
    final notifier = container.read(localGalleryNotifierProvider.notifier);

    final found = await notifier.findUnfavoritedImages();
    expect(found, ['b.png', 'c.png']);

    // 确认期间又收藏了 c。
    service.favorites.add('c.png');
    final result = await notifier.deleteUnfavoritedImages(found);

    expect(result.deletedPaths, ['b.png']);
    expect(result.failedCount, 0);
    expect(deleter.deleted, ['b.png']);
    expect(service.removed, [
      ['b.png'],
    ]);
  });
}

class _RecordingDeleter extends GalleryImageFileDeleter {
  _RecordingDeleter() : super(MemorySettingsStorage());

  final deleted = <String>[];

  @override
  Future<bool> delete(String path) async {
    deleted.add(path);
    return true;
  }
}

class _FavoritesGalleryService extends Mock implements LocalGalleryService {
  _FavoritesGalleryService({required this.files, required this.favorites});

  final List<String> files;
  final Set<String> favorites;
  final applied = <FilterCriteria>[];
  final removed = <List<String>>[];

  @override
  bool get isInitialized => true;

  @override
  int get totalCount => files.length;

  @override
  int get filteredCount => favorites.length;

  @override
  FilterCriteria get currentFilter =>
      applied.isEmpty ? const FilterCriteria() : applied.last;

  @override
  Future<void> applyFilter(FilterCriteria criteria) async {
    applied.add(criteria);
  }

  @override
  Future<List<LocalImageRecord>> getPage(int page, {int? pageSize}) async =>
      const [];

  @override
  Future<bool> toggleFavorite(String filePath) async {
    if (!favorites.remove(filePath)) favorites.add(filePath);
    return favorites.contains(filePath);
  }

  @override
  Future<bool> isFavorite(String filePath) async =>
      favorites.contains(filePath);

  @override
  Future<int> getFavoriteCount() async => favorites.length;

  @override
  Future<int> removeDeletedImagesImmediately(List<String> filePaths) async {
    removed.add(filePaths);
    files.removeWhere(filePaths.contains);
    return filePaths.length;
  }

  @override
  Future<LocalGalleryQueryPage> queryPage({
    required int page,
    int pageSize = 50,
    String searchQuery = '',
    bool favoritesOnly = false,
  }) async {
    final matching = [
      for (final path in files)
        if (!favoritesOnly || favorites.contains(path)) path,
    ];
    final start = page * pageSize;
    return LocalGalleryQueryPage(
      records: [
        for (final path in matching.skip(start).take(pageSize))
          LocalImageRecord(path: path, size: 1, modifiedAt: DateTime(2026)),
      ],
      page: page,
      pageSize: pageSize,
      totalCount: matching.length,
    );
  }

  @override
  Future<void> dispose() async {}
}

class _StubGalleryService extends GalleryService {
  _StubGalleryService(this.service);

  final LocalGalleryService service;

  @override
  LocalGalleryService build() => service;

  @override
  Future<void> ensureInitialized() async {}
}
