import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../data/services/metadata/hash_calculator.dart';
import 'app_logger.dart';

/// One gallery file per generated image.
///
/// Several entries save results: auto-save, a favorite or a locate that
/// needs a file, and the save buttons. When two of them save the same source
/// bytes into the same root, one after the other or at the same time, the
/// later one gets the file the first wrote instead of writing a second copy.
/// A copy the gallery already knows under the same content hash counts as
/// written. Each save is logged with its source, so a diagnostic log shows
/// which entry wrote a file.
abstract final class GeneratedImageSaves {
  static final Map<String, Future<String>> _saves = {};

  /// Returns the existing file for [sourceBytes] under [rootPath], or the
  /// path [write] saves them to.
  static Future<({String path, bool reused})> saveOnce({
    required String rootPath,
    required Uint8List sourceBytes,
    required String source,
    required Future<String> Function() write,
  }) async {
    final hash = await FileHashCalculator().calculateFromBytesAsync(
      sourceBytes,
    );
    final key = '$rootPath\n$hash';
    while (true) {
      final earlier = _saves[key];
      if (earlier == null) break;
      try {
        final path = await earlier;
        if (await File(path).exists()) return _reused(path, source);
      } on Object {
        // That save failed or its file is gone; this one writes the file.
      }
      if (identical(_saves[key], earlier)) {
        _saves.remove(key);
        break;
      }
    }
    // No await between this check and registering the write, so a save that
    // starts meanwhile waits for this one.
    final known = _knownCopy(hash, rootPath);
    if (known != null) {
      _saves[key] = Future.value(known);
      return _reused(known, source);
    }
    final writing = write();
    _saves[key] = writing;
    try {
      final path = await writing;
      AppLogger.i('[GeneratedSave] $source wrote $path', 'ImageSaveUtils');
      return (path: path, reused: false);
    } on Object {
      if (identical(_saves[key], writing)) _saves.remove(key);
      rethrow;
    }
  }

  static String? _knownCopy(String hash, String rootPath) {
    for (final path in FileHashCalculator().getPathsForHash(hash)) {
      if (p.isWithin(rootPath, path) && File(path).existsSync()) return path;
    }
    return null;
  }

  static ({String path, bool reused}) _reused(String path, String source) {
    AppLogger.i(
      '[GeneratedSave] $source reused $path for the same image',
      'ImageSaveUtils',
    );
    return (path: path, reused: true);
  }
}
