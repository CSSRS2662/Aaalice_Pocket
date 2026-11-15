import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/constants/app_version.dart';
import 'package:nai_launcher/core/services/pocket_update_service.dart';
import 'package:nai_launcher/core/services/verified_resumable_downloader.dart';
import 'package:package_info_plus/package_info_plus.dart';

const _assetUrl =
    'https://github.com/CSSRS2662/Aaalice_Pocket/releases/download/'
    'pocket-v1.10.0/Aaalice_Pocket_1.10.0_arm64.apk';
const _apk = [1, 2, 3, 4];
const _channel = MethodChannel('com.aaalice.nai_launcher/app_installer');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Dio dio;
  late PocketUpdateService service;
  late Map<String, dynamic> metadata;
  late Map<String, dynamic> asset;
  late List<MethodCall> installerCalls;
  late int requests;

  setUp(() async {
    final cache = await Directory.systemTemp.createTemp('pocket_update_test_');
    addTearDown(() => cache.delete(recursive: true));
    installerCalls = [];
    requests = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      installerCalls.add(call);
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));
    asset = {
      'name': 'Aaalice_Pocket_1.10.0_arm64.apk',
      'state': 'uploaded',
      'size': _apk.length,
      'digest': 'sha256:${sha256.convert(_apk)}',
      'browser_download_url': _assetUrl,
    };
    metadata = {
      'tag_name': 'pocket-v1.10.0',
      'draft': false,
      'prerelease': false,
      'body': 'Release notes',
      'assets': [asset],
    };
    dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests++;
            final uri = options.uri.toString();
            if (uri == _assetUrl) {
              handler.resolve(
                Response<ResponseBody>(
                  requestOptions: options,
                  statusCode: 200,
                  data: ResponseBody.fromBytes(_apk, 200),
                ),
              );
            } else {
              expect(
                uri,
                'https://api.github.com/repos/CSSRS2662/Aaalice_Pocket/releases/latest',
              );
              handler.resolve(
                Response(requestOptions: options, data: metadata),
              );
            }
          },
        ),
      );
    addTearDown(() => dio.close(force: true));
    service = PocketUpdateService(dio: dio, cacheDirectory: () async => cache);
  });

  test(
    'compares versions numerically and accepts only newer stable releases',
    () async {
      final release = await service.check(installedVersion: '1.9.99+124');
      expect(release?.version, '1.10.0');
      expect(release?.notes, 'Release notes');
      expect(await service.check(installedVersion: '1.10.0+125'), isNull);
      metadata['prerelease'] = true;
      expect(await service.check(installedVersion: '1.9.99'), isNull);
    },
  );

  test('dev builds report up to date without contacting GitHub', () async {
    for (final version in ['1.0.0-dev.1+126', '1.10.0-dev.2', '1.11.0-dev.1']) {
      expect(await service.check(installedVersion: version), isNull);
    }
    expect(requests, 0);
  });

  test('default check reads the installed Android version', () async {
    for (final (version, expected) in [
      ('1.1.0', '1.10.0'),
      ('1.1.0-dev.1', null),
    ]) {
      PackageInfo.setMockInitialValues(
        appName: 'Aaalice Pocket',
        packageName: 'com.cssrs2662.aaalicepocket',
        version: version,
        buildNumber: '132',
        buildSignature: '',
      );
      await AppVersion.initialize();
      expect((await service.check())?.version, expected);
    }
    expect(requests, 1);
  });

  test(
    'rejects a newer release with an unexpected URL or missing digest',
    () async {
      asset['browser_download_url'] = 'https://example.org/Pocket.apk';
      await expectLater(
        service.check(installedVersion: '1.0.0'),
        throwsFormatException,
      );
      asset['browser_download_url'] = _assetUrl;
      asset.remove('digest');
      await expectLater(
        service.check(installedVersion: '1.0.0'),
        throwsFormatException,
      );
    },
  );

  test('passes only the verified APK to the Android installer', () async {
    asset['digest'] = 'sha256:${'0' * 64}';
    final invalid = (await service.check(installedVersion: '1.0.0'))!;
    await expectLater(
      service.install(invalid, cancelToken: CancelToken()),
      throwsA(
        isA<VerifiedDownloadException>().having(
          (error) => error.failure,
          'failure',
          VerifiedDownloadFailure.checksumMismatch,
        ),
      ),
    );
    expect(installerCalls, isEmpty);

    asset['digest'] = 'sha256:${sha256.convert(_apk)}';
    final valid = (await service.check(installedVersion: '1.0.0'))!;
    await service.install(valid, cancelToken: CancelToken());
    final install = installerCalls.single;
    expect(install.method, 'installApk');
    expect(install.arguments['version'], valid.version);
    expect(await File(install.arguments['path'] as String).readAsBytes(), _apk);
  });
}
