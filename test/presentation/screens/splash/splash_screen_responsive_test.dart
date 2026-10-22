import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/providers/warmup_provider.dart';
import 'package:nai_launcher/presentation/screens/splash/splash_intro_animation.dart';
import 'package:nai_launcher/presentation/screens/splash/splash_screen.dart';

import '../../../helpers/flutter_error_collector.dart';

class _IdleWarmupNotifier extends WarmupNotifier {
  @override
  WarmupState build() => WarmupState.initial();
}

class _FailedWarmupNotifier extends WarmupNotifier {
  @override
  WarmupState build() =>
      WarmupState.initial().copyWith(error: 'database failed');
}

/// Keeps the intro asset loading so tests never touch the image decoder.
class _PendingAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) => Completer<ByteData>().future;
}

const _safePadding = EdgeInsets.only(top: 24, bottom: 16);

Widget _splashApp({
  required WarmupNotifier Function() notifier,
  double textScale = 1,
  EdgeInsets padding = _safePadding,
  double keyboardInset = 0,
}) {
  return ProviderScope(
    overrides: [warmupNotifierProvider.overrideWith(notifier)],
    child: DefaultAssetBundle(
      bundle: _PendingAssetBundle(),
      child: MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            padding: padding,
            viewPadding: padding,
            viewInsets: EdgeInsets.only(bottom: keyboardInset),
          ),
          child: child!,
        ),
        home: const SplashScreen(),
      ),
    ),
  );
}

Future<void> _setSize(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void main() {
  testWidgets('Splash shows only the intro and a spinner while loading', (
    tester,
  ) async {
    await _setSize(tester, const Size(412, 915));
    await tester.pumpWidget(_splashApp(notifier: _IdleWarmupNotifier.new));
    await tester.pump();

    expect(find.byType(SplashIntroAnimation), findsOneWidget);
    expect(find.byKey(const ValueKey('splash-spinner')), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byType(Text), findsNothing);
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      SplashScreen.backgroundColor,
    );
  });

  testWidgets('Intro artwork sits where the system splash draws the icon', (
    tester,
  ) async {
    const size = Size(412, 915);
    await _setSize(tester, size);
    await tester.pumpWidget(
      _splashApp(
        notifier: _IdleWarmupNotifier.new,
        padding: const EdgeInsets.only(top: 32, bottom: 24),
      ),
    );
    await tester.pump();

    final rect = tester.getRect(find.byKey(const ValueKey('splash-intro')));
    final scale = rect.width / SplashIntroAnimation.frameSize.width;
    final art = rect.topLeft + SplashIntroAnimation.artCenter * scale;
    expect(scale, closeTo(SplashIntroAnimation.systemSplashScale, 1e-9));
    expect(art.dx, closeTo(size.width / 2, 0.01));
    expect(art.dy, closeTo(size.height / 2, 0.01));
  });

  testWidgets(
    'Splash keeps the spinner reachable at 320 width with 3x text, IME, and SafeArea',
    (tester) async {
      final flutterErrors = FlutterErrorCollector.install(tester);
      addTearDown(flutterErrors.restoreAndAssertNoErrors);
      const size = Size(320, 760);
      const keyboardInset = 300.0;
      await _setSize(tester, size);

      await tester.pumpWidget(
        _splashApp(
          notifier: _IdleWarmupNotifier.new,
          textScale: 3,
          keyboardInset: keyboardInset,
        ),
      );
      await tester.pump();
      flutterErrors.expectNoErrors(reason: 'initial splash layout');

      final usableRect = Rect.fromLTRB(
        0,
        _safePadding.top,
        size.width,
        size.height - keyboardInset,
      );
      final spinner = find.byKey(const ValueKey('splash-spinner'));
      await tester.ensureVisible(spinner);
      await tester.pump();
      expect(usableRect.contains(tester.getRect(spinner).center), isTrue);
      expect(
        tester.getRect(find.byKey(const ValueKey('splash-intro'))).width,
        greaterThan(0),
      );
    },
  );

  testWidgets('Startup errors keep the message and retry reachable', (
    tester,
  ) async {
    final flutterErrors = FlutterErrorCollector.install(tester);
    addTearDown(flutterErrors.restoreAndAssertNoErrors);
    const size = Size(320, 760);
    const keyboardInset = 300.0;
    await _setSize(tester, size);

    await tester.pumpWidget(
      _splashApp(
        notifier: _FailedWarmupNotifier.new,
        textScale: 3,
        keyboardInset: keyboardInset,
      ),
    );
    await tester.pump();
    flutterErrors.expectNoErrors(reason: 'error splash layout');

    expect(find.byKey(const ValueKey('splash-spinner')), findsNothing);
    final usableRect = Rect.fromLTRB(
      0,
      _safePadding.top,
      size.width,
      size.height - keyboardInset,
    );
    for (final target in [
      find.byIcon(Icons.error_outline),
      find.byKey(const ValueKey('warmup_retry')),
    ]) {
      await tester.ensureVisible(target);
      await tester.pump();
      expect(
        tester.getRect(target).intersect(usableRect).height,
        greaterThan(0),
        reason: '$target should be reachable above the IME',
      );
    }
  });

  testWidgets('Splash fits common widths and a short landscape screen', (
    tester,
  ) async {
    final flutterErrors = FlutterErrorCollector.install(tester);
    addTearDown(flutterErrors.restoreAndAssertNoErrors);

    for (final size in const [
      Size(320, 640),
      Size(600, 960),
      Size(840, 700),
      Size(1180, 820),
      Size(1600, 1000),
      Size(740, 360),
    ]) {
      await _setSize(tester, size);
      await tester.pumpWidget(_splashApp(notifier: _IdleWarmupNotifier.new));
      await tester.pump();
      flutterErrors.expectNoErrors(reason: 'splash at $size');

      final screen = Offset.zero & size;
      final spinner = tester.getRect(
        find.byKey(const ValueKey('splash-spinner')),
      );
      final intro = tester.getRect(find.byKey(const ValueKey('splash-intro')));
      expect(screen.contains(spinner.bottomRight), isTrue, reason: '$size');
      expect(
        intro.top,
        greaterThanOrEqualTo(_safePadding.top),
        reason: '$size',
      );
      expect(intro.bottom, lessThanOrEqualTo(spinner.top), reason: '$size');
    }
  });
}
