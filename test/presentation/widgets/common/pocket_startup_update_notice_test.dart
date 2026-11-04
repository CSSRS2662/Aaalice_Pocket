import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/constants/app_version.dart';
import 'package:nai_launcher/core/services/pocket_update_service.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/widgets/common/action_notice.dart';
import 'package:nai_launcher/presentation/widgets/common/pocket_startup_update_notice.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  setUpAll(() async {
    PackageInfo.setMockInitialValues(
      appName: 'Aaalice Pocket',
      packageName: 'com.cssrs2662.aaalicepocket',
      version: '1.0.0',
      buildNumber: '124',
      buildSignature: '',
    );
    await AppVersion.initialize();
  });

  for (final size in const [
    Size(320, 720),
    Size(600, 720),
    Size(840, 440),
    Size(1180, 720),
    Size(1600, 720),
  ]) {
    testWidgets('shows startup release details and actions at $size', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      addTearDown(ActionNotice.dismiss);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(3),
                padding: const EdgeInsets.only(bottom: 16),
              ),
              child: child!,
            ),
            home: const Scaffold(
              body: PocketStartupUpdateNotice(child: SizedBox.expand()),
            ),
          ),
        ),
      );
      expect(find.text('查看详情'), findsNothing);
      container
          .read(pocketStartupUpdateProvider.notifier)
          .state = PocketRelease(
        version: '1.1.0',
        notes: '发布说明',
        apkUrl: Uri.https('github.com', '/test.apk'),
        apkSize: 270 * 1024 * 1024,
        sha256: '',
      );
      await tester.pumpAndSettle();
      final details = find.text('查看详情');
      expect(details.hitTestable(), findsOneWidget);
      expect(container.read(pocketStartupUpdateProvider), isNull);
      await tester.tap(details);
      await tester.pumpAndSettle();
      expect(find.text('发现新版本 · v1.1.0'), findsOneWidget);
      for (final label in ['发布说明', '前往项目地址', '关闭', '一键更新']) {
        final text = find.text(label, findRichText: true);
        if (text.hitTestable().evaluate().isEmpty) {
          final scrollable = find.byType(Scrollable).last;
          await tester.scrollUntilVisible(text, 70, scrollable: scrollable);
          await tester.pumpAndSettle();
        }
        expect(text.hitTestable(), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
