import 'dart:convert';

import '../../../../../core/storage/local_storage_service.dart';
import '../../../../../data/models/character/character_prompt.dart';
import '../../../../../data/models/gallery/prompt_group_snapshot.dart';
import '../../../../../data/services/prompt_group/character_section_store.dart';
import '../../widgets/prompt_group_controller.dart';

/// Grouped editing of one character's prompts.
///
/// The character keeps the joined prompt that requests read; the sections are
/// stored beside it, per character, and are used only while they still add
/// up to that prompt. Like the main prompt's sections they stay on this
/// device: they arrange the prompt, the prompt itself is the data.
class CharacterPromptGroups {
  CharacterPromptGroups._({
    required this.characterId,
    required this.positive,
    required this.negative,
    required LocalStorageService storage,
  }) : _storage = storage;

  factory CharacterPromptGroups.load(
    LocalStorageService storage,
    CharacterPrompt character,
  ) {
    final entry = CharacterSectionStore.readAll(storage)[character.id];
    final saved = entry is Map ? entry : null;
    final positiveMatches = saved?['positivePrompt'] == character.prompt;
    final negativeMatches =
        saved?['negativePrompt'] == character.negativePrompt;
    return CharacterPromptGroups._(
      characterId: character.id,
      storage: storage,
      positive: PromptGroupCollection.fromJson(
        positiveMatches ? saved!['positiveSections'] : null,
        fallbackText: character.prompt,
      ),
      negative: PromptGroupCollection.fromJson(
        negativeMatches ? saved!['negativeSections'] : null,
        fallbackText: character.negativePrompt,
      ),
    );
  }

  final String characterId;
  final PromptGroupCollection positive;
  final PromptGroupCollection negative;
  final LocalStorageService _storage;

  PromptGroupCollection groupsFor(bool negative) =>
      negative ? this.negative : positive;

  /// Brings fixed-tag sections up to the tags' content, see
  /// [PromptGroupCollection.resolveFixedTags].
  void resolveFixedTags(String? Function(String fixedTagId) contentOf) {
    positive.resolveFixedTags(contentOf);
    negative.resolveFixedTags(contentOf);
  }

  /// Sections that no longer add up to the character's prompt, because it
  /// was changed elsewhere, become one section holding it.
  void align(CharacterPrompt character) {
    if (!positive.matchesPrompt(character.prompt)) {
      positive.replaceWith(character.prompt);
    }
    if (!negative.matchesPrompt(character.negativePrompt)) {
      negative.replaceWith(character.negativePrompt);
    }
  }

  /// After a change made elsewhere: takes the stored sections of a side
  /// when they add up to the new prompt (a writer such as the agent saved
  /// them first), and otherwise [align]s. Sections that still add up to the
  /// prompt are this editor's latest unless [preferStored], which a writer
  /// that just stored sections asks for.
  void adopt(CharacterPrompt character, {bool preferStored = false}) {
    final entry = CharacterSectionStore.readAll(_storage)[characterId];
    final saved = entry is Map ? entry : null;
    void side(
      PromptGroupCollection groups,
      String prompt, {
      required String promptKey,
      required String sectionsKey,
    }) {
      final matches = groups.matchesPrompt(prompt);
      final raw = saved?[sectionsKey];
      if ((preferStored || !matches) &&
          saved?[promptKey] == prompt &&
          raw is List) {
        final stored = [
          for (final item in raw) ?PromptGroupSectionSnapshot.fromJson(item),
        ];
        if (stored.isNotEmpty &&
            jsonEncode([for (final s in stored) s.toJson()]) !=
                jsonEncode(groups.toJson())) {
          groups.restore(stored);
        }
        return;
      }
      if (!matches) groups.replaceWith(prompt);
    }

    side(
      positive,
      character.prompt,
      promptKey: 'positivePrompt',
      sectionsKey: 'positiveSections',
    );
    side(
      negative,
      character.negativePrompt,
      promptKey: 'negativePrompt',
      sectionsKey: 'negativeSections',
    );
  }

  /// Stores the sections for [character], dropping the entries of
  /// characters that no longer exist.
  void save(CharacterPrompt character, {required Set<String> liveIds}) {
    final all = CharacterSectionStore.readAll(_storage)
      ..removeWhere((id, _) => !liveIds.contains(id));
    all[characterId] = {
      'version': 1,
      'positivePrompt': character.prompt,
      'negativePrompt': character.negativePrompt,
      'positiveSections': positive.toJson(),
      'negativeSections': negative.toJson(),
    };
    CharacterSectionStore.writeAll(_storage, all);
  }

  void dispose() {
    positive.dispose();
    negative.dispose();
  }
}
