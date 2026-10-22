import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../../core/utils/app_logger.dart';

/// Loads the codec for the intro frames.
typedef SplashIntroCodecLoader = Future<ui.Codec> Function(AssetBundle bundle);

/// Plays the pocket intro animation once and keeps its last frame.
///
/// Frame 0 is the launcher icon artwork. The Android system splash stays up
/// until that frame can replace it, so the hand-over does not flash.
/// [onSettled] fires once the last frame is on screen, right away when motion
/// is reduced, on a load error, or after [settleTimeout] at the latest.
class SplashIntroAnimation extends StatefulWidget {
  const SplashIntroAnimation({super.key, this.onSettled, this.codecLoader});

  static const String asset = 'assets/splash/pocket_intro.gif';

  /// Pixel size of the frames.
  static const Size frameSize = Size(360, 480);

  /// Centre of the icon artwork in frame 0, in frame pixels.
  static const Offset artCenter = Offset(183, 256.5);

  /// Logical pixels per frame pixel at which frame 0 matches the Android 12+
  /// system splash icon (the adaptive icon drawn at 240 dp).
  static const double systemSplashScale = 0.6856;

  /// Upper bound for holding the app on the splash for the animation.
  static const Duration settleTimeout = Duration(seconds: 3);

  final VoidCallback? onSettled;

  @visibleForTesting
  final SplashIntroCodecLoader? codecLoader;

  @override
  State<SplashIntroAnimation> createState() => _SplashIntroAnimationState();
}

class _SplashIntroAnimationState extends State<SplashIntroAnimation> {
  static const _firstFrameHoldLimit = Duration(milliseconds: 400);

  ui.Codec? _codec;
  ui.Image? _frame;
  int _shownFrames = 0;
  Timer? _nextFrameTimer;
  Timer? _settleTimer;
  Timer? _firstFrameHoldTimer;
  bool _holdingFirstFrame = false;
  bool _started = false;
  bool _settled = false;

  @override
  void initState() {
    super.initState();
    final binding = WidgetsBinding.instance;
    if (!binding.firstFrameRasterized) {
      binding.deferFirstFrame();
      _holdingFirstFrame = true;
      _firstFrameHoldTimer = Timer(_firstFrameHoldLimit, _releaseFirstFrame);
    }
    _settleTimer = Timer(SplashIntroAnimation.settleTimeout, _settle);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    unawaited(
      _load(
        DefaultAssetBundle.of(context),
        playing: !MediaQuery.disableAnimationsOf(context),
      ),
    );
  }

  Future<void> _load(AssetBundle bundle, {required bool playing}) async {
    try {
      final codec = await (widget.codecLoader ?? _loadAssetCodec)(bundle);
      if (!mounted) {
        codec.dispose();
        return;
      }
      _codec = codec;
      await _showNextFrame(playing: playing);
    } catch (error, stackTrace) {
      AppLogger.e('Splash intro failed to load', error, stackTrace, 'Splash');
      _finishPlayback();
    }
  }

  static Future<ui.Codec> _loadAssetCodec(AssetBundle bundle) async {
    final data = await bundle.load(SplashIntroAnimation.asset);
    return ui.instantiateImageCodec(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  }

  Future<void> _showNextFrame({required bool playing}) async {
    final codec = _codec;
    if (codec == null) return;
    final decodeTime = Stopwatch()..start();
    final ui.FrameInfo info;
    try {
      info = await codec.getNextFrame();
    } catch (error, stackTrace) {
      AppLogger.e('Splash intro frame failed', error, stackTrace, 'Splash');
      _finishPlayback();
      return;
    }
    if (!mounted) {
      info.image.dispose();
      return;
    }
    final previous = _frame;
    setState(() => _frame = info.image);
    previous?.dispose();
    _shownFrames++;
    _releaseFirstFrame();

    if (!playing || _shownFrames >= codec.frameCount) {
      _finishPlayback();
      return;
    }
    // Decoding the next frame takes time too; keep the frame rate.
    final wait = info.duration - decodeTime.elapsed;
    _nextFrameTimer = Timer(
      wait.isNegative ? Duration.zero : wait,
      () => unawaited(_showNextFrame(playing: true)),
    );
  }

  void _finishPlayback() {
    _codec?.dispose();
    _codec = null;
    _releaseFirstFrame();
    _settle();
  }

  void _settle() {
    if (_settled || !mounted) return;
    _settled = true;
    _settleTimer?.cancel();
    widget.onSettled?.call();
  }

  void _releaseFirstFrame() {
    if (!_holdingFirstFrame) return;
    _holdingFirstFrame = false;
    _firstFrameHoldTimer?.cancel();
    WidgetsBinding.instance.allowFirstFrame();
  }

  @override
  void dispose() {
    _nextFrameTimer?.cancel();
    _settleTimer?.cancel();
    _releaseFirstFrame();
    _codec?.dispose();
    _codec = null;
    _frame?.dispose();
    _frame = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: 'Aaalice Pocket',
      child: RawImage(
        key: const ValueKey('splash-intro-frame'),
        image: _frame,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}
