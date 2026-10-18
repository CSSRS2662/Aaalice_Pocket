import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import '../../../core/utils/app_logger.dart';

/// Bytes of history images that live in files rather than in memory.
///
/// Holds the most recently used images up to [budgetBytes], so a long history
/// does not keep every PNG in memory. [prefetch] reads ahead off the UI
/// thread; [read] is the synchronous fallback for an image nobody prefetched.
abstract final class GeneratedImageFileCache {
  static const int budgetBytes = 96 * 1024 * 1024;

  static final LinkedHashMap<String, Uint8List> _cache = LinkedHashMap();
  static final Map<String, Future<void>> _pending = {};
  static int _size = 0;

  static Uint8List read(String path) {
    final cached = _touch(path);
    if (cached != null) return cached;
    try {
      return _put(path, File(path).readAsBytesSync());
    } on Object catch (error) {
      AppLogger.w('History image $path is unreadable: $error', 'History');
      return Uint8List(0);
    }
  }

  /// Loads [paths] into the cache without blocking the UI thread.
  static Future<void> prefetch(Iterable<String> paths) => Future.wait([
    for (final path in paths)
      if (!_cache.containsKey(path))
        _pending[path] ??= File(path)
            .readAsBytes()
            .then<void>((bytes) => _put(path, bytes))
            .catchError((Object _) {})
            // A block body: returning the removed future would wait on itself.
            .whenComplete(() {
              _pending.remove(path);
            }),
  ]);

  static bool isCached(String path) => _cache.containsKey(path);

  /// Caches [bytes] already in memory as the content of [path].
  static void remember(String path, Uint8List bytes) => _put(path, bytes);

  static void evict(String path) {
    final removed = _cache.remove(path);
    if (removed != null) _size -= removed.length;
  }

  static void clear() {
    _cache.clear();
    _size = 0;
  }

  static Uint8List? _touch(String path) {
    final cached = _cache.remove(path);
    if (cached != null) _cache[path] = cached;
    return cached;
  }

  static Uint8List _put(String path, Uint8List bytes) {
    final existing = _touch(path);
    if (existing != null) return existing;
    _cache[path] = bytes;
    _size += bytes.length;
    while (_size > budgetBytes && _cache.length > 1) {
      final oldest = _cache.keys.first;
      _size -= _cache.remove(oldest)!.length;
    }
    return bytes;
  }
}
