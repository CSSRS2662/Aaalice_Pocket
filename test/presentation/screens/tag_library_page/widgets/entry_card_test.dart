import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/models/tag_library/tag_library_entry.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/screens/tag_library_page/widgets/entry_card.dart';
import 'package:nai_launcher/presentation/widgets/common/thumbnail_display.dart';
import 'package:nai_launcher/presentation/widgets/tag_library/library_group_style.dart';

TagLibraryEntry _entry({
  String id = 'entry',
  bool favorite = false,
  String? thumbnail,
}) => TagLibraryEntry(
  id: id,
  name: '测试词条',
  content: '1girl,\n solo, smile',
  isFavorite: favorite,
  thumbnail: thumbnail,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

Future<void> _pump(
  WidgetTester tester,
  EntryCard card, {
  Size size = const Size(200, 64),
}) => tester.pumpWidget(
  MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Center(
        child: SizedBox(width: size.width, height: size.height, child: card),
      ),
    ),
  ),
);

void main() {
  testWidgets('shows the name, a one-line snippet, heart and pin', (
    tester,
  ) async {
    final entry = _entry(favorite: true);
    await _pump(
      tester,
      EntryCard(
        entry: entry,
        groupStyle: LibraryGroupStyle.generic,
        isFixedTag: true,
        onTap: () {},
      ),
    );

    expect(find.text('测试词条'), findsOneWidget);
    expect(find.text('1girl, solo, smile'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('tag-library-entry-favorite-entry')),
      findsOne,
    );
    expect(
      find.byKey(const ValueKey('tag-library-entry-fixed-entry')),
      findsOne,
    );
    expect(find.byType(LibraryGroupIcon), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tap opens, long-press starts selecting', (tester) async {
    final calls = <String>[];
    await _pump(
      tester,
      EntryCard(
        entry: _entry(),
        groupStyle: LibraryGroupStyle.generic,
        onTap: () => calls.add('open'),
        onToggleSelection: () => calls.add('select'),
      ),
    );

    await tester.tap(find.byType(EntryCard));
    await tester.longPress(find.byType(EntryCard));
    await tester.pump();

    expect(calls, ['open', 'select']);
  });

  testWidgets('in selection mode a tap toggles and the card is outlined', (
    tester,
  ) async {
    final calls = <String>[];
    await _pump(
      tester,
      EntryCard(
        entry: _entry(),
        groupStyle: LibraryGroupStyle.generic,
        isSelectionMode: true,
        isSelected: true,
        onTap: () => calls.add('open'),
        onToggleSelection: () => calls.add('toggle'),
      ),
    );

    await tester.tap(find.byType(EntryCard));
    expect(calls, ['toggle']);
    final decoration =
        tester
                .widget<Ink>(
                  find.descendant(
                    of: find.byType(EntryCard),
                    matching: find.byType(Ink),
                  ),
                )
                .decoration!
            as BoxDecoration;
    final scheme = Theme.of(tester.element(find.byType(EntryCard))).colorScheme;
    expect(decoration.color, scheme.primaryContainer);
    expect((decoration.border! as Border).top.color, scheme.primary);
  });

  testWidgets('keeps the thumbnail when selection mode changes', (
    tester,
  ) async {
    final entry = _entry(thumbnail: 'missing-thumbnail.png');
    Future<void> pump({required bool selecting}) => _pump(
      tester,
      EntryCard(
        entry: entry,
        groupStyle: LibraryGroupStyle.generic,
        isSelectionMode: selecting,
        onTap: () {},
        onToggleSelection: () {},
      ),
    );

    await pump(selecting: false);
    await tester.pump();
    final state = tester.state(find.byType(ThumbnailDisplay));
    expect(
      tester.widget<ThumbnailDisplay>(find.byType(ThumbnailDisplay)).width,
      40,
    );

    await pump(selecting: true);
    expect(tester.state(find.byType(ThumbnailDisplay)), same(state));
  });

  testWidgets('shared hover preview closes when selecting starts', (
    tester,
  ) async {
    final entry = _entry(thumbnail: 'missing-thumbnail.png');
    Future<void> pump({required bool selecting}) => _pump(
      tester,
      EntryCard(
        entry: entry,
        groupStyle: LibraryGroupStyle.generic,
        isSelectionMode: selecting,
        onTap: () {},
        onToggleSelection: () {},
      ),
      size: const Size(240, 64),
    );

    await pump(selecting: false);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer();
    await mouse.moveTo(tester.getCenter(find.byType(EntryCard)));
    await tester.pump(const Duration(milliseconds: 800));

    const previewKey = ValueKey('tag-library-entry-preview-overlay');
    expect(find.byKey(previewKey), findsOneWidget);

    await pump(selecting: true);
    await tester.pump();
    expect(find.byKey(previewKey), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('3x text fits the card height it asks for', (tester) async {
    late double extent;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(3)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              extent = EntryCard.extentFor(
                context,
                textScaler: MediaQuery.textScalerOf(context),
              );
              return Center(
                child: SizedBox(
                  width: 300,
                  height: extent,
                  child: EntryCard(
                    entry: _entry(favorite: true),
                    groupStyle: LibraryGroupStyle.generic,
                    isFixedTag: true,
                    onTap: () {},
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    expect(extent, greaterThan(100));
    expect(tester.takeException(), isNull);
  });
}
