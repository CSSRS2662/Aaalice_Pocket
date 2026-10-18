import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/services/metadata/hash_calculator.dart';
import '../platform/platform_capabilities.dart';
import '../storage/local_storage_service.dart';
import '../utils/app_logger.dart';
import 'android_media_store_service.dart';

/// Result of [SystemAlbum.save]: where the image is, and whether this save
/// found it already there instead of writing it.
typedef SystemAlbumSave = ({String location, bool duplicate});

/// Where an album writes and finds images.
abstract interface class SystemAlbumTarget {
  /// The phone's shared photo album rather than a folder on disk.
  bool get isPhotoAlbum;

  /// Writes [bytes] as [fileName] and returns where they went.
  Future<String> write(Uint8List bytes, String fileName);

  /// Whether what [write] returned as [location] is still there.
  Future<bool> contains(String location);
}

/// Saving puts images here: the photo album on Android, an
/// "Aaalice NAI Launcher" folder in Downloads elsewhere. The in-app gallery
/// holds favorites only.
///
/// Each save is remembered by the content hash of its identity bytes, so
/// saving the same image again is reported as a duplicate while the album
/// still has it; once the user removes it there, saving writes it again.
/// The record stays on this device.
class SystemAlbum {
  SystemAlbum({required LocalStorageService storage, SystemAlbumTarget? target})
    : _storage = storage,
      target = target ?? defaultTarget();

  static const _registryKey = 'system_album_saves_v1';

  /// Saves remembered for duplicate checks; the oldest are forgotten first.
  static const maxRemembered = 4000;

  static final Map<String, Future<SystemAlbumSave>> _inFlight = {};

  /// Saves run one at a time, so the registry is never written twice at once.
  static Future<void> _queue = Future<void>.value();

  final LocalStorageService _storage;
  final SystemAlbumTarget target;

  static SystemAlbumTarget defaultTarget() =>
      PlatformCapabilities.current.supportsSystemGalleryExport
      ? const AndroidPhotoAlbumTarget()
      : FolderAlbumTarget(_defaultFolder);

  static Future<Directory> _defaultFolder() async {
    final base =
        await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    return Directory(p.join(base.path, 'Aaalice NAI Launcher'));
  }

  /// Saves [bytes] as [fileName] unless the album already has the image
  /// whose source is [identity] (by default [bytes]). [allowDuplicate]
  /// saves another copy anyway. [source] names the entry in the log.
  Future<SystemAlbumSave> save({
    required Uint8List bytes,
    required String fileName,
    required String source,
    Uint8List? identity,
    bool allowDuplicate = false,
  }) async {
    final hash = await FileHashCalculator().calculateFromBytesAsync(
      identity ?? bytes,
    );
    if (!allowDuplicate) {
      final pending = _inFlight[hash];
      if (pending != null) {
        try {
          final earlier = await pending;
          return (location: earlier.location, duplicate: true);
        } on Object {
          // That save failed; this one tries again.
        }
      }
    }
    final saving = _serially(
      () => _save(hash, bytes, fileName, source, allowDuplicate),
    );
    _inFlight[hash] = saving;
    try {
      return await saving;
    } finally {
      if (identical(_inFlight[hash], saving)) _inFlight.remove(hash);
    }
  }

  static Future<T> _serially<T>(Future<T> Function() operation) {
    final next = _queue.then((_) => operation());
    _queue = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  Future<SystemAlbumSave> _save(
    String hash,
    Uint8List bytes,
    String fileName,
    String source,
    bool allowDuplicate,
  ) async {
    final entries = _readRegistry();
    final known = entries[hash];
    if (!allowDuplicate && known != null && await target.contains(known)) {
      AppLogger.i('[AlbumSave] $source found $known already', 'SystemAlbum');
      return (location: known, duplicate: true);
    }
    final location = await target.write(bytes, fileName);
    entries
      ..remove(hash)
      ..[hash] = location;
    while (entries.length > maxRemembered) {
      entries.remove(entries.keys.first);
    }
    await _storage.setSetting(_registryKey, jsonEncode(entries));
    AppLogger.i('[AlbumSave] $source wrote $location', 'SystemAlbum');
    return (location: location, duplicate: false);
  }

  /// Insertion-ordered, oldest first.
  Map<String, String> _readRegistry() {
    final raw = _storage.getSetting<String>(_registryKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return {
        for (final entry in decoded.entries)
          if (entry.key is String && entry.value is String)
            entry.key as String: entry.value as String,
      };
    } on FormatException {
      return {};
    }
  }
}

/// Android's shared Pictures collection, under "Aaalice NAI Launcher".
class AndroidPhotoAlbumTarget implements SystemAlbumTarget {
  const AndroidPhotoAlbumTarget();

  @override
  bool get isPhotoAlbum => true;

  @override
  Future<String> write(Uint8List bytes, String fileName) async {
    final uri = await AndroidMediaStoreService.savePng(
      bytes: bytes,
      fileName: fileName,
    );
    if (uri == null || uri.isEmpty) {
      throw StateError('The photo album did not accept the image.');
    }
    return uri;
  }

  @override
  Future<bool> contains(String location) =>
      AndroidMediaStoreService.imageExists(location);
}

/// A folder on disk standing in for the photo album.
class FolderAlbumTarget implements SystemAlbumTarget {
  FolderAlbumTarget(this._folder);

  final Future<Directory> Function() _folder;

  @override
  bool get isPhotoAlbum => false;

  @override
  Future<String> write(Uint8List bytes, String fileName) async {
    final folder = await _folder();
    await folder.create(recursive: true);
    final stem = p.basenameWithoutExtension(fileName);
    final extension = p.extension(fileName);
    var candidate = p.join(folder.path, fileName);
    for (var suffix = 2; ; suffix++) {
      try {
        final file = await File(candidate).create(exclusive: true);
        await file.writeAsBytes(bytes, flush: true);
        return candidate;
      } on FileSystemException {
        if (!await File(candidate).exists()) rethrow;
        candidate = p.join(folder.path, '$stem-$suffix$extension');
      }
    }
  }

  @override
  Future<bool> contains(String location) => File(location).exists();
}
