import '../../../core/utils/app_logger.dart';
import 'gallery_path_utils.dart';
import 'local_gallery_service.dart';

/// 清理的结果：删掉的路径和删除失败的数量。
class GalleryUnfavoritedCleanupResult {
  const GalleryUnfavoritedCleanupResult({
    required this.deletedPaths,
    required this.failedCount,
  });

  final List<String> deletedPaths;
  final int failedCount;
}

/// 图库只放收藏。旧版本把每次保存都写进了图库，这里找出这些没收藏的图片，
/// 并在用户确认后永久删除。
class GalleryUnfavoritedCleanup {
  GalleryUnfavoritedCleanup({
    required LocalGalleryService service,
    required Future<bool> Function(String path) deleteFile,
  }) : _service = service,
       _deleteFile = deleteFile;

  static const _pageSize = 500;

  final LocalGalleryService _service;
  final Future<bool> Function(String path) _deleteFile;

  /// 图库里所有没收藏的图片路径。
  Future<List<String>> find() async {
    final favorites = {
      for (final path in await _paths(favoritesOnly: true))
        galleryFilePathKey(path),
    };
    return [
      for (final path in await _paths(favoritesOnly: false))
        if (!favorites.contains(galleryFilePathKey(path))) path,
    ];
  }

  /// 删除 [paths] 中仍未收藏的图片；删除前再查一次，期间刚收藏的会保留。
  Future<GalleryUnfavoritedCleanupResult> delete(List<String> paths) async {
    final deleted = <String>[];
    var failed = 0;
    for (final path in paths) {
      try {
        if (await _service.isFavorite(path)) continue;
        await _deleteFile(path);
        deleted.add(path);
      } catch (error, stackTrace) {
        failed++;
        AppLogger.e(
          'Deleting unfavorited image failed: $path',
          error,
          stackTrace,
          'GalleryUnfavoritedCleanup',
        );
      }
    }
    return GalleryUnfavoritedCleanupResult(
      deletedPaths: deleted,
      failedCount: failed,
    );
  }

  Future<List<String>> _paths({required bool favoritesOnly}) async {
    final paths = <String>[];
    for (var page = 0; ; page++) {
      final result = await _service.queryPage(
        page: page,
        pageSize: _pageSize,
        favoritesOnly: favoritesOnly,
      );
      paths.addAll(result.records.map((record) => record.path));
      if (!result.hasMore) return paths;
    }
  }
}
