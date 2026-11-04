import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/autocomplete/tag_translation_lookup.dart';
import 'package:nai_launcher/core/storage/local_storage_service.dart';
import 'package:nai_launcher/data/models/gallery/local_image_record.dart';
import 'package:nai_launcher/data/models/gallery/nai_image_metadata.dart';
import 'package:nai_launcher/data/models/gallery/prompt_group_snapshot.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/widgets/common/image_detail/components/detail_metadata_panel.dart';
import 'package:nai_launcher/presentation/widgets/common/image_detail/components/detail_prompt_groups.dart';
import 'package:nai_launcher/presentation/widgets/common/image_detail/image_detail_data.dart';

import '../../../../../helpers/memory_local_storage.dart';

final _pixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

class _GalleryImage extends LocalImageDetailData {
  _GalleryImage(String id, this.loaded)
    : super(
        LocalImageRecord(
          path: id,
          size: 100,
          modifiedAt: DateTime(2026),
          metadata: const NaiImageMetadata(prompt: 'cat, dog'),
        ),
      );
  final Future<NaiImageMetadata?> loaded;
  @override
  Future<NaiImageMetadata?> getMetadataAsync() => loaded;
  @override
  Future<Uint8List> getImageBytes() async => _pixel;
}

NaiImageMetadata _grouped() => NaiImageMetadata(
  prompt: 'cat, dog',
  promptGroupData: const PromptGroupSnapshot(
    groupedMode: true,
    positiveSections: [
      PromptGroupSectionSnapshot(id: 'a', text: 'cat'),
      PromptGroupSectionSnapshot(id: 'b', text: 'dog'),
    ],
    negativeSections: [],
  ).toJson(),
);

Widget _panel(ImageDetailData image) => ProviderScope(
  overrides: [
    localStorageServiceProvider.overrideWithValue(MemoryLocalStorage()),
    tagTranslationLookupProvider.overrideWithValue(
      TagTranslationLookup.fromResolver((_) async => {}),
    ),
  ],
  child: MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: DetailMetadataPanel(
        currentImage: image,
        collapsible: false,
        expandedWidth: 360,
      ),
    ),
  ),
);

void main() {
  testWidgets('gallery detail hydrates groups despite an existing PNG record', (
    tester,
  ) async {
    final loaded = Completer<NaiImageMetadata?>();
    await tester.pumpWidget(
      _panel(_GalleryImage('gallery.png', loaded.future)),
    );
    await tester.pump();
    expect(find.byType(DetailPromptGroups), findsNothing);
    loaded.complete(_grouped());
    await tester.pumpAndSettle();
    expect(find.byType(DetailPromptGroups), findsOneWidget);
    expect(find.text('Section 1'), findsOneWidget);
    expect(find.text('Section 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('late gallery metadata cannot replace the next image details', (
    tester,
  ) async {
    final loaded = Completer<NaiImageMetadata?>();
    await tester.pumpWidget(_panel(_GalleryImage('old.png', loaded.future)));
    await tester.pump();
    await tester.pumpWidget(
      _panel(
        GeneratedImageDetailData(
          imageBytes: _pixel,
          id: 'new.png',
          metadata: const NaiImageMetadata(prompt: 'new image'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    loaded.complete(_grouped());
    await tester.pumpAndSettle();
    expect(find.byType(DetailPromptGroups), findsNothing);
    expect(find.text('new image'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
