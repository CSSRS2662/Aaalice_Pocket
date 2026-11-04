import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/constants/storage_keys.dart';
import 'package:nai_launcher/core/storage/local_storage_service.dart';
import 'package:nai_launcher/data/models/gallery/prompt_group_snapshot.dart';
import 'package:nai_launcher/data/models/image/image_params.dart';
import 'package:nai_launcher/presentation/providers/generation/generation_params_notifier.dart';
import 'package:nai_launcher/presentation/providers/prompt_group_state_provider.dart';
import 'package:nai_launcher/presentation/widgets/common/image_detail/components/detail_prompt_group_reuse.dart';

import '../../../../../helpers/memory_local_storage.dart';

class _Params extends GenerationParamsNotifier {
  _Params(this.initial);
  final ImageParams initial;
  @override
  ImageParams build() => initial;
  @override
  void updatePrompt(String prompt) => state = state.copyWith(prompt: prompt);
  @override
  void updateNegativePrompt(String prompt) =>
      state = state.copyWith(negativePrompt: prompt);
}

void main() {
  test('reusing into an empty grouped editor fills its blank card', () async {
    final storage = MemoryLocalStorage();
    final container = ProviderContainer(
      overrides: [
        localStorageServiceProvider.overrideWithValue(storage),
        generationParamsNotifierProvider.overrideWith(
          () => _Params(const ImageParams()),
        ),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(currentPromptGroupSnapshotProvider.notifier)
        .state = const PromptGroupSnapshot(
      groupedMode: true,
      positiveSections: [PromptGroupSectionSnapshot(id: 'blank', text: '')],
      negativeSections: [],
    );
    final state = container.read(detailPromptGroupStateProvider);
    await appendDetailPromptGroup(state, 'saved card', negative: false);
    expect(state.read().positiveSections, hasLength(1));
    expect(state.read().positivePrompt, 'saved card');
  });

  for (final grouped in [false, true]) {
    test(
      'reuse appends to latest $grouped prompt without changing the other side',
      () async {
        final snapshot = PromptGroupSnapshot(
          groupedMode: grouped,
          positiveSections: const [
            PromptGroupSectionSnapshot(id: 'a', text: 'latest edit'),
            PromptGroupSectionSnapshot(
              id: 'off',
              text: 'disabled',
              enabled: false,
            ),
          ],
          negativeSections: const [
            PromptGroupSectionSnapshot(id: 'n', text: 'lowres'),
          ],
        );
        final storage = MemoryLocalStorage();
        final container = ProviderContainer(
          overrides: [
            localStorageServiceProvider.overrideWithValue(storage),
            generationParamsNotifierProvider.overrideWith(
              () => _Params(
                ImageParams(
                  prompt: snapshot.positivePrompt,
                  negativePrompt: snapshot.negativePrompt,
                ),
              ),
            ),
          ],
        );
        addTearDown(container.dispose);
        container.read(currentPromptGroupSnapshotProvider.notifier).state =
            snapshot;
        final state = container.read(detailPromptGroupStateProvider);
        await appendDetailPromptGroup(
          state,
          '1.2::saved style::',
          negative: false,
        );
        await appendDetailPromptGroup(state, 'snow', negative: false);
        var current = state.read();
        expect(current.positivePrompt, 'latest edit, 1.2::saved style::, snow');
        expect(current.negativePrompt, 'lowres');
        expect(current.groupedMode, grouped);
        expect(current.positiveSections, hasLength(grouped ? 4 : 1));
        expect(current.positiveSections.last.fixedTagId, isNull);
        await appendDetailPromptGroup(state, 'bad hands', negative: true);
        current = state.read();
        expect(current.positivePrompt, 'latest edit, 1.2::saved style::, snow');
        expect(current.negativePrompt, 'lowres, bad hands');
        final request = container.read(promptGroupRestoreRequestProvider)!;
        expect(request.restoreNegative, isTrue);
        expect(request.restorePositive, isFalse);
        final stored = jsonDecode(
          storage.values[StorageKeys.promptGroupEditorState] as String,
        );
        expect(stored['negativePrompt'], 'lowres, bad hands');
      },
    );
  }
}
