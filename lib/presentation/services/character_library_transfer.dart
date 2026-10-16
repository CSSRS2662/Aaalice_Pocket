import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../core/constants/storage_keys.dart';
import '../../core/storage/local_storage_service.dart';
import '../../data/models/character/character_library_entry.dart';
import '../../data/models/character/character_prompt.dart';
import '../../data/models/gallery/prompt_group_snapshot.dart';
import '../../data/services/prompt_group/character_section_store.dart';
import '../providers/character_library_provider.dart';
import '../providers/character_prompt_provider.dart';
import '../providers/fixed_tags_provider.dart';
import '../utils/prompt_preset_import_utils.dart';

/// Moves characters between the character library and the character bar.
///
/// A character added from the library is a copy: editing it in the bar
/// leaves the library alone until it is saved back, either over the entry
/// it came from or as a new one. The bar remembers which entry each of its
/// characters came from, and what it looked like then, on this device only.
class CharacterLibraryTransfer {
  const CharacterLibraryTransfer(this._read);

  final ProviderReader _read;

  LocalStorageService get _storage => _read(localStorageServiceProvider);

  String? _fixedTagContent(String id) {
    for (final entry in _read(fixedTagsNotifierProvider).entries) {
      if (entry.id == id) return entry.weightedContent;
    }
    return null;
  }

  /// Adds [entries] to the bar in order and returns how many fit under the
  /// model's character limit.
  int addToPanel(List<CharacterLibraryEntry> entries) {
    final notifier = _read(characterPromptNotifierProvider.notifier);
    final added = <String>[];
    for (final source in entries) {
      final entry = source.resolveFixedTags(_fixedTagContent);
      final before = _read(characterPromptNotifierProvider).characters;
      notifier.addCharacter(
        entry.gender,
        name: entry.name,
        prompt: entry.prompt,
        negativePrompt: entry.negativePrompt,
      );
      final after = _read(characterPromptNotifierProvider).characters;
      if (after.length == before.length) break;
      final character = after.last;
      CharacterSectionStore.restore(_storage, {
        character.id: {
          'version': 1,
          'positivePrompt': character.prompt,
          'negativePrompt': character.negativePrompt,
          'positiveSections': [
            for (final section in entry.positiveSections) section.toJson(),
          ],
          'negativeSections': [
            for (final section in entry.negativeSections) section.toJson(),
          ],
        },
      });
      _writeLink(character, entry.id);
      added.add(source.id);
    }
    _read(characterLibraryProvider.notifier).recordUse(added);
    return added.length;
  }

  /// A library entry holding [character]: its saved sections while they
  /// still add up to its prompts, otherwise each prompt as one section.
  CharacterLibraryEntry entryFromPanel(CharacterPrompt character) {
    final saved = CharacterSectionStore.readAll(_storage)[character.id];
    List<PromptGroupSectionSnapshot> sections({
      required String promptKey,
      required String sectionsKey,
      required String prompt,
    }) {
      if (saved is Map && saved[promptKey] == prompt) {
        final list = saved[sectionsKey];
        if (list is List) {
          final restored = [
            for (final item in list.take(CharacterLibraryEntry.maxSections))
              ?PromptGroupSectionSnapshot.fromJson(item),
          ];
          if (restored.isNotEmpty) return restored;
        }
      }
      return [
        if (prompt.trim().isNotEmpty)
          PromptGroupSectionSnapshot(
            id: '${character.id}-$promptKey',
            text: prompt,
          ),
      ];
    }

    return CharacterLibraryEntry.create(
      name: character.name,
      gender: character.effectiveGender,
      positiveSections: sections(
        promptKey: 'positivePrompt',
        sectionsKey: 'positiveSections',
        prompt: character.prompt,
      ),
      negativeSections: sections(
        promptKey: 'negativePrompt',
        sectionsKey: 'negativeSections',
        prompt: character.negativePrompt,
      ),
    );
  }

  /// Saves [character] into the library, over the entry it came from unless
  /// [asNew] or that entry is gone, and returns the saved entry.
  CharacterLibraryEntry saveFromPanel(
    CharacterPrompt character, {
    required bool asNew,
  }) {
    final library = _read(characterLibraryProvider.notifier);
    final fresh = entryFromPanel(character);
    final linkedId = linkedEntryId(character.id);
    final base = asNew || linkedId == null ? null : library.byId(linkedId);
    final CharacterLibraryEntry saved;
    if (base == null) {
      saved = fresh;
      library.add(saved);
    } else {
      saved = base.copyWith(
        name: fresh.name,
        gender: fresh.gender,
        positiveSections: fresh.positiveSections,
        negativeSections: fresh.negativeSections,
      );
      library.update(saved);
    }
    _writeLink(character, saved.id);
    return saved;
  }

  /// The library entry [characterId] was added from or saved to, while that
  /// entry still exists.
  String? linkedEntryId(String characterId) {
    final link = _links()[characterId];
    final id = link is Map ? link['entryId'] : null;
    if (id is! String) return null;
    return _read(characterLibraryProvider.notifier).byId(id) == null
        ? null
        : id;
  }

  /// Whether [character] changed since it last matched its library entry.
  bool hasUnsavedChanges(CharacterPrompt character) {
    final link = _links()[character.id];
    if (link is! Map || linkedEntryId(character.id) == null) return false;
    return link['fingerprint'] != _fingerprint(character);
  }

  String _fingerprint(CharacterPrompt character) {
    final saved = CharacterSectionStore.readAll(_storage)[character.id];
    final matches =
        saved is Map &&
        saved['positivePrompt'] == character.prompt &&
        saved['negativePrompt'] == character.negativePrompt;
    final data = jsonEncode({
      'name': character.name,
      'gender': character.effectiveGender.name,
      'prompt': character.prompt,
      'negativePrompt': character.negativePrompt,
      if (matches) ...{
        'positiveSections': saved['positiveSections'],
        'negativeSections': saved['negativeSections'],
      },
    });
    return sha256.convert(utf8.encode(data)).toString();
  }

  Map<String, Object?> _links() {
    final raw = _storage.getSetting<String>(StorageKeys.characterLibraryLinks);
    if (raw == null || raw.isEmpty) return {};
    try {
      final value = jsonDecode(raw);
      return value is Map ? Map<String, Object?>.from(value) : {};
    } on FormatException {
      return {};
    }
  }

  void _writeLink(CharacterPrompt character, String entryId) {
    final live = {
      for (final item in _read(characterPromptNotifierProvider).characters)
        item.id,
    };
    final links = _links()..removeWhere((id, _) => !live.contains(id));
    links[character.id] = {
      'entryId': entryId,
      'fingerprint': _fingerprint(character),
    };
    _storage.setSetting(StorageKeys.characterLibraryLinks, jsonEncode(links));
  }
}
