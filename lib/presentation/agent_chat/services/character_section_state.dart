import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/local_storage_service.dart';
import '../../../data/models/character/character_prompt.dart';
import '../../../data/models/fixed_tag/fixed_tag_entry.dart';
import '../../../data/models/fixed_tag/fixed_tag_prompt_type.dart';
import '../../../data/models/gallery/prompt_group_snapshot.dart';
import '../../../data/services/prompt_group/character_section_store.dart';
import '../../providers/character_prompt_provider.dart';
import '../../providers/character_workspace_provider.dart';
import '../../providers/fixed_tags_provider.dart';
import 'prompt_section_state.dart';

/// The sections of characters' prompts for writers other than the character
/// editor, such as the agent.
///
/// A character keeps the joined prompt that requests read. Its sections are
/// stored beside it, per character, and count only while they still add up
/// to that prompt. Writes store the sections before the joined prompt, so an
/// open editor finds them matching and shows them.
class CharacterSectionState {
  CharacterSectionState(this._ref);

  final Ref _ref;

  /// Whether the character editors show sections (one switch for all).
  bool get groupedMode => _ref.read(characterPromptsGroupedProvider);

  void enableGroupedMode() =>
      _ref.read(characterPromptsGroupedProvider.notifier).set(true);

  LocalStorageService get _storage => _ref.read(localStorageServiceProvider);

  /// The saved sections of one side of [character]; a side whose sections no
  /// longer add up to its prompt reads as one section holding that prompt.
  List<PromptGroupSectionSnapshot> read(
    CharacterPrompt character, {
    required bool negative,
  }) =>
      stored(character, negative: negative) ??
      [
        PromptGroupSectionSnapshot(
          id: '${character.id}-${negative ? 'n' : 'p'}-1',
          text: negative ? character.negativePrompt : character.prompt,
        ),
      ];

  /// The saved sections of one side while they add up to its prompt.
  List<PromptGroupSectionSnapshot>? stored(
    CharacterPrompt character, {
    required bool negative,
  }) {
    final entry = CharacterSectionStore.readAll(_storage)[character.id];
    final prompt = negative ? character.negativePrompt : character.prompt;
    if (entry is! Map ||
        entry[negative ? 'negativePrompt' : 'positivePrompt'] != prompt) {
      return null;
    }
    final raw = entry[negative ? 'negativeSections' : 'positiveSections'];
    if (raw is! List) return null;
    final sections = [
      for (final item in raw) ?PromptGroupSectionSnapshot.fromJson(item),
    ];
    return sections.isEmpty
        ? null
        : PromptSectionEdits.withIds(
            sections,
            '${character.id}-${negative ? 'n' : 'p'}',
          );
  }

  /// Stores [positive] and/or [negative] as [character]'s sections, writes
  /// their joined text as its prompts and returns the updated character.
  CharacterPrompt write(
    CharacterPrompt character, {
    List<PromptGroupSectionSnapshot>? positive,
    List<PromptGroupSectionSnapshot>? negative,
  }) {
    final updated = storeSections(
      character,
      positive: positive,
      negative: negative,
    );
    _ref
        .read(characterPromptNotifierProvider.notifier)
        .updateCharacter(updated);
    return updated;
  }

  /// The store half of [write]: saves the sections and returns the
  /// character with the joined prompts, for callers that write the
  /// character themselves (afterwards, so an open editor adopts them).
  CharacterPrompt storeSections(
    CharacterPrompt character, {
    List<PromptGroupSectionSnapshot>? positive,
    List<PromptGroupSectionSnapshot>? negative,
  }) {
    final positiveSections = positive ?? read(character, negative: false);
    final negativeSections = negative ?? read(character, negative: true);
    final updated = character.copyWith(
      prompt: joinEnabled(positiveSections),
      negativePrompt: joinEnabled(negativeSections),
    );
    final all = CharacterSectionStore.readAll(_storage);
    all[character.id] = {
      'version': 1,
      'positivePrompt': updated.prompt,
      'negativePrompt': updated.negativePrompt,
      'positiveSections': [
        for (final section in positiveSections) section.toJson(),
      ],
      'negativeSections': [
        for (final section in negativeSections) section.toJson(),
      ],
    };
    CharacterSectionStore.writeAll(_storage, all);
    _ref.read(characterSectionsRevisionProvider.notifier).state++;
    return updated;
  }

  /// The new sections of one side asked for by add_character /
  /// update_character arguments [args], or null to leave the side to the
  /// plain prompt fields: a section list replaces every section; in grouped
  /// mode a plain prompt replaces the enabled text sections [current] has
  /// saved and keeps its disabled and fixed-tag sections.
  List<PromptGroupSectionSnapshot>? sectionsFromArgs(
    Map<String, dynamic> args, {
    required bool negative,
    CharacterPrompt? current,
  }) {
    final listKey = negative ? 'negative_prompt_sections' : 'prompt_sections';
    final textKey = negative ? 'negative_prompt' : 'prompt';
    if (args.containsKey(listKey)) {
      if (args.containsKey(textKey)) {
        throw PromptSectionEditException(
          'invalid_sections',
          'Give $textKey or $listKey, not both.',
        );
      }
      return parseSections(args[listKey], negative: negative, field: listKey);
    }
    if (current == null || !groupedMode || !args.containsKey(textKey)) {
      return null;
    }
    // Without saved sections the prompt is one section anyway.
    final saved = stored(current, negative: negative);
    if (saved == null) return null;
    return PromptSectionEdits.replaceEnabled(
      saved,
      (args[textKey] as String?)?.trim() ?? '',
    );
  }

  /// [character]'s sections as the agent sees them.
  Map<String, Object?> sectionsJson(CharacterPrompt character) => {
    for (final negative in const [false, true])
      negative ? 'negative_sections' : 'positive_sections': promptSectionsJson(
        read(character, negative: negative),
        fixedTagName: (id) => fixedTag(id)?.name,
      ),
  };

  /// Sections given as [raw] for the [negative] side: each item is text, or
  /// an object with text or fixed_tag_id and optional enabled and
  /// keep_in_main. Throws [PromptSectionEditException].
  List<PromptGroupSectionSnapshot> parseSections(
    Object? raw, {
    required bool negative,
    required String field,
  }) {
    PromptSectionEditException invalid(String message) =>
        PromptSectionEditException('invalid_sections', '$field: $message');
    if (raw is! List || raw.isEmpty) {
      throw invalid('must be a non-empty array.');
    }
    if (raw.length > PromptSectionEdits.maxSections) {
      throw invalid('at most ${PromptSectionEdits.maxSections} sections.');
    }
    final sections = <PromptGroupSectionSnapshot>[];
    for (final (index, item) in raw.indexed) {
      final position = index + 1;
      if (item is String) {
        if (item.trim().isEmpty) throw invalid('item $position is empty.');
        sections.add(
          PromptGroupSectionSnapshot(
            id: PromptSectionEdits.newId(),
            text: item.trim(),
          ),
        );
        continue;
      }
      if (item is! Map) {
        throw invalid('item $position must be a string or an object.');
      }
      final text = item['text'];
      final fixedTagId = item['fixed_tag_id'];
      final enabled = item['enabled'] ?? true;
      final keepInMain = item['keep_in_main'];
      if (enabled is! bool || (keepInMain != null && keepInMain is! bool)) {
        throw invalid('item $position: enabled and keep_in_main are booleans.');
      }
      if (fixedTagId != null) {
        if (fixedTagId is! String || fixedTagId.isEmpty || text != null) {
          throw invalid('item $position: give text or fixed_tag_id.');
        }
        final section = fixedTagSection(
          fixedTagId,
          negative: negative,
          enabled: enabled,
          keepInMain: keepInMain == true,
        );
        if (sections.any((s) => s.fixedTagId == section.fixedTagId)) {
          throw invalid('item $position repeats fixed tag $fixedTagId.');
        }
        sections.add(section);
        continue;
      }
      if (text is! String || text.trim().isEmpty || keepInMain != null) {
        throw invalid('item $position needs text (keep_in_main needs a tag).');
      }
      sections.add(
        PromptGroupSectionSnapshot(
          id: PromptSectionEdits.newId(),
          text: text.trim(),
          enabled: enabled,
        ),
      );
    }
    return sections;
  }

  /// The prompt [sections] send: the enabled ones joined like the editor.
  static String joinEnabled(Iterable<PromptGroupSectionSnapshot> sections) =>
      CharacterSectionStore.join([
        for (final section in sections)
          if (section.enabled) section.text,
      ]);

  /// A new section showing fixed tag [fixedTagId] on the [negative] side.
  PromptGroupSectionSnapshot fixedTagSection(
    String fixedTagId, {
    required bool negative,
    bool enabled = true,
    bool keepInMain = false,
  }) {
    final entry = fixedTag(fixedTagId);
    if (entry == null) {
      throw PromptSectionEditException(
        'fixed_tag_not_found',
        'No fixed tag has id "$fixedTagId". Call list_fixed_tags for ids.',
      );
    }
    final side = negative
        ? FixedTagPromptType.negative
        : FixedTagPromptType.positive;
    if (entry.promptType != side) {
      throw PromptSectionEditException(
        'fixed_tag_side',
        'Fixed tag "${entry.name}" is a ${entry.promptType.name} tag; add it '
            'to the ${entry.promptType.name} prompt.',
      );
    }
    return PromptGroupSectionSnapshot(
      id: PromptSectionEdits.newId(),
      text: entry.weightedContent,
      enabled: enabled,
      fixedTagId: entry.id,
      keepInMain: keepInMain,
    );
  }

  FixedTagEntry? fixedTag(String id) {
    for (final entry in _ref.read(fixedTagsNotifierProvider).entries) {
      if (entry.id == id) return entry;
    }
    return null;
  }
}
