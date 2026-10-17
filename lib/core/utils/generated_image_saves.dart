import 'dart:async';
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
/// A copy the gallery already holds under the same content hash counts as
/// written, including one saved before this run when the save names its
/// seed. Each save is logged with its source, so a diagnostic log shows
/// which entry wrote a file.
abstract final class GeneratedImageSaves {
  static final Map<String, Future<String>> _saves = {};

  /// Returns the existing file for [sourceBytes] under [rootPath], or the
  /// path [write] saves them to. [seed] lets earlier dated saves be found;
  /// [allowDuplicate] always writes a new copy.
  static Future<({String path, bool reused})> saveOnce({
    required String rootPath,
    required Uint8List sourceBytes,
    required String source,
    required Future<String> Function() write,
    int? seed,
    bool allowDuplicate = false,
  }) async {
    final hash = await FileHashCalculator().calculateFromBytesAsync(
      sourceBytes,
    );
    final key = '$rootPath\n$hash';
    if (!allowDuplicate) {
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
    }
    // Claimed with no await since the check above, so a save that starts
    // during the folder check or the write waits for this one.
    final claim = Completer<String>();
    final claimed = claim.future..ignore();
    _saves[key] = claimed;
    try {
      if (!allowDuplicate) {
        if (seed != null && seed >= 0) {
          await _hashSeedNamedFiles(rootPath, seed);
        }
        final known = _knownCopy(hash, rootPath);
        if (known != null) {
          claim.complete(known);
          return _reused(known, source);
        }
      }
      final path = await write();
      claim.complete(path);
      AppLogger.i(
        '[GeneratedSave] $source wrote $path'
            '${allowDuplicate ? ' (duplicate allowed)' : ''}',
        'ImageSaveUtils',
      );
      return (path: path, reused: false);
    } on Object catch (error, stack) {
      if (!claim.isCompleted) claim.completeError(error, stack);
      if (identical(_saves[key], claimed)) _saves.remove(key);
      rethrow;
    }
  }

  /// Dated saves name a result `HH-MM-SS-<seed>.png`, adding `-2` and on for
  /// name conflicts, so only files with the same seed can hold the same
  /// image. Hashing them lets [_knownCopy] find copies saved before this run.
  static Future<void> _hashSeedNamedFiles(String rootPath, int seed) async {
    final name = RegExp(
      '^\\d{2}-\\d{2}-\\d{2}-$seed(?:-\\d+)?\\.png\$',
      caseSensitive: false,
    );
    try {
      final root = Directory(rootPath);
      if (!await root.exists()) return;
      final hashing = <Future<String>>[];
      await for (final entity in root.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File && name.hasMatch(p.basename(entity.path))) {
          hashing.add(FileHashCalculator().calculate(entity.path));
        }
      }
      await Future.wait(hashing);
    } on Object catch (error) {
      AppLogger.w(
        '[GeneratedSave] could not check $rootPath for copies: $error',
        'ImageSaveUtils',
      );
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
