import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nai_launcher/core/constants/api_constants.dart';
import 'package:nai_launcher/data/models/image/image_params.dart';
import 'package:nai_launcher/data/models/user/user_subscription.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/providers/cost_estimate_provider.dart';
import 'package:nai_launcher/presentation/providers/image_generation_provider.dart';
import 'package:nai_launcher/presentation/providers/subscription_provider.dart';
import 'package:nai_launcher/presentation/screens/generation/mobile_generation_view_data.dart';
import 'package:nai_launcher/presentation/screens/generation/mobile_workbench/mobile_generate_bar.dart';
import 'package:nai_launcher/presentation/themes/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  final generate = find.byKey(const ValueKey('generation-mobile-generate'));
  final bar = find.byKey(const ValueKey('generation-mobile-bottom-bar'));

  testWidgets('底栏只有一行：智能体、队列在生成按钮左侧，额度不在底栏', (tester) async {
    for (final (width, scale) in [(390.0, 1.0), (320.0, 1.0), (320.0, 3.0)]) {
      await tester.binding.setSurfaceSize(Size(width, 800));
      await tester.pumpWidget(_subject(textScale: scale));
      await tester.pump();
      final reason = '$width@$scale';

      // Stamina and balance moved to the header.
      expect(find.byKey(const ValueKey('opus-stamina-bar')), findsNothing);
      expect(find.text('9,993'), findsNothing);

      final generateRect = tester.getRect(generate);
      var previousRight = 0.0;
      for (final key in [
        'generation-add-current-to-queue',
        'generation-agent-drawer-action',
        'generation-mobile-queue-action',
      ]) {
        final rect = tester.getRect(find.byKey(ValueKey(key)));
        expect(rect.left, greaterThanOrEqualTo(previousRight), reason: key);
        expect(rect.right, lessThanOrEqualTo(generateRect.left), reason: key);
        expect(rect.shortestSide, greaterThanOrEqualTo(44), reason: key);
        expect((rect.center.dy - generateRect.center.dy).abs(), lessThan(1));
        previousRight = rect.right;
      }
      expect(generateRect.right, lessThanOrEqualTo(width));
      expect(
        tester.getRect(bar).height - generateRect.height,
        lessThanOrEqualTo(18 + 0.1),
        reason: 'only padding around the one action row',
      );
      expect(tester.takeException(), isNull, reason: reason);
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('点击生成时底色和标签平滑切换，停止操作立即生效', (tester) async {
    final container = ProviderContainer(
      overrides: [
        imageGenerationNotifierProvider.overrideWith(
          () => _StateImageGenerationNotifier(const ImageGenerationState()),
        ),
      ],
    );
    addTearDown(container.dispose);
    var active = false;
    var cancelled = 0;
    final theme = AppTheme.getTheme(Brightness.light);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: theme,
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                child: StatefulBuilder(
                  builder: (context, setState) => MobileGenerateActionButton(
                    isGenerating: active,
                    showCancel: active,
                    isPreparing: false,
                    cooldownRemainingSeconds: 0,
                    showCost: false,
                    requiresLogin: false,
                    onGenerate: () {
                      (container.read(imageGenerationNotifierProvider.notifier)
                              as _StateImageGenerationNotifier)
                          .update(
                            const ImageGenerationState(
                              status: GenerationStatus.generating,
                              currentImage: 1,
                              totalImages: 2,
                              progress: 0.5,
                            ),
                          );
                      setState(() => active = true);
                    },
                    onCancel: () => cancelled++,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    Color background() =>
        (tester
                    .widgetList<DecoratedBox>(
                      find.descendant(
                        of: generate,
                        matching: find.byType(DecoratedBox),
                      ),
                    )
                    .first
                    .decoration
                as BoxDecoration)
            .color!;
    final initial = background();
    await tester.tap(generate);
    await tester.pump();
    expect(find.text('生成'), findsOneWidget);
    expect(find.text('1/2 50%'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 80));
    expect(background(), isNot(initial));
    expect(background(), isNot(theme.colorScheme.surfaceContainerHighest));
    await tester.tap(generate);
    expect(cancelled, 1);
    await tester.pumpAndSettle();
    expect(background(), theme.colorScheme.surfaceContainerHighest);
    expect(find.text('生成'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('生成按钮显示批次和进度，重试只在后台计数', (tester) async {
    Widget button(ImageGenerationState state) => ProviderScope(
      key: UniqueKey(),
      overrides: [
        imageGenerationNotifierProvider.overrideWith(
          () => _StateImageGenerationNotifier(state),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.getTheme(Brightness.light),
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 240,
              child: MobileGenerateActionButton(
                isGenerating: true,
                showCancel: true,
                isPreparing: false,
                cooldownRemainingSeconds: 0,
                showCost: true,
                requiresLogin: false,
                onGenerate: () {},
                onCancel: () {},
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(
      button(
        const ImageGenerationState(
          status: GenerationStatus.generating,
          progress: 0.4,
          retryAttempt: 3,
          maxRetries: 5,
          currentImage: 1,
          totalImages: 4,
        ),
      ),
    );
    expect(find.text('1/4 40%'), findsOneWidget);
    expect(find.textContaining('重试'), findsNothing);

    await tester.pumpWidget(
      button(
        const ImageGenerationState(
          status: GenerationStatus.generating,
          progress: 0.4,
        ),
      ),
    );
    expect(find.text('1/1 40%'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('generation-mobile-retry-label')),
      findsNothing,
    );
  });
}

class _StateImageGenerationNotifier extends ImageGenerationNotifier {
  _StateImageGenerationNotifier(this.initial);

  final ImageGenerationState initial;

  @override
  ImageGenerationState build() => initial;
  void update(ImageGenerationState value) => state = value;
}

Widget _subject({
  String model = ImageModels.animeDiffusionV5Full,
  double textScale = 1,
}) => ProviderScope(
  overrides: [
    subscriptionNotifierProvider.overrideWith(_FakeSubscriptionNotifier.new),
    generationParamsNotifierProvider.overrideWith(
      () => _FakeGenerationParamsNotifier(model),
    ),
    estimatedCostProvider.overrideWith((ref) => 0),
  ],
  child: MaterialApp(
    theme: AppTheme.getTheme(Brightness.light),
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, app) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        disableAnimations: true,
        textScaler: TextScaler.linear(textScale),
      ),
      child: app!,
    ),
    home: Scaffold(
      body: const SizedBox.expand(),
      bottomNavigationBar: MobileGenerateBar(
        data: const MobileGenerationViewData(
          batchStatus: (
            isGenerating: false,
            isPreparing: false,
            currentImage: 0,
            totalImages: 0,
          ),
          cooldownRemainingSeconds: 0,
          keyboardVisible: false,
          isGenerating: false,
          isLauncherGenerating: false,
          requiresLogin: false,
          showRandomTools: false,
          isUpscaleMode: false,
          randomModeEnabled: false,
        ),
        onGenerate: () {},
        onCancel: () {},
        onSkipCurrent: () {},
        onAddToQueue: () {},
        onOpenAgent: () {},
      ),
    ),
  ),
);

class _FakeSubscriptionNotifier extends SubscriptionNotifier {
  @override
  SubscriptionState build() => const SubscriptionState.loaded(
    UserSubscription(
      tier: 3,
      active: true,
      trainingStepsLeft: TrainingStepsInfo(fixedTrainingStepsLeft: 9993),
      usage: OpusUsageInfo(
        percent: 86,
        isNegative: false,
        timeUntilNextPercent: 6780,
      ),
    ),
  );
}

class _FakeGenerationParamsNotifier extends GenerationParamsNotifier {
  _FakeGenerationParamsNotifier(this.model);

  final String model;

  @override
  ImageParams build() => ImageParams(model: model);
}
