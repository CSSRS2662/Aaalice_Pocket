import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/widgets/prompt/tag_selection_bar.dart';

void main() {
  for (final width in [320.0, 600.0, 840.0, 1180.0, 1600.0]) {
    testWidgets('selection actions remain reachable at $width and 3x text', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var copies = 0;
      var moves = 0;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 600),
              textScaler: const TextScaler.linear(3),
            ),
            child: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: TagSelectionBar(
                  count: 12,
                  onClose: () {},
                  onSelectAll: () {},
                  onCopy: () => copies++,
                  onMove: () => moves++,
                ),
              ),
            ),
          ),
        ),
      );
      final copy = find.byKey(const ValueKey('tag-selection-copy'));
      final move = find.byKey(const ValueKey('tag-selection-move'));
      expect(tester.getSize(copy).height, greaterThanOrEqualTo(44));
      expect(tester.getSize(move).height, greaterThanOrEqualTo(44));
      await tester.tap(copy);
      await tester.tap(move);
      expect(copies, 1);
      expect(moves, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
