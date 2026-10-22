import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/localization_extension.dart';
import '../../providers/warmup_provider.dart';
import '../../utils/warmup_message_localizer.dart';
import 'splash_intro_animation.dart';

/// 启动画面
/// 播放一次进入动画，加载期间只显示一个转圈。
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key, this.onIntroSettled});

  /// Same cream as the intro animation and the Android launch window.
  static const Color backgroundColor = Color(0xFFFFF9ED);

  /// Pocket teal from the artwork.
  static const Color accentColor = Color(0xFF31757E);

  /// Called once the intro animation has reached its last frame.
  final VoidCallback? onIntroSettled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final warmupState = ref.watch(warmupNotifierProvider);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarContrastEnforced: false,
      ),
      child: Scaffold(
        backgroundColor: backgroundColor,
        body: LayoutBuilder(
          builder: (context, constraints) => _SplashBody(
            constraints: constraints,
            warmupState: warmupState,
            onIntroSettled: onIntroSettled,
          ),
        ),
      ),
    );
  }
}

class _SplashBody extends StatelessWidget {
  const _SplashBody({
    required this.constraints,
    required this.warmupState,
    required this.onIntroSettled,
  });

  static const double _statusGap = 12;
  static const double _statusExtent = 48;

  final BoxConstraints constraints;
  final WarmupState warmupState;
  final VoidCallback? onIntroSettled;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final horizontal = math.max(padding.left, padding.right) + 16;
    final scale = _introScale(padding, horizontal);
    final introSize = SplashIntroAnimation.frameSize * scale;
    final artCenter = SplashIntroAnimation.artCenter * scale;
    // Put the artwork where the system splash drew the icon: screen centre.
    final top = math.max(padding.top, constraints.maxHeight / 2 - artCenter.dy);

    return SingleChildScrollView(
      key: const ValueKey('splash_scroll_view'),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: constraints.maxWidth,
          minHeight: constraints.maxHeight,
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            horizontal,
            top,
            horizontal,
            padding.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Transform.translate(
                offset: Offset(introSize.width / 2 - artCenter.dx, 0),
                child: SizedBox.fromSize(
                  key: const ValueKey('splash-intro'),
                  size: introSize,
                  child: SplashIntroAnimation(onSettled: onIntroSettled),
                ),
              ),
              const SizedBox(height: _statusGap),
              _SplashStatus(warmupState: warmupState),
            ],
          ),
        ),
      ),
    );
  }

  /// Matches the system splash icon size, shrinking only when space is short.
  double _introScale(EdgeInsets padding, double horizontal) {
    const frame = SplashIntroAnimation.frameSize;
    final byWidth = (constraints.maxWidth - horizontal * 2) / frame.width;
    final byHeight =
        (constraints.maxHeight -
            padding.vertical -
            _statusGap -
            _statusExtent) /
        frame.height;
    final fitted = math.min(
      SplashIntroAnimation.systemSplashScale,
      math.min(byWidth, byHeight),
    );
    return math.max(0.2, fitted);
  }
}

class _SplashStatus extends StatelessWidget {
  const _SplashStatus({required this.warmupState});

  final WarmupState warmupState;

  @override
  Widget build(BuildContext context) {
    final error = warmupState.error;
    if (error != null) {
      return _SplashError(error: error);
    }
    return AnimatedOpacity(
      opacity: warmupState.isComplete ? 0 : 1,
      duration: const Duration(milliseconds: 200),
      child: const SizedBox.square(
        dimension: 22,
        child: CircularProgressIndicator(
          key: ValueKey('splash-spinner'),
          strokeWidth: 2.4,
          color: SplashScreen.accentColor,
        ),
      ),
    );
  }
}

class _SplashError extends ConsumerWidget {
  const _SplashError({required this.error});

  final String error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: theme.colorScheme.error, size: 28),
          const SizedBox(height: 12),
          Text(
            WarmupMessageLocalizer.localizeError(l10n, error),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const ValueKey('warmup_retry'),
            onPressed: () {
              ref.read(warmupNotifierProvider.notifier).retry();
            },
            icon: const Icon(Icons.refresh),
            label: Text(l10n.common_retry),
          ),
        ],
      ),
    );
  }
}
