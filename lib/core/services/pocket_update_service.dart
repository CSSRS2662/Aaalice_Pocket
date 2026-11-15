import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../constants/app_version.dart';
import 'verified_resumable_downloader.dart';

final pocketUpdateServiceProvider = Provider<PocketUpdateService>((ref) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );
  ref.onDispose(() => dio.close(force: true));
  return PocketUpdateService(dio: dio);
});

class PocketRelease {
  const PocketRelease({
    required this.version,
    required this.notes,
    required this.apkUrl,
    required this.apkSize,
    required this.sha256,
  });

  final String version;
  final String notes;
  final Uri apkUrl;
  final int apkSize;
  final String sha256;
}

class PocketUpdateService {
  PocketUpdateService({
    required Dio dio,
    Future<Directory> Function() cacheDirectory = getTemporaryDirectory,
  }) : _dio = dio,
       _cacheDirectory = cacheDirectory,
       _downloader = VerifiedResumableDownloader(dio: dio);

  static const _repository = 'CSSRS2662/Aaalice_Pocket';
  static final projectUrl = Uri.https('github.com', _repository);
  static final _latest = Uri.https(
    'api.github.com',
    'repos/$_repository/releases/latest',
  );
  static const _installer = MethodChannel(
    'com.aaalice.nai_launcher/app_installer',
  );
  static final _releaseTag = RegExp(r'^pocket-v(\d+\.\d+\.\d+)$');
  static final _version = RegExp(r'^(\d+)\.(\d+)\.(\d+)(-[^+]+)?(?:\+.+)?$');
  static final _digest = RegExp(r'^sha256:([a-fA-F0-9]{64})$');

  final Dio _dio;
  final Future<Directory> Function() _cacheDirectory;
  final VerifiedResumableDownloader _downloader;
  bool _installing = false;

  Future<PocketRelease?> check({String? installedVersion}) async {
    final current = _version.firstMatch(
      installedVersion ?? AppVersion.fullVersion,
    );
    if (current == null) {
      throw const FormatException('Invalid installed version');
    }
    final prerelease = current.group(4)?.toLowerCase();
    if (prerelease == '-dev' || prerelease?.startsWith('-dev.') == true) {
      return null;
    }
    final response = await _dio.getUri<Map<String, dynamic>>(
      _latest,
      options: Options(headers: {'Accept': 'application/vnd.github+json'}),
    );
    final data = response.data;
    if (data == null) throw const FormatException('Missing release metadata');
    final tag = data['tag_name'];
    final version = tag is String
        ? _releaseTag.firstMatch(tag)?.group(1)
        : null;
    if (data['draft'] == true ||
        data['prerelease'] == true ||
        version == null) {
      return null;
    }
    if (!_isNewer(version, current)) return null;

    final name = 'Aaalice_Pocket_${version}_arm64.apk';
    final uri = Uri.https(
      'github.com',
      '$_repository/releases/download/$tag/$name',
    );
    final assets = data['assets'];
    final asset = assets is List
        ? assets
              .whereType<Map<String, dynamic>>()
              .where(
                (asset) =>
                    asset['name'] == name && asset['state'] == 'uploaded',
              )
              .firstOrNull
        : null;
    final size = asset?['size'];
    final digest = asset?['digest'];
    final sha256 = digest is String
        ? _digest.firstMatch(digest)?.group(1)
        : null;
    if (size is! int ||
        size <= 0 ||
        sha256 == null ||
        asset?['browser_download_url'] != uri.toString()) {
      throw const FormatException('Missing verified Pocket arm64 APK');
    }
    final notes = data['body'];
    return PocketRelease(
      version: version,
      notes: notes is String ? notes.trim() : '',
      apkUrl: uri,
      apkSize: size,
      sha256: sha256,
    );
  }

  static bool _isNewer(String release, RegExpMatch installed) {
    final parts = release.split('.');
    for (var i = 0; i < parts.length; i++) {
      final order = int.parse(
        parts[i],
      ).compareTo(int.parse(installed.group(i + 1)!));
      if (order != 0) return order > 0;
    }
    return installed.group(4) != null;
  }

  Future<void> install(
    PocketRelease release, {
    required CancelToken cancelToken,
    void Function(VerifiedDownloadProgress progress)? onProgress,
  }) async {
    if (_installing) throw PlatformException(code: 'install_in_progress');
    _installing = true;
    try {
      final file = await _download(release, cancelToken, onProgress);
      if (cancelToken.isCancelled) return;
      await _installer.invokeMethod<bool>('installApk', {
        'path': file.path,
        'version': release.version,
      });
    } finally {
      _installing = false;
    }
  }

  Future<File> _download(
    PocketRelease release,
    CancelToken cancelToken,
    void Function(VerifiedDownloadProgress progress)? onProgress,
  ) async {
    final root = await _cacheDirectory();
    final directory = Directory(p.join(root.path, 'nai_launcher_updates'));
    final fileName = 'Aaalice_Pocket_${release.version}_arm64.apk';
    await directory.create(recursive: true);
    final oldPackage = RegExp(
      r'^Aaalice_Pocket_\d+\.\d+\.\d+_arm64\.apk(?:\.part)?$',
    );
    await for (final entry in directory.list(followLinks: false)) {
      final name = p.basename(entry.path);
      if (entry is File &&
          oldPackage.hasMatch(name) &&
          name != fileName &&
          name != '$fileName.part') {
        await entry.delete();
      }
    }
    final download = await _downloader.download(
      uri: release.apkUrl,
      targetFile: File(p.join(directory.path, fileName)),
      expectedSize: release.apkSize,
      expectedSha256: release.sha256,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
    return download.file;
  }
}
