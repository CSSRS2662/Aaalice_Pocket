import 'package:flutter/foundation.dart';
import 'package:nai_launcher/core/services/system_album.dart';
import 'package:nai_launcher/core/storage/local_storage_service.dart';

/// 内存里的系统相册：记录每次写入，可模拟用户在相册里删图或写入失败。
class MemoryAlbumTarget implements SystemAlbumTarget {
  MemoryAlbumTarget({this.isPhotoAlbum = true});

  @override
  final bool isPhotoAlbum;

  final Map<String, Uint8List> images = {};
  final List<String> fileNames = [];

  /// 设置后，下一次写入抛出它。
  Object? failNextWrite;

  @override
  Future<String> write(Uint8List bytes, String fileName) async {
    final failure = failNextWrite;
    if (failure != null) {
      failNextWrite = null;
      throw failure;
    }
    fileNames.add(fileName);
    final location = 'album://${fileNames.length}/$fileName';
    images[location] = bytes;
    return location;
  }

  @override
  Future<bool> contains(String location) async => images.containsKey(location);

  /// 设置后，[find] 抛出它，模拟查询相册失败。
  Object? failFind;

  /// 按内容查找同一张图，模拟目标文件夹里已有的图片（包括旧版本存的）。
  @override
  Future<String?> find({
    required Uint8List bytes,
    required String sha256,
  }) async {
    if (failFind case final failure?) throw failure;
    for (final entry in images.entries) {
      if (listEquals(entry.value, bytes)) return entry.key;
    }
    return null;
  }
}

/// 纯内存的设置存储，供系统相册的去重记录使用。
class MemorySettingsStorage extends LocalStorageService {
  final Map<String, Object?> values = {};

  @override
  T? getSetting<T>(String key, {T? defaultValue}) =>
      (values.containsKey(key) ? values[key] : defaultValue) as T?;

  @override
  Future<void> setSetting<T>(String key, T value) async {
    values[key] = value;
  }

  @override
  Future<void> deleteSetting(String key) async {
    values.remove(key);
  }
}

SystemAlbum memorySystemAlbum(MemoryAlbumTarget target) =>
    SystemAlbum(storage: MemorySettingsStorage(), target: target);
