import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nai_launcher/core/constants/storage_keys.dart';
import 'package:nai_launcher/core/storage/local_storage_service.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/providers/generation/generation_preview_visibility_provider.dart';
import 'package:nai_launcher/presentation/providers/image_generation_provider.dart';
import 'package:nai_launcher/presentation/screens/generation/widgets/generation_controls/generation_active_label.dart';
import 'package:nai_launcher/presentation/widgets/common/generation_dot_field.dart';
import 'package:nai_launcher/presentation/widgets/common/image_card_stream_preview.dart';
import 'package:nai_launcher/presentation/widgets/common/selectable_image_card.dart';

import '../../../helpers/memory_local_storage.dart';

void main() {
  test(
    'preview visibility persists independently of streaming transport',
    () async {
      final storage = MemoryLocalStorage();
      final container = ProviderContainer(
        overrides: [localStorageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);
      expect(container.read(generationPreviewVisibilityProvider), isTrue);
      await container
          .read(generationPreviewVisibilityProvider.notifier)
          .setEnabled(false);
      expect(storage.values[StorageKeys.generationShowStreamPreview], isFalse);
      expect(container.read(generationStreamPreviewSettingsProvider), isTrue);
      final restored = ProviderContainer(
        overrides: [localStorageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(restored.dispose);
      expect(restored.read(generationPreviewVisibilityProvider), isFalse);
    },
  );

  testWidgets(
    'hidden previews keep dots on the canvas while button progress advances',
    (tester) async {
      final bytes = Uint8List.fromList(
        img.encodePng(img.Image(width: 16, height: 16)),
      );
      final storage = MemoryLocalStorage()
        ..values[StorageKeys.generationShowStreamPreview] = false;
      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(storage),
          imageGenerationNotifierProvider.overrideWith(
            () => _GenerationState(bytes),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: Column(
                children: [
                  SizedBox.square(
                    dimension: 200,
                    child: SelectableImageCard(
                      isGenerating: true,
                      imageWidth: 16,
                      imageHeight: 16,
                      streamPreview: bytes,
                      enableSelection: false,
                    ),
                  ),
                  const SizedBox(
                    width: 200,
                    height: 52,
                    child: GenerationActiveLabel(),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ImageCardStreamPreview), findsNothing);
      expect(find.byType(GenerationDotField), findsOneWidget);
      expect(find.text('1/3 40%'), findsOneWidget);
      final notifier =
          container.read(imageGenerationNotifierProvider.notifier)
              as _GenerationState;
      notifier.progress(0.7);
      await tester.pump();
      expect(find.text('1/3 70%'), findsOneWidget);
      expect(
        container.read(imageGenerationNotifierProvider).streamPreview,
        same(bytes),
      );
      await container
          .read(generationPreviewVisibilityProvider.notifier)
          .setEnabled(true);
      await tester.pumpAndSettle();
      expect(find.byType(ImageCardStreamPreview), findsOneWidget);
      expect(find.text('1/3 70%'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

class _GenerationState extends ImageGenerationNotifier {
  _GenerationState(this.preview);
  final Uint8List preview;
  @override
  ImageGenerationState build() => ImageGenerationState(
    status: GenerationStatus.generating,
    currentImage: 1,
    totalImages: 3,
    progress: 0.4,
    streamPreview: preview,
  );
  void progress(double value) => state = state.copyWith(progress: value);
}
