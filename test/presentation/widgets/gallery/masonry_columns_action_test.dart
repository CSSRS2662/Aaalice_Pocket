import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/constants/storage_keys.dart';
import 'package:nai_launcher/core/storage/local_storage_service.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/providers/grid_columns_provider.dart';
import 'package:nai_launcher/presentation/widgets/gallery/library_masonry_grid.dart';
import 'package:nai_launcher/presentation/widgets/gallery/masonry_columns_action.dart';

import '../../../helpers/memory_local_storage.dart';

const _surface = GridColumnsSurface.localGallery;

Future<void> _pump(WidgetTester tester, MemoryLocalStorage storage) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [localStorageServiceProvider.overrideWith((ref) => storage)],
      child: MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: Column(
            children: [
              const MasonryColumnsAction(surface: _surface),
              Expanded(
                child: Consumer(
                  builder: (context, ref, _) => LibraryMasonryGrid(
                    preferredColumns: ref.watch(gridColumnsProvider(_surface)),
                    itemCount: 8,
                    aspectRatioOf: (_) => 1,
                    itemBuilder: (context, index, size) => SizedBox.fromSize(
                      key: ValueKey('tile-$index'),
                      size: size,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Tiles whose top edge matches the first tile's: one row of the grid.
int _firstRow(WidgetTester tester) {
  final top = tester.getTopLeft(find.byKey(const ValueKey('tile-0'))).dy;
  return [
    for (var index = 0; index < 8; index++)
      if (tester.getTopLeft(find.byKey(ValueKey('tile-$index'))).dy == top)
        index,
  ].length;
}

void main() {
  testWidgets('the switch goes 2 → 3 → 4 → 2 and remembers the choice', (
    tester,
  ) async {
    final storage = MemoryLocalStorage();
    await _pump(tester, storage);
    expect(_firstRow(tester), 2);

    final button = find.byKey(MasonryColumnsAction.buttonKey(_surface));
    for (final expected in [3, 4, 2]) {
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(_firstRow(tester), expected);
      expect(storage.values[StorageKeys.localGalleryMasonryColumns], expected);
      expect(find.text('$expected 列'), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('a stored choice comes back, clamped to 2–4', (tester) async {
    final storage = MemoryLocalStorage()
      ..values[StorageKeys.localGalleryMasonryColumns] = 4;
    await _pump(tester, storage);
    expect(_firstRow(tester), 4);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(LibraryMasonryGrid)),
    );
    container.read(gridColumnsProvider(_surface).notifier).set(1);
    await tester.pumpAndSettle();
    expect(_firstRow(tester), 2);
  });
}
