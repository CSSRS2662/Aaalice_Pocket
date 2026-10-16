import '../../models/character/character_prompt.dart';
import 'character_section_store.dart';

/// Fixed tags placed among a character's sections.
///
/// A fixed-tag section stores the tag's id and the content it last resolved
/// to. The character's prompt holds that content like any section's text, so
/// requests read it as usual; [resolve] brings it up to date after the tag
/// changes. A tag a character includes is "claimed": for that generation the
/// main prompt leaves it out, unless the section keeps it in both places.
abstract final class CharacterFixedTags {
  /// Ids of the fixed tags the included characters of [config] claim, read
  /// from the section entries in [entries].
  static Set<String> claimed(
    CharacterPromptConfig config,
    Map<String, Object?> entries,
  ) {
    final ids = <String>{};
    for (final character in config.characters) {
      if (!character.enabled) continue;
      final entry = entries[character.id];
      if (entry is! Map) continue;
      for (final side in _Side.values) {
        if (!side.matches(entry, character)) continue;
        for (final section in side.sections(entry)) {
          final id = section['fixedTagId'];
          if (id is String &&
              id.isNotEmpty &&
              section['enabled'] != false &&
              section['keepInMain'] != true) {
            ids.add(id);
          }
        }
      }
    }
    return ids;
  }

  /// Rewrites the fixed-tag sections of [entry], the saved sections of
  /// [character], with [contentOf]; null keeps a section's last content.
  /// Returns the character and entry with the recombined prompts, or null
  /// when nothing changed or the entry no longer adds up to the character.
  static ({CharacterPrompt character, Map<String, Object?> entry})? resolve(
    CharacterPrompt character,
    Map<Object?, Object?> entry,
    String? Function(String fixedTagId) contentOf,
  ) {
    var next = character;
    final nextEntry = Map<String, Object?>.from(
      entry.map((key, value) => MapEntry(key.toString(), value)),
    );
    var changed = false;
    for (final side in _Side.values) {
      if (!side.matches(entry, character)) continue;
      final sections = [
        for (final section in side.sections(entry))
          Map<String, Object?>.from(
            section.map((key, value) => MapEntry(key.toString(), value)),
          ),
      ];
      var sideChanged = false;
      for (final section in sections) {
        final id = section['fixedTagId'];
        if (id is! String || id.isEmpty) continue;
        final content = contentOf(id);
        if (content == null || content == section['text']) continue;
        section['text'] = content;
        sideChanged = true;
      }
      if (!sideChanged) continue;
      changed = true;
      final prompt = joinSectionTexts(sections);
      nextEntry[side.sectionsKey] = sections;
      nextEntry[side.promptKey] = prompt;
      next = side.withPrompt(next, prompt);
    }
    return changed ? (character: next, entry: nextEntry) : null;
  }

  /// [resolve] for every character of [config] with saved sections; writes
  /// the changed entries back into [entries] and returns the new config, or
  /// null when nothing changed.
  static CharacterPromptConfig? resolveAll(
    CharacterPromptConfig config,
    Map<String, Object?> entries,
    String? Function(String fixedTagId) contentOf,
  ) {
    var changed = false;
    final characters = <CharacterPrompt>[];
    for (final character in config.characters) {
      final entry = entries[character.id];
      final result = entry is Map ? resolve(character, entry, contentOf) : null;
      if (result == null) {
        characters.add(character);
        continue;
      }
      changed = true;
      entries[character.id] = result.entry;
      characters.add(result.character);
    }
    return changed ? config.copyWith(characters: characters) : null;
  }

  /// The included texts of saved [sections] joined into a prompt, exactly
  /// as the section editor joins them.
  static String joinSectionTexts(Iterable<Map<Object?, Object?>> sections) =>
      CharacterSectionStore.join([
        for (final section in sections)
          if (section['enabled'] != false)
            if (section['text'] case final String text) text,
      ]);
}

enum _Side {
  positive('positivePrompt', 'positiveSections'),
  negative('negativePrompt', 'negativeSections');

  const _Side(this.promptKey, this.sectionsKey);

  final String promptKey;
  final String sectionsKey;

  String promptOf(CharacterPrompt character) =>
      this == positive ? character.prompt : character.negativePrompt;

  CharacterPrompt withPrompt(CharacterPrompt character, String prompt) =>
      this == positive
      ? character.copyWith(prompt: prompt)
      : character.copyWith(negativePrompt: prompt);

  /// Sections are used only while they still add up to the prompt.
  bool matches(Map<Object?, Object?> entry, CharacterPrompt character) =>
      entry[promptKey] == promptOf(character);

  Iterable<Map<Object?, Object?>> sections(Map<Object?, Object?> entry) =>
      switch (entry[sectionsKey]) {
        final List<Object?> list => list.whereType<Map<Object?, Object?>>(),
        _ => const [],
      };
}
