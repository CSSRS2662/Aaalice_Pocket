import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/presentation/screens/splash/splash_intro_animation.dart';
import 'package:nai_launcher/presentation/screens/splash/splash_screen.dart';

void main() {
  group('SplashIntroAnimation', () {
    testWidgets('plays every frame once, keeps the last one and settles', (
      tester,
    ) async {
      final codec = await _FakeCodec.create(tester, frameCount: 3);
      var settled = 0;

      await tester.pumpWidget(
        _host(
          SplashIntroAnimation(
            codecLoader: (_) async => codec,
            onSettled: () => settled++,
          ),
        ),
      );
      await tester.pump();
      expect(codec.requested, 1);
      expect(_shownImage(tester), isNotNull);
      expect(settled, 0);

      await tester.pump(_FakeCodec.frameDuration);
      expect(codec.requested, 2);
      expect(settled, 0);

      await tester.pump(_FakeCodec.frameDuration);
      expect(codec.requested, 3);
      expect(settled, 1);
      expect(codec.disposed, isTrue);

      await tester.pump(const Duration(seconds: 5));
      expect(codec.requested, 3, reason: 'the animation must not restart');
      expect(settled, 1);
      expect(_shownImage(tester), isNotNull, reason: 'last frame stays');
    });

    testWidgets('reduced motion shows the first frame and settles at once', (
      tester,
    ) async {
      final codec = await _FakeCodec.create(tester, frameCount: 3);
      var settled = 0;

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: _host(
            SplashIntroAnimation(
              codecLoader: (_) async => codec,
              onSettled: () => settled++,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(codec.requested, 1);
      expect(settled, 1);
      expect(_shownImage(tester), isNotNull);
      await tester.pump(const Duration(seconds: 2));
      expect(codec.requested, 1);
    });

    testWidgets('a stuck loader still settles after the timeout', (
      tester,
    ) async {
      final never = Completer<ui.Codec>();
      var settled = 0;

      await tester.pumpWidget(
        _host(
          SplashIntroAnimation(
            codecLoader: (_) => never.future,
            onSettled: () => settled++,
          ),
        ),
      );
      await tester.pump(
        SplashIntroAnimation.settleTimeout - const Duration(milliseconds: 1),
      );
      expect(settled, 0);

      await tester.pump(const Duration(milliseconds: 2));
      expect(settled, 1);
    });

    testWidgets('a load error settles at once', (tester) async {
      var settled = 0;

      await tester.pumpWidget(
        _host(
          SplashIntroAnimation(
            codecLoader: (_) async => throw StateError('missing asset'),
            onSettled: () => settled++,
          ),
        ),
      );
      await tester.pump();

      expect(settled, 1);
      expect(_shownImage(tester), isNull);
    });
  });

  group('splash assets', () {
    test('intro GIF plays once and has the expected frame size', () {
      final bytes = File(SplashIntroAnimation.asset).readAsBytesSync();
      final header = ByteData.sublistView(bytes, 0, 10);

      expect(String.fromCharCodes(bytes.sublist(0, 6)), 'GIF89a');
      expect(header.getUint16(6, Endian.little), 360);
      expect(header.getUint16(8, Endian.little), 480);
      expect(
        SplashIntroAnimation.frameSize,
        const Size(360, 480),
        reason: 'layout constants must follow the asset',
      );
      // Without the NETSCAPE2.0 loop block a GIF plays a single time.
      expect(
        String.fromCharCodes(bytes).contains('NETSCAPE2.0'),
        isFalse,
        reason: 'the intro must not loop',
      );
    });

    test('Android launch window and icon use the splash background', () {
      final colors = File(
        'android/app/src/main/res/values/colors.xml',
      ).readAsStringSync();
      final hex = SplashScreen.backgroundColor
          .toARGB32()
          .toRadixString(16)
          .substring(2)
          .toUpperCase();

      for (final name in [
        'launch_background_color',
        'ic_launcher_background',
      ]) {
        expect(
          colors,
          contains('<color name="$name">#$hex</color>'),
          reason: '$name must match the Flutter splash background',
        );
      }
    });
  });
}

Widget _host(Widget child) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Center(child: SizedBox(width: 360, height: 480, child: child)),
  );
}

ui.Image? _shownImage(WidgetTester tester) {
  return tester
      .widget<RawImage>(find.byKey(const ValueKey('splash-intro-frame')))
      .image;
}

class _FakeCodec implements ui.Codec {
  _FakeCodec(this._image, this.frameCount);

  static const frameDuration = Duration(milliseconds: 100);

  static Future<_FakeCodec> create(
    WidgetTester tester, {
    required int frameCount,
  }) async {
    final image = await tester.runAsync(
      () => createTestImage(width: 4, height: 4, cache: false),
    );
    addTearDown(image!.dispose);
    return _FakeCodec(image, frameCount);
  }

  final ui.Image _image;
  int requested = 0;
  bool disposed = false;

  @override
  final int frameCount;

  @override
  int get repetitionCount => 0;

  @override
  Future<ui.FrameInfo> getNextFrame() async {
    requested++;
    return _FakeFrameInfo(frameDuration, _image.clone());
  }

  @override
  void dispose() {
    disposed = true;
  }
}

class _FakeFrameInfo implements ui.FrameInfo {
  _FakeFrameInfo(this.duration, this.image);

  @override
  final Duration duration;

  @override
  final ui.Image image;
}
