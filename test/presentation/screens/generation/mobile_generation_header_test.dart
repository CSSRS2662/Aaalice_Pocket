import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nai_launcher/core/constants/api_constants.dart';
import 'package:nai_launcher/core/constants/storage_keys.dart';
import 'package:nai_launcher/core/storage/local_storage_service.dart';
import 'package:nai_launcher/data/models/image/image_params.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/providers/image_generation_provider.dart';
import 'package:nai_launcher/data/models/user/user_subscription.dart';
import 'package:nai_launcher/presentation/providers/cost_estimate_provider.dart';
import 'package:nai_launcher/presentation/providers/subscription_provider.dart';
import 'package:nai_launcher/presentation/screens/generation/mobile_workbench/mobile_generation_header.dart';
import 'package:nai_launcher/presentation/screens/generation/mobile_workbench/effort_gauge_icon.dart';
import 'package:nai_launcher/presentation/widgets/anlas/anlas_icon.dart';
import 'package:nai_launcher/presentation/screens/generation/mobile_workbench/mobile_quota_pill.dart';
import 'package:nai_launcher/presentation/themes/pocket_accent.dart';
import 'package:nai_launcher/presentation/themes/core/layered_surface_style.dart';
import 'package:nai_launcher/presentation/themes/app_theme.dart';

import '../../../helpers/memory_local_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  final pill = find.byKey(const ValueKey('generation-mobile-model-action'));

  testWidgets('点按模型直接展开菜单切换，当前模型带勾选', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer(
      overrides: [
        generationParamsNotifierProvider.overrideWith(
          _FakeGenerationParamsNotifier.new,
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _app(const MobileModelMenu()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.descendant(of: pill, matching: find.text('V5 Full')), findsOne);
    expect(
      tester.getSemantics(pill),
      isSemantics(label: '模型 V5 Full，标准，点按切换', isButton: true),
    );

    await tester.tap(pill);
    await tester.pumpAndSettle();
    for (final id in ImageModels.allModels) {
      final item = find.byKey(ValueKey('generation-mobile-model-$id'));
      expect(item, findsOneWidget);
      expect(tester.getSize(item).height, greaterThanOrEqualTo(44));
    }
    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey(
            'generation-mobile-model-${ImageModels.animeDiffusionV5Full}',
          ),
        ),
        matching: find.byIcon(Icons.check_rounded),
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(
        const ValueKey(
          'generation-mobile-model-${ImageModels.animeDiffusionV45Full}',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      container.read(generationParamsNotifierProvider).model,
      ImageModels.animeDiffusionV45Full,
    );
    expect(
      find.descendant(of: pill, matching: find.text('V4.5 Full')),
      findsOne,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('尺寸菜单只能选择：分组预设与已保存尺寸，选中后写回参数', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final storage = MemoryLocalStorage()
      ..values[StorageKeys.customResolutionPresets] = ['896x1152'];
    final container = ProviderContainer(
      overrides: [
        generationParamsNotifierProvider.overrideWith(
          _FakeGenerationParamsNotifier.new,
        ),
        localStorageServiceProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);
    final sizePill = find.byKey(
      const ValueKey('generation-mobile-size-action'),
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _app(const MobileSizeMenu()),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: sizePill, matching: find.text('832×1216')),
      findsOne,
    );
    expect(
      tester.getSemantics(sizePill),
      isSemantics(label: '尺寸 832×1216，点按切换', isButton: true),
    );

    await tester.tap(sizePill);
    await tester.pumpAndSettle();
    final portrait = find.byKey(
      const ValueKey('generation-mobile-size-normal_portrait'),
    );
    expect(
      find.descendant(of: portrait, matching: find.byIcon(Icons.check_rounded)),
      findsOne,
    );
    expect(
      find.byKey(
        const ValueKey('generation-mobile-size-saved_custom_896_1152'),
      ),
      findsOne,
    );
    expect(find.text('常规'), findsOne);
    // Only choices: typing, saving and deleting sizes stay on the param page.
    expect(find.byType(TextField), findsNothing);
    expect(find.byKey(const ValueKey('save-custom-resolution')), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('generation-mobile-size-normal_landscape')),
    );
    await tester.pumpAndSettle();
    final params = container.read(generationParamsNotifierProvider);
    expect((params.width, params.height), (1216, 832));
    expect(
      find.descendant(of: sizePill, matching: find.text('1216×832')),
      findsOne,
    );

    await tester.tap(sizePill);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey('generation-mobile-size-saved_custom_896_1152'),
      ),
    );
    await tester.pumpAndSettle();
    final saved = container.read(generationParamsNotifierProvider);
    expect((saved.width, saved.height), (896, 1152));
    expect(tester.takeException(), isNull);
  });

  testWidgets('节约档以仪表盘代替模式文字，重选当前模型保留档位', (tester) async {
    final container = ProviderContainer(
      overrides: [
        generationParamsNotifierProvider.overrideWith(
          _FakeGenerationParamsNotifier.new,
        ),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(generationParamsNotifierProvider.notifier);
    notifier.updateModel(ImageModels.animeDiffusionV5FullMedium);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _app(const MobileModelMenu()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('V5 Full'), findsOneWidget);
    expect(find.textContaining('Medium Effort'), findsNothing);
    expect(find.byType(EffortGaugeIcon), findsOneWidget);
    expect(find.byTooltip('节约'), findsOneWidget);
    expect(find.byIcon(Icons.expand_more_rounded), findsNothing);
    expect(
      tester.getSemantics(pill),
      isSemantics(label: '模型 V5 Full，节约，点按切换', isButton: true),
    );
    final mediumWidth = tester.getSize(pill).width;

    await tester.tap(pill);
    await tester.pumpAndSettle();
    final currentItem = find.byKey(
      const ValueKey(
        'generation-mobile-model-${ImageModels.animeDiffusionV5Full}',
      ),
    );
    expect(tester.widget<MenuItemButton>(currentItem).onPressed, isNull);
    await tester.tap(currentItem);
    await tester.pumpAndSettle();
    expect(
      container.read(generationParamsNotifierProvider).model,
      ImageModels.animeDiffusionV5FullMedium,
    );
    await tester.tap(pill);
    await tester.pumpAndSettle();

    notifier.updateModel(ImageModels.animeDiffusionV5Full);
    await tester.pumpAndSettle();
    expect(find.byType(EffortGaugeIcon), findsOneWidget);
    expect(find.byTooltip('标准'), findsOneWidget);
    expect(mediumWidth, tester.getSize(pill).width);
    expect(tester.takeException(), isNull);
  });

  testWidgets('档位指针双向转动，快速反向从当前位置继续，减少动态效果时直接就位', (tester) async {
    final container = ProviderContainer(
      overrides: [
        generationParamsNotifierProvider.overrideWith(
          _FakeGenerationParamsNotifier.new,
        ),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(generationParamsNotifierProvider.notifier);
    notifier.updateModel(ImageModels.animeDiffusionV5FullMedium);
    Future<void> pumpMode({bool reduceMotion = false}) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _app(const MobileModelMenu(), disableAnimations: reduceMotion),
        ),
      );
    }

    double angle() {
      final matrix = tester
          .widget<Transform>(
            find.byKey(const ValueKey('generation-effort-needle')),
          )
          .transform;
      return math.atan2(matrix.storage[1], matrix.storage[0]);
    }

    await pumpMode();
    expect(angle(), closeTo(0, 0.001));
    notifier.updateModel(ImageModels.animeDiffusionV5Full);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(angle(), greaterThan(0));
    expect(angle(), lessThan(math.pi * 0.385));
    await tester.pumpAndSettle();
    expect(angle(), closeTo(math.pi * 0.385, 0.001));
    notifier.updateModel(ImageModels.animeDiffusionV5FullMedium);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final intermediate = angle();
    expect(intermediate, greaterThan(0));
    expect(intermediate, lessThan(math.pi * 0.385));
    notifier.updateModel(ImageModels.animeDiffusionV5Full);
    await tester.pump();
    expect(angle(), closeTo(intermediate, 0.001));
    await tester.pumpAndSettle();
    expect(angle(), closeTo(math.pi * 0.385, 0.001));
    notifier.updateModel(ImageModels.animeDiffusionV5FullMedium);
    await tester.pumpAndSettle();
    expect(angle(), closeTo(0, 0.001));
    await pumpMode(reduceMotion: true);
    notifier.updateModel(ImageModels.animeDiffusionV5Full);
    await tester.pump();
    expect(angle(), closeTo(math.pi * 0.385, 0.001));
    notifier.updateModel(ImageModels.animeDiffusionV5FullMedium);
    await tester.pump();
    expect(angle(), closeTo(0, 0.001));
    expect(tester.takeException(), isNull);
  });

  testWidgets('额度胶囊填满剩余宽度，所有模型和大字体下顶栏均无需横向拖动', (tester) async {
    final container = ProviderContainer(
      overrides: [
        generationParamsNotifierProvider.overrideWith(
          _FakeGenerationParamsNotifier.new,
        ),
        localStorageServiceProvider.overrideWithValue(MemoryLocalStorage()),
        subscriptionNotifierProvider.overrideWith(
          _FakeSubscriptionNotifier.new,
        ),
        estimatedCostProvider.overrideWith((ref) => 0),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final model = find.byKey(const ValueKey('generation-mobile-model-action'));
    final size = find.byKey(const ValueKey('generation-mobile-size-action'));
    final quota = find.byKey(const ValueKey('generation-mobile-quota'));
    final notifier = container.read(generationParamsNotifierProvider.notifier);
    for (final id in ImageModels.supportedModels) {
      notifier.updateModel(id);
      for (final width in [320.0, 600.0, 840.0, 1180.0, 1600.0]) {
        await tester.binding.setSurfaceSize(Size(width, 390));
        for (final scale in [1.0, 3.0]) {
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: _app(
                SizedBox(
                  width: width,
                  child: MediaQuery.withClampedTextScaling(
                    maxScaleFactor: MobileGenerationHeader.maxTextScale,
                    child: const MobileGenerationHeaderBar(),
                  ),
                ),
                textScale: scale,
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byType(SingleChildScrollView), findsNothing);
          expect(
            tester.getRect(size).left - tester.getRect(model).right,
            closeTo(6, 0.1),
          );
          expect(
            tester.getRect(quota).left - tester.getRect(size).right,
            closeTo(6, 0.1),
          );
          expect(tester.getRect(quota).right, closeTo(width, 0.1));
          expect(tester.getSize(quota).width, greaterThanOrEqualTo(87.9));
          for (final control in [model, size, quota]) {
            expect(tester.getSize(control).height, 44);
            expect(tester.getSize(control).width, greaterThanOrEqualTo(44));
          }
          for (final text in [
            MobileGenerationHeader.shortModelLabel(
              ImageModels.selectorModel(id),
            ),
            '832×1216',
            '9,993',
          ]) {
            final paragraph = tester.renderObject<RenderParagraph>(
              find.text(text),
            );
            expect(
              paragraph.didExceedMaxLines,
              isFalse,
              reason: '$id/$width/$scale',
            );
          }
          expect(find.textContaining('%'), findsNothing);
          expect(tester.takeException(), isNull, reason: '$id/$width/$scale');
        }
      }
    }
    final theme = Theme.of(tester.element(quota));
    expect(
      tester.widget<Material>(quota).color,
      controlSurfaceColor(theme.colorScheme),
    );
    expect(
      find.descendant(of: quota, matching: find.byType(AnlasIcon)),
      findsOneWidget,
    );
  });

  testWidgets('体力五段按实际可用量填充并跟随主题，点胶囊刷新余额及查看详情', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer(
      overrides: [
        generationParamsNotifierProvider.overrideWith(
          _FakeGenerationParamsNotifier.new,
        ),
        localStorageServiceProvider.overrideWithValue(MemoryLocalStorage()),
        subscriptionNotifierProvider.overrideWith(
          _FakeSubscriptionNotifier.new,
        ),
        estimatedCostProvider.overrideWith((ref) => 0),
      ],
    );
    addTearDown(container.dispose);
    final notifier =
        container.read(subscriptionNotifierProvider.notifier)
            as _FakeSubscriptionNotifier;
    final quota = find.byKey(const ValueKey('generation-mobile-quota'));
    final theme = AppTheme.getTheme(Brightness.dark, accent: PocketAccent.blue);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _app(
          const SizedBox(
            width: 150,
            child: MobileQuotaPill(textStyle: TextStyle(fontSize: 14)),
          ),
          theme: theme,
        ),
      ),
    );
    for (final (percent, purchased, expected) in [
      (93.0, 0.0, [1.0, 1.0, 1.0, 1.0, 0.65]),
      (0.0, 0.0, [0.0, 0.0, 0.0, 0.0, 0.0]),
      (0.0, 20.0, [1.0, 0.0, 0.0, 0.0, 0.0]),
      (-3.0, 12.0, [0.6, 0.0, 0.0, 0.0, 0.0]),
      (130.0, 0.0, [1.0, 1.0, 1.0, 1.0, 1.0]),
    ]) {
      notifier.setState(
        SubscriptionState.loaded(
          UserSubscription(
            tier: 3,
            active: true,
            trainingStepsLeft: const TrainingStepsInfo(
              fixedTrainingStepsLeft: 9993,
            ),
            usage: OpusUsageInfo(
              percent: percent,
              isNegative: percent < 0,
              purchasedPercent: purchased,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (var index = 0; index < 5; index++) {
        final fill = tester.widget<FractionallySizedBox>(
          find.byKey(ValueKey('generation-mobile-stamina-fill-$index')),
        );
        expect(fill.widthFactor, closeTo(expected[index], 0.001));
        expect((fill.child! as ColoredBox).color, theme.colorScheme.primary);
      }
      expect(find.textContaining('%'), findsNothing);
      final track = find.byKey(
        const ValueKey('generation-mobile-stamina-track'),
      );
      expect(
        find.descendant(of: track, matching: find.byType(ClipRRect)),
        findsOneWidget,
      );
      final gaps = tester
          .widgetList<SizedBox>(
            find.descendant(of: track, matching: find.byType(SizedBox)),
          )
          .where((box) => box.width != null);
      expect(gaps.length, 4);
      expect(gaps.every((gap) => gap.width == 1), isTrue);
      expect(tester.takeException(), isNull);
    }
    await tester.tap(quota);
    await tester.pumpAndSettle();
    expect(notifier.refreshes, 1);
    final details = find.byKey(const ValueKey('opus-stamina-details'));
    expect(details, findsOneWidget);
    Navigator.of(tester.element(details)).pop();
    await tester.pumpAndSettle();
    container
        .read(generationParamsNotifierProvider.notifier)
        .updateModel(ImageModels.animeDiffusionV45Full);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('generation-mobile-stamina-track')),
      findsNothing,
    );
    await tester.tap(quota);
    await tester.pumpAndSettle();
    expect(notifier.refreshes, 2);
    expect(details, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('额度加载与缺失状态保持胶囊尺寸，错误可重试', (tester) async {
    final container = ProviderContainer(
      overrides: [
        generationParamsNotifierProvider.overrideWith(
          _FakeGenerationParamsNotifier.new,
        ),
        subscriptionNotifierProvider.overrideWith(
          _FakeSubscriptionNotifier.new,
        ),
        estimatedCostProvider.overrideWith((ref) => 0),
      ],
    );
    addTearDown(container.dispose);
    final notifier =
        container.read(subscriptionNotifierProvider.notifier)
            as _FakeSubscriptionNotifier;
    final quota = find.byKey(const ValueKey('generation-mobile-quota'));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _app(
          const SizedBox(
            width: 88,
            child: MobileQuotaPill(textStyle: TextStyle(fontSize: 14)),
          ),
        ),
      ),
    );
    for (final state in [
      const SubscriptionState.loading(),
      const SubscriptionState.unsupported(),
      const SubscriptionState.error('offline'),
    ]) {
      notifier.setState(state);
      await tester.pumpAndSettle();
      expect(tester.getSize(quota), const Size(88, 44));
      expect(
        find.byKey(const ValueKey('generation-mobile-stamina-track')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    }
    expect(find.byTooltip('点击重试'), findsOneWidget);
    await tester.tap(quota);
    await tester.pumpAndSettle();
    expect(notifier.fetches, 1);
  });
}

Widget _app(
  Widget child, {
  double textScale = 1,
  ThemeData? theme,
  bool disableAnimations = true,
}) => MaterialApp(
  theme: theme ?? AppTheme.getTheme(Brightness.light),
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, app) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      disableAnimations: disableAnimations,
      textScaler: TextScaler.linear(textScale),
    ),
    child: app!,
  ),
  home: Scaffold(
    body: Align(alignment: Alignment.topLeft, child: child),
  ),
);

class _FakeGenerationParamsNotifier extends GenerationParamsNotifier {
  @override
  ImageParams build() => const ImageParams(
    model: ImageModels.animeDiffusionV5Full,
    width: 832,
    height: 1216,
  );

  @override
  void updateSize(int width, int height, {bool persist = true}) {
    state = state.copyWith(width: width, height: height);
  }

  @override
  void updateModel(
    String model, {
    bool persist = true,
    bool followDefaults = true,
  }) {
    state = state.copyWith(model: model);
  }
}

class _FakeSubscriptionNotifier extends SubscriptionNotifier {
  int refreshes = 0;
  int fetches = 0;

  void setState(SubscriptionState value) => state = value;

  @override
  Future<bool> refreshBalance({
    SubscriptionRefreshPriority priority =
        SubscriptionRefreshPriority.background,
  }) async {
    refreshes++;
    return true;
  }

  @override
  Future<void> fetchSubscription() async {
    fetches++;
  }

  @override
  SubscriptionState build() => const SubscriptionState.loaded(
    UserSubscription(
      tier: 3,
      active: true,
      trainingStepsLeft: TrainingStepsInfo(fixedTrainingStepsLeft: 9993),
      usage: OpusUsageInfo(
        percent: 93,
        isNegative: false,
        timeUntilNextPercent: 600,
      ),
    ),
  );
}
