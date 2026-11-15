import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/autocomplete/autocomplete_settings.dart';
import 'package:nai_launcher/core/autocomplete/completion_models.dart';
import 'package:nai_launcher/core/storage/local_storage_service.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/screens/settings/widgets/online_tag_source_settings.dart';

import '../../../../helpers/memory_local_storage.dart';

void main() {
  testWidgets('source and fallback choices persist on a narrow screen', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final storage = MemoryLocalStorage();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [localStorageServiceProvider.overrideWithValue(storage)],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(3)),
            child: child!,
          ),
          home: const Scaffold(
            body: SingleChildScrollView(child: OnlineTagSourceSettings()),
          ),
        ),
      ),
    );
    final dropdown = find.byKey(const ValueKey('autocomplete-online-source'));
    expect(
      tester.widget<DropdownButton<OnlineTagProvider>>(dropdown).value,
      OnlineTagProvider.danbooru,
    );
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('AIBooru').last);
    await tester.pumpAndSettle();
    final fallback = find.text('失败时查询备用源');
    await tester.ensureVisible(fallback);
    await tester.tap(fallback);
    await tester.pumpAndSettle();

    final restored = ProviderContainer(
      overrides: [localStorageServiceProvider.overrideWithValue(storage)],
    );
    addTearDown(restored.dispose);
    final settings = restored.read(autocompleteSettingsProvider);
    expect(settings.onlineTagProvider, OnlineTagProvider.aibooru);
    expect(settings.onlineTagFallback, isTrue);
    expect(tester.takeException(), isNull);
  });
}
