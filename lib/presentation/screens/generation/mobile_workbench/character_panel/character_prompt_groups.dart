import 'dart:async';
import 'dart:convert';

import '../../../../../core/constants/storage_keys.dart';
import '../../../../../core/storage/local_storage_service.dart';
import '../../../../../data/models/character/character_prompt.dart';
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
    required this.grouped,
    required LocalStorageService storage,
  }) : _storage = storage;

  factory CharacterPromptGroups.load(
    LocalStorageService storage,
    CharacterPrompt character,
  ) {
    final entry = _readAll(storage)[character.id];
    final saved = entry is Map ? entry : null;
    final positiveMatches = saved?['positivePrompt'] == character.prompt;
    final negativeMatches =
        saved?['negativePrompt'] == character.negativePrompt;
    return CharacterPromptGroups._(
      characterId: character.id,
      storage: storage,
      grouped: saved?['mode'] == PromptEditorMode.grouped.name,
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
  bool grouped;

  PromptGroupCollection groupsFor(bool negative) =>
      negative ? this.negative : positive;

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

  /// Stores the sections for [character], dropping the entries of
  /// characters that no longer exist.
  void save(CharacterPrompt character, {required Set<String> liveIds}) {
    final all = _readAll(_storage)
      ..removeWhere((id, _) => !liveIds.contains(id));
    all[characterId] = {
      'version': 1,
      'mode': grouped
          ? PromptEditorMode.grouped.name
          : PromptEditorMode.single.name,
      'positivePrompt': character.prompt,
      'negativePrompt': character.negativePrompt,
      'positiveSections': positive.toJson(),
      'negativeSections': negative.toJson(),
    };
    unawaited(
      _storage.setSetting(
        StorageKeys.characterPromptGroupState,
        jsonEncode(all),
      ),
    );
  }

  void dispose() {
    positive.dispose();
    negative.dispose();
  }

  static Map<String, Object?> _readAll(LocalStorageService storage) {
    final raw = storage.getSetting<String>(
      StorageKeys.characterPromptGroupState,
    );
    if (raw == null || raw.isEmpty) return {};
    try {
      final value = jsonDecode(raw);
      return value is Map ? Map<String, Object?>.from(value) : {};
    } on FormatException {
      return {};
    }
  }
}
