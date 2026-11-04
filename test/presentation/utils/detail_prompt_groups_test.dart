import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/models/gallery/nai_image_metadata.dart';
import 'package:nai_launcher/data/models/gallery/prompt_group_snapshot.dart';
import 'package:nai_launcher/presentation/utils/detail_prompt_groups.dart';

void main() {
  test(
    'fixed names come from the recorded side and prefix or suffix position',
    () {
      final metadata = NaiImageMetadata(
        prompt: 'style, cat, style',
        fixedPrefixTags: const ['style'],
        fixedSuffixTags: const ['style'],
        promptGroupData: const PromptGroupSnapshot(
          groupedMode: true,
          positiveSections: [PromptGroupSectionSnapshot(id: 'a', text: 'cat')],
          negativeSections: [],
        ).toJson(),
        fixedTagUsageData: const {
          'entries': [
            {
              'name': 'Negative style',
              'content': 'style',
              'prompt_type': 'negative',
              'position': 'prefix',
            },
            {
              'name': 'Prefix style',
              'content': 'style',
              'prompt_type': 'positive',
              'position': 'prefix',
            },
            {
              'name': 'Suffix style',
              'content': 'style',
              'prompt_type': 'positive',
              'position': 'suffix',
            },
          ],
        },
      );
      final groups = detailPromptGroups(metadata, negative: false)!;
      expect(groups.first.name, 'Prefix style');
      expect(groups.last.name, 'Suffix style');
      expect(groups.map((group) => group.text), ['style', 'cat', 'style']);
    },
  );

  test(
    'only used sections appear, with fixed and quality cards in image order',
    () {
      const snapshot = PromptGroupSnapshot(
        groupedMode: true,
        positiveSections: [
          PromptGroupSectionSnapshot(id: 'a', text: 'cat, solo'),
          PromptGroupSectionSnapshot(id: 'off', text: 'rain', enabled: false),
          PromptGroupSectionSnapshot(
            id: 'fixed',
            text: 'style',
            fixedTagId: 'f',
          ),
          PromptGroupSectionSnapshot(id: 'empty', text: ''),
          PromptGroupSectionSnapshot(id: 'b', text: 'smile'),
        ],
        negativeSections: [PromptGroupSectionSnapshot(id: 'n', text: 'lowres')],
      );
      final metadata = NaiImageMetadata(
        prompt: 'style, cat, solo, smile, best quality',
        negativePrompt: 'lowres',
        fixedPrefixTags: const ['style'],
        qualityTags: const ['best quality'],
        promptGroupData: snapshot.toJson(),
        characterInfos: const [CharacterPromptInfo(prompt: 'rabbit girl')],
      );
      final groups = detailPromptGroups(metadata, negative: false)!;
      expect(groups.map((g) => g.text), [
        'style',
        'cat, solo',
        'smile',
        'best quality',
        'rabbit girl',
      ]);
      expect(groups.map((g) => g.offset), [0, 1, 3, 4, 5]);
      expect(groups.map((g) => g.kind), [
        DetailPromptGroupKind.fixed,
        DetailPromptGroupKind.section,
        DetailPromptGroupKind.section,
        DetailPromptGroupKind.quality,
        DetailPromptGroupKind.character,
      ]);
      expect(groups[2].number, 5);
      expect(
        detailPromptGroups(metadata, negative: true)!.single.text,
        'lowres',
      );
    },
  );

  test(
    'disabled fragments and stale sections do not appear as image cards',
    () {
      final metadata = NaiImageMetadata(
        prompt: '1.2::cat::, sunshine',
        promptGroupData: const PromptGroupSnapshot(
          groupedMode: true,
          positiveSections: [
            PromptGroupSectionSnapshot(
              id: 'a',
              text: '1.2::cat::, /*disabled:dog*/',
            ),
            PromptGroupSectionSnapshot(id: 'stale', text: 'old tag'),
          ],
          negativeSections: [],
        ).toJson(),
      );
      final groups = detailPromptGroups(metadata, negative: false)!;
      expect(groups.map((g) => g.text), ['1.2::cat::', 'sunshine']);
      expect(groups.last.kind, DetailPromptGroupKind.remaining);
    },
  );

  test('missing or single-mode records keep the flat prompt presentation', () {
    expect(
      detailPromptGroups(
        const NaiImageMetadata(prompt: 'cat'),
        negative: false,
      ),
      isNull,
    );
    final metadata = NaiImageMetadata(
      prompt: 'cat',
      promptGroupData: const PromptGroupSnapshot(
        groupedMode: false,
        positiveSections: [PromptGroupSectionSnapshot(id: 'a', text: 'cat')],
        negativeSections: [],
      ).toJson(),
    );
    expect(detailPromptGroups(metadata, negative: false), isNull);
  });
}
