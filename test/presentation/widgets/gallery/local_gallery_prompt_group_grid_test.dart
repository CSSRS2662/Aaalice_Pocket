import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/models/gallery/gallery_prompt_group.dart';
import 'package:nai_launcher/data/models/gallery/local_image_record.dart';
import 'package:nai_launcher/data/models/gallery/nai_image_metadata.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/providers/generation/generation_models.dart';
import 'package:nai_launcher/presentation/providers/local_gallery_prompt_groups_provider.dart';
import 'package:nai_launcher/presentation/widgets/gallery/gallery_grid.dart';
import 'package:nai_launcher/presentation/widgets/gallery/local_gallery_prompt_group_grid.dart';
import 'package:nai_launcher/presentation/widgets/gallery/local_image_card_3d.dart';
import 'package:visibility_detector/visibility_detector.dart';

void main() {
  for (final (width, panelKey) in [
    (320.0, 'adaptive-bottom-sheet'),
    (1180.0, 'adaptive-centered-form'),
  ]) {
    testWidgets('group opens a separate browser at ${width.toInt()}px', (
      tester,
    ) async {
      final visibility = VisibilityDetectorController.instance;
      final originalInterval = visibility.updateInterval;
      visibility.updateInterval = Duration.zero;
      addTearDown(() => visibility.updateInterval = originalInterval);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 780);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final older = _record('forest-old', 'forest', 1);
      final cover = _record('forest-new', 'forest', 2);
      final other = _record('coast', 'coast', 3);
      final latest = GeneratedImage(
        id: 'latest',
        bytes: base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO6qv0YAAAAASUVORK5CYII=',
        ),
        width: 1216,
        height: 832,
        createdAt: DateTime(2026, 11, 4),
        metadata: cover.metadata,
      );
      final groups = GalleryPromptGroup.fromFavorites(
        [older, cover, other],
        recentGenerations: [
          (
            id: latest.id,
            metadata: latest.metadata,
            createdAt: latest.createdAt,
          ),
        ],
      );
      List<LocalImageRecord>? openedImages;
      int? openedIndex;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localGalleryPromptGroupsProvider.overrideWith((ref) => groups),
          ],
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
            home: Scaffold(
              body: Builder(
                builder: (context) => LocalGalleryPromptGroupGrid(
                  groups: groups,
                  preferredColumns: 2,
                  history: {latest.id: latest},
                  onOpen: (group) => showLocalGalleryPromptGroup(
                    context,
                    promptKey: group.promptKey,
                    columns: 2,
                    onOpenImage: (_, images, index) {
                      openedImages = images;
                      openedIndex = index;
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      final groupCard = find.byKey(ValueKey(groups.first.promptKey));
      final otherCard = find.byKey(ValueKey(groups.last.promptKey));
      final groupSize = tester.getSize(groupCard);
      final otherSize = tester.getSize(otherCard);
      expect(groupSize.width / groupSize.height, closeTo(1216 / 832, 0.01));
      expect(otherSize.width / otherSize.height, closeTo(832 / 1216, 0.01));
      final groupImage = tester.widget<Image>(
        find.descendant(of: groupCard, matching: find.byType(Image)),
      );
      expect(
        (groupImage.image as ResizeImage).imageProvider,
        MemoryImage(latest.bytes),
      );
      await tester.tap(groupCard);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
      expect(find.byKey(ValueKey(panelKey)), findsOneWidget);
      final browser = find.byKey(
        const ValueKey('local-gallery-same-prompt-dialog-grid'),
      );
      final grid = tester.widget<GalleryGrid>(browser);
      expect(grid.images, [cover, older]);
      expect(openedImages, isNull);

      await tester.tap(
        find.byWidgetPredicate(
          (widget) => widget is LocalImageCard3D && widget.record == older,
        ),
      );
      expect(openedImages, [cover, older]);
      expect(openedIndex, 1);

      Navigator.of(tester.element(browser)).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
      expect(browser, findsNothing);
      expect(groupCard, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

LocalImageRecord _record(String name, String prompt, int day) =>
    LocalImageRecord(
      path: 'G:/gallery/$name.png',
      size: 1,
      modifiedAt: DateTime(2026, 11, day),
      metadata: NaiImageMetadata(prompt: prompt, width: 832, height: 1216),
      isFavorite: true,
    );
