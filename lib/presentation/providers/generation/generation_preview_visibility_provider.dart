import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/storage_keys.dart';
import '../../../core/storage/local_storage_service.dart';

final generationPreviewVisibilityProvider =
    NotifierProvider<GenerationPreviewVisibility, bool>(
      GenerationPreviewVisibility.new,
    );

class GenerationPreviewVisibility extends Notifier<bool> {
  @override
  bool build() => ref
      .read(localStorageServiceProvider)
      .getSetting<bool>(
        StorageKeys.generationShowStreamPreview,
        defaultValue: true,
      )!;

  Future<void> setEnabled(bool value) async {
    await ref
        .read(localStorageServiceProvider)
        .setSetting(StorageKeys.generationShowStreamPreview, value);
    state = value;
  }
}
