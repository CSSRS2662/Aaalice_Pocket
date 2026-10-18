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

  /// Where the album's own folder already holds an image with exactly these
  /// [bytes] (whose SHA-256 is [sha256]); null when it holds none.
  Future<String?> find({required Uint8List bytes, required String sha256});
}

/// Saving puts images here: the photo album on Android, an
/// "Aaalice NAI Launcher" folder in Downloads elsewhere. The in-app gallery
/// holds favorites only.
///
/// Saving the same image again is reported as a duplicate while the album's
/// folder still holds it, and writes it again once the user removed it there.
/// Each save is remembered by the content hash of its identity bytes; an
/// image the record does not know is looked up in the folder by content, so
/// copies saved earlier, for example by older versions, count too. Only the
/// album's own folder is searched. The record stays on this device.
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
    final calculator = FileHashCalculator();
    final hash = await calculator.calculateFromBytesAsync(identity ?? bytes);
    final contentHash = identity == null
        ? hash
        : await calculator.calculateFromBytesAsync(bytes);
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
      () => _save(
        hash: hash,
        contentHash: contentHash,
        bytes: bytes,
        identity: identity,
        fileName: fileName,
        source: source,
        allowDuplicate: allowDuplicate,
      ),
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

  Future<SystemAlbumSave> _save({
    required String hash,
    required String contentHash,
    required Uint8List bytes,
    required Uint8List? identity,
    required String fileName,
    required String source,
    required bool allowDuplicate,
  }) async {
    final entries = _readRegistry();
    if (!allowDuplicate) {
      final existing = await _findExisting(
        known: entries[hash],
        bytes: bytes,
        contentHash: contentHash,
        identity: identity,
        identityHash: hash,
      );
      if (existing != null) {
        if (entries[hash] != existing) await _remember(entries, hash, existing);
        AppLogger.i(
          '[AlbumSave] $source found $existing already',
          'SystemAlbum',
        );
        return (location: existing, duplicate: true);
      }
    }
    final location = await target.write(bytes, fileName);
    await _remember(entries, hash, location);
    AppLogger.i('[AlbumSave] $source wrote $location', 'SystemAlbum');
    return (location: location, duplicate: false);
  }

  /// Where the album already has the image: the location an earlier save
  /// recorded, or else a file in the album's folder with the same content.
  Future<String?> _findExisting({
    required String? known,
    required Uint8List bytes,
    required String contentHash,
    required Uint8List? identity,
    required String identityHash,
  }) async {
    try {
      if (known != null && await target.contains(known)) return known;
      final found = await target.find(bytes: bytes, sha256: contentHash);
      if (found != null || identity == null || identityHash == contentHash) {
        return found;
      }
      return await target.find(bytes: identity, sha256: identityHash);
    } on Object catch (error) {
      // A failed lookup must not stop the save itself.
      AppLogger.w('[AlbumSave] duplicate lookup failed: $error', 'SystemAlbum');
      return null;
    }
  }

  Future<void> _remember(
    Map<String, String> entries,
    String hash,
    String location,
  ) async {
    entries
      ..remove(hash)
      ..[hash] = location;
    while (entries.length > maxRemembered) {
      entries.remove(entries.keys.first);
    }
    await _storage.setSetting(_registryKey, jsonEncode(entries));
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

  /// Without a storage permission, MediaStore only lists the images this
  /// installation put there.
  @override
  Future<String?> find({required Uint8List bytes, required String sha256}) =>
      AndroidMediaStoreService.findImage(sha256: sha256, size: bytes.length);
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

  @override
  Future<String?> find({
    required Uint8List bytes,
    required String sha256,
  }) async {
    final folder = await _folder();
    if (!await folder.exists()) return null;
    final calculator = FileHashCalculator();
    await for (final entity in folder.list(followLinks: false)) {
      if (entity is! File || await entity.length() != bytes.length) continue;
      final content = await entity.readAsBytes();
      if (await calculator.calculateFromBytesAsync(content) == sha256) {
        return entity.path;
      }
    }
    return null;
  }
}
