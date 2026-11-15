import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/constants/api_constants.dart';
import 'package:nai_launcher/core/utils/prompt_semantics_utils.dart';
import 'package:nai_launcher/data/models/gallery/gallery_prompt_group.dart';
import 'package:nai_launcher/data/models/gallery/local_image_record.dart';
import 'package:nai_launcher/data/models/gallery/nai_image_metadata.dart';

void main() {
  const prompt = NaiImageMetadata(
    prompt: 'forest, {rain}',
    negativePrompt: 'blur',
    characterInfos: [CharacterPromptInfo(prompt: '1girl')],
  );

  test('exact prompts merge across metadata formats and ignore seed', () {
    final groups = GalleryPromptGroup.fromFavorites([
      _record('old', 1, prompt),
      _record(
        'new',
        3,
        prompt.copyWith(
          seed: 789,
          characterInfos: [],
          characterPrompts: ['1girl'],
        ),
      ),
      _record('different text', 2, prompt.copyWith(prompt: 'forest,{rain}')),
      _record(
        'different negative',
        2,
        prompt.copyWith(negativePrompt: 'noise'),
      ),
      _record(
        'different character',
        2,
        prompt.copyWith(
          characterInfos: [const CharacterPromptInfo(prompt: '1boy')],
        ),
      ),
      _record('no metadata', 4, null),
      _record('not favorited', 5, prompt).copyWith(isFavorite: false),
    ]);

    expect(groups, hasLength(4));
    expect(groups.first.images.map((image) => image.path), ['new', 'old']);
    expect(groups.skip(1).map((group) => group.images.length), [1, 1, 1]);
  });

  test('a new generation reorders only its existing favorite group', () {
    final older = _record('older', 1, prompt);
    final otherPrompt = prompt.copyWith(prompt: 'beach');
    final newer = _record('newer', 2, otherPrompt);
    final favorites = [older, newer];
    expect(
      GalleryPromptGroup.fromFavorites(favorites).first.favoriteCover,
      newer,
    );

    final groups = GalleryPromptGroup.fromFavorites(
      favorites,
      recentGenerations: [
        (
          id: 'latest',
          metadata: prompt.copyWith(seed: 42),
          createdAt: DateTime(2026, 11, 3),
        ),
        (id: 'previous', metadata: prompt, createdAt: DateTime(2026, 11, 2)),
        (
          id: 'other',
          metadata: prompt.copyWith(prompt: 'city'),
          createdAt: DateTime(2026, 11, 4),
        ),
      ],
    );
    expect(groups.map((group) => group.favoriteCover), [older, newer]);
    expect(groups.map((group) => group.latestGenerationId), ['latest', null]);
    expect(groups.first.images, [older]);
  });

  test(
    'history input prompts match expanded presets in saved image metadata',
    () {
      const model = ImageModels.animeDiffusionV45Full;
      const preset = 0;
      final history = prompt.copyWith(
        model: model,
        qualityToggle: true,
        ucPreset: preset,
      );
      final request = buildPromptSemanticsSnapshot(
        prompt: history.prompt,
        negativePrompt: history.negativePrompt,
        model: model,
        qualityToggle: true,
        ucPreset: preset,
      );
      final saved = _record(
        'saved',
        1,
        history.copyWith(
          prompt: request.effectivePrompt,
          negativePrompt: request.effectiveNegativePrompt,
        ),
      );
      final other = _record('other', 2, history.copyWith(prompt: 'coast'));

      final groups = GalleryPromptGroup.fromFavorites(
        [saved, other],
        recentGenerations: [
          (id: 'matching', metadata: history, createdAt: DateTime(2026, 11, 3)),
        ],
      );
      expect(groups.first.images, [saved]);
      expect(groups.first.latestGenerationId, 'matching');
    },
  );
}

LocalImageRecord _record(String path, int day, NaiImageMetadata? metadata) =>
    LocalImageRecord(
      path: path,
      size: 1,
      modifiedAt: DateTime(2026, 11, day),
      isFavorite: true,
      metadata: metadata,
    );
