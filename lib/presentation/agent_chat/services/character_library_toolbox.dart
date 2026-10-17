import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/agent/agent_types.dart';
import '../../../data/models/character/character_library_entry.dart';
import '../../providers/character_library_provider.dart';
import '../../providers/character_prompt_provider.dart';
import '../../providers/generation/generation_params_notifier.dart';
import '../../services/character_library_transfer.dart';
import 'character_section_state.dart';
import 'character_toolbox.dart';
import 'defined_agent_tool.dart';
import 'prompt_section_state.dart';
import 'toolbox_json.dart';

/// Tools for the character library: saved characters with their sections
/// and fixed-tag references, which the user adds to the scene and saves
/// characters back into.
class CharacterLibraryToolbox {
  CharacterLibraryToolbox(this._ref);

  final Ref _ref;

  static const int _defaultLimit = 50;
  static const int _maxLimit = 200;

  List<AgentTool> tools() => [_list(), _get(), _addToScene(), _save()];

  CharacterLibraryTransfer get _transfer => CharacterLibraryTransfer(_ref.read);

  DefinedAgentTool _list() => DefinedAgentTool(
    name: 'list_character_library',
    label: 'List Character Library',
    description:
        'List characters saved in the character library, favorites first, '
        'with their joined prompts. query matches names, prompts and '
        'categories case-insensitively. Use get_character_library_entry for '
        'one entry\'s sections and add_character_from_library to put entries '
        'into the scene.',
    parameters: toolboxObject(
      properties: {
        'query': {'type': 'string'},
        'category': {'type': 'string'},
        'favorites_only': {'type': 'boolean'},
        'limit': {'type': 'integer', 'minimum': 1, 'maximum': _maxLimit},
      },
    ),
    executeFn: (_, params) async {
      final query = (params['query'] as String?)?.trim().toLowerCase() ?? '';
      final category = (params['category'] as String?)?.trim();
      final favoritesOnly = params['favorites_only'] == true;
      final limit = ((params['limit'] as num?)?.toInt() ?? _defaultLimit).clamp(
        1,
        _maxLimit,
      );
      final library = _ref.read(characterLibraryProvider);
      final matches = [
        for (final entry in library)
          if ((!favoritesOnly || entry.favorite) &&
              (category == null ||
                  category.isEmpty ||
                  entry.category == category) &&
              (query.isEmpty || _matches(entry, query)))
            entry,
      ]..sort((a, b) => a.favorite == b.favorite ? 0 : (a.favorite ? -1 : 1));
      return agentToolJsonResult({
        'ok': true,
        'total': library.length,
        'match_count': matches.length,
        'categories': _ref.read(characterLibraryProvider.notifier).categories,
        'entries': [for (final entry in matches.take(limit)) _summary(entry)],
      });
    },
  );

  DefinedAgentTool _get() => DefinedAgentTool(
    name: 'get_character_library_entry',
    label: 'Get Character Library Entry',
    description:
        'Read one character library entry with its positive and negative '
        'sections. A section with fixed_tag_id shows that fixed tag, whose '
        'current content is resolved when the entry is added to the scene.',
    parameters: toolboxObject(
      properties: {
        'id': {'type': 'string', 'minLength': 1},
      },
      required: const ['id'],
    ),
    executeFn: (_, params) async {
      final entry = _entry(params['id'] as String);
      if (entry == null) return _notFound(params['id'] as String);
      final sections = CharacterSectionState(_ref);
      return agentToolJsonResult({
        'ok': true,
        'entry': {
          ..._summary(entry),
          for (final negative in const [false, true])
            negative
                ? 'negative_sections'
                : 'positive_sections': promptSectionsJson(
              entry.sectionsFor(negative),
              fixedTagName: (id) => sections.fixedTag(id)?.name,
            ),
        },
      });
    },
  );

  DefinedAgentTool _addToScene() => DefinedAgentTool(
    name: 'add_character_from_library',
    label: 'Add Character From Library',
    description:
        'Add library entries to the scene as new characters, in order, with '
        'their sections and fixed tags; fixed tags take their current '
        'content. Entries past the model character limit are not added. The '
        'scene characters remember their entry, so save_character_to_library '
        'can update it later.',
    parameters: toolboxObject(
      properties: {
        'ids': {
          'type': 'array',
          'minItems': 1,
          'maxItems': 6,
          'items': {'type': 'string'},
        },
      },
      required: const ['ids'],
    ),
    executeFn: (_, params) async {
      final ids = params['ids'];
      if (ids is! List || ids.isEmpty || ids.any((id) => id is! String)) {
        return agentToolError('invalid_ids', 'ids must list entry ids.');
      }
      final entries = <CharacterLibraryEntry>[];
      for (final id in ids.cast<String>()) {
        final entry = _entry(id);
        if (entry == null) return _notFound(id);
        entries.add(entry);
      }
      final notifier = _ref.read(characterPromptNotifierProvider.notifier);
      if (notifier.characterLimit == 0) {
        final model = _ref.read(generationParamsNotifierProvider).model;
        return agentToolError(
          'model_character_unsupported',
          'Model $model does not support character prompts.',
        );
      }
      final before = _ref.read(characterPromptNotifierProvider).characters;
      final added = _transfer.addToPanel(entries);
      final characters = _ref.read(characterPromptNotifierProvider).characters;
      final toolbox = CharacterToolbox(_ref);
      return agentToolJsonResult({
        'ok': true,
        'added_count': added,
        if (added < entries.length)
          'not_added_ids': [for (final entry in entries.skip(added)) entry.id],
        if (added < entries.length)
          'note':
              'The current model allows ${notifier.characterLimit} '
              'characters.',
        'characters': [
          for (var index = before.length; index < characters.length; index++)
            toolbox.characterStateJson(characters[index], order: index),
        ],
      });
    },
  );

  DefinedAgentTool _save() => DefinedAgentTool(
    name: 'save_character_to_library',
    label: 'Save Character To Library',
    description:
        'Save a scene character into the character library with its '
        'sections and fixed tags. A character that came from or was saved to '
        'an entry updates that entry unless as_new is true; otherwise a new '
        'entry is created. Only save when the user asks to keep the '
        'character.',
    parameters: toolboxObject(
      properties: {
        'character_id': {'type': 'string', 'minLength': 1},
        'as_new': {'type': 'boolean'},
      },
      required: const ['character_id'],
    ),
    executeFn: (_, params) async {
      final id = params['character_id'] as String;
      final character = _ref
          .read(characterPromptNotifierProvider)
          .findCharacterById(id);
      if (character == null) {
        return agentToolError(
          'character_not_found',
          'No character has id "$id". Call get_prompt_state for ids.',
        );
      }
      final linked = _transfer.linkedEntryId(id);
      final asNew = params['as_new'] == true || linked == null;
      final saved = _transfer.saveFromPanel(character, asNew: asNew);
      return agentToolJsonResult({
        'ok': true,
        'created': asNew,
        'entry': _summary(saved),
      });
    },
  );

  CharacterLibraryEntry? _entry(String id) =>
      _ref.read(characterLibraryProvider.notifier).byId(id);

  static bool _matches(CharacterLibraryEntry entry, String query) =>
      entry.name.toLowerCase().contains(query) ||
      entry.category.toLowerCase().contains(query) ||
      entry.prompt.toLowerCase().contains(query) ||
      entry.negativePrompt.toLowerCase().contains(query);

  static Map<String, Object?> _summary(CharacterLibraryEntry entry) => {
    'id': entry.id,
    'name': entry.name,
    'gender': entry.gender.name,
    'category': entry.category,
    'favorite': entry.favorite,
    'use_count': entry.useCount,
    'last_used_at': entry.lastUsedAt?.toIso8601String(),
    'prompt': entry.prompt,
    'negative_prompt': entry.negativePrompt,
    'section_count': entry.sectionCount,
    'fixed_tag_count': entry.fixedTagCount,
  };

  static AgentToolResult _notFound(String id) => agentToolError(
    'character_library_entry_not_found',
    'No character library entry has id "$id". Call list_character_library.',
  );
}
