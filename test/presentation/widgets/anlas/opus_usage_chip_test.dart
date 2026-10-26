import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/constants/api_constants.dart';
import 'package:nai_launcher/core/services/opus_usage_estimator.dart';
import 'package:nai_launcher/data/models/image/image_params.dart';
import 'package:nai_launcher/data/models/user/user_subscription.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/providers/cost_estimate_provider.dart';
import 'package:nai_launcher/presentation/providers/generation/image_workflow_controller.dart';
import 'package:nai_launcher/presentation/providers/image_generation_provider.dart';
import 'package:nai_launcher/presentation/providers/subscription_provider.dart';
import 'package:nai_launcher/presentation/widgets/anlas/opus_usage_chip.dart';

class _SubscriptionStub extends SubscriptionNotifier {
  _SubscriptionStub(this._state);

  final SubscriptionState _state;

  @override
  SubscriptionState build() => _state;

  @override
  void schedulePostBillingRefresh({Duration delay = Duration.zero}) {}
}

Future<void> _pumpChip(
  WidgetTester tester,
  SubscriptionState subscription,
  String model, {
  void Function(ProviderContainer container)? configure,
}) async {
  final container = ProviderContainer(
    overrides: [
      subscriptionNotifierProvider.overrideWith(
        () => _SubscriptionStub(subscription),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Center(child: OpusUsageChip())),
      ),
    ),
  );
  // pumpWidget 之后再切模型，避免 auto-dispose 调度的 Timer 悬挂在帧外。
  container
      .read(generationParamsNotifierProvider.notifier)
      .updateModel(model, persist: false, followDefaults: false);
  configure?.call(container);
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const opusWithUsage = SubscriptionState.loaded(
    UserSubscription(
      tier: 3,
      active: true,
      usage: OpusUsageInfo(percent: 98, timeUntilNextPercent: 4800),
    ),
  );

  testWidgets('shows the remaining percent on V5 for Opus accounts', (
    tester,
  ) async {
    await _pumpChip(tester, opusWithUsage, ImageModels.animeDiffusionV5Curated);

    expect(find.text('98%'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('shows overflow quota without capping the text or estimate', (
    tester,
  ) async {
    const overflowUsage = SubscriptionState.loaded(
      UserSubscription(
        tier: 3,
        active: true,
        usage: OpusUsageInfo(percent: 192),
      ),
    );

    late ImageParams params;
    await _pumpChip(
      tester,
      overflowUsage,
      ImageModels.animeDiffusionV5Curated,
      configure: (container) =>
          params = container.read(generationParamsNotifierProvider),
    );

    expect(find.text('192%'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    // Counted by the Anlas price of one image at the current settings.
    final price = opusUsageImageAnlas(params, const ImageWorkflowState())!;
    final images = OpusUsageEstimator.imagesForPercent(192, imageAnlas: price);
    expect(images, (192 * 17.3 * 26 / price).round());
    expect(tooltip.message, contains('About $images images left'));
  });

  testWidgets('max enhance bills above 1 MP, which is not free', (
    tester,
  ) async {
    await _pumpChip(
      tester,
      opusWithUsage,
      ImageModels.animeDiffusionV5Curated,
      configure: (container) {
        final notifier = container.read(
          generationParamsNotifierProvider.notifier,
        );
        notifier.updateSize(832, 1216, persist: false);
        notifier.updateUpscaledEnhance(true);
      },
    );

    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(tooltip.message, contains('Stamina not used'));
    expect(tooltip.message, isNot(contains('images left')));
  });

  testWidgets('stays hidden on models without the quota pool', (tester) async {
    await _pumpChip(tester, opusWithUsage, ImageModels.animeDiffusionV45Full);

    expect(find.byType(Tooltip), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('stays hidden when the subscription has no usage info', (
    tester,
  ) async {
    const opusWithoutUsage = SubscriptionState.loaded(
      UserSubscription(tier: 3, active: true),
    );

    await _pumpChip(
      tester,
      opusWithoutUsage,
      ImageModels.animeDiffusionV5Curated,
    );

    expect(find.byType(Tooltip), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('switches to the exhausted style when the quota is negative', (
    tester,
  ) async {
    const exhausted = SubscriptionState.loaded(
      UserSubscription(
        tier: 3,
        active: true,
        usage: OpusUsageInfo(percent: -2, isNegative: true),
      ),
    );

    await _pumpChip(tester, exhausted, ImageModels.animeDiffusionV5Curated);

    expect(find.text('0%'), findsOneWidget);
    expect(find.byIcon(Icons.hourglass_bottom_rounded), findsOneWidget);
  });

  testWidgets('stays hidden for non-Opus tiers', (tester) async {
    const scroll = SubscriptionState.loaded(
      UserSubscription(
        tier: 2,
        active: true,
        usage: OpusUsageInfo(percent: 50),
      ),
    );

    await _pumpChip(tester, scroll, ImageModels.animeDiffusionV5Curated);

    expect(find.byType(Tooltip), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
}
