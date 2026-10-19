import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/agent/agent_types.dart';
import '../../../data/models/character/character_prompt.dart';
import '../../../data/models/gallery/prompt_group_snapshot.dart';
import '../../providers/character_prompt_provider.dart';
import '../../providers/generation/generation_params_notifier.dart';
import '../../services/character_library_transfer.dart';
import 'character_section_state.dart';
import 'defined_agent_tool.dart';
import 'prompt_section_state.dart';

/// Character tools: add, edit, place, order and remove the characters of the
/// scene. Changes go through the character provider and show in the UI at
/// once; characters edited in grouped mode keep their sections.
class CharacterToolbox {
  CharacterToolbox(this._ref);

  final Ref _ref;

  List<AgentTool> tools() => [
    DefinedAgentTool(
      name: 'update_character',
      label: 'Update Character',
      description:
          'Update one character matched by stable id or case-insensitive '
          'name. Only provided fields change, so omitting position fields '
          'preserves an existing explicit manual position. Keep ai_choice '
          'unless the user explicitly requests manual placement or concrete '
          'coordinates. ai_choice preserves any saved custom point for later '
          'restoration. custom accepts both position_x and position_y, or '
          'reuses an existing saved point; it never invents a new point. x '
          'is left-to-right and y is top-to-bottom, finite 0..1 values. '
          '$_characterSectionsNote',
      parameters: const {
        'type': 'object',
        'properties': {
          'id': {'type': 'string', 'description': 'Stable character ID.'},
          'name': {
            'type': 'string',
            'description': 'Existing character name to match.',
          },
          'new_name': {'type': 'string', 'description': 'New display name.'},
          'gender': {
            'type': 'string',
            'enum': ['female', 'male', 'other'],
            'description': _genderNote,
          },
          'prompt': {'type': 'string'},
          'negative_prompt': {'type': 'string'},
          'prompt_sections': _characterSectionsSchema,
          'negative_prompt_sections': _characterSectionsSchema,
          'enabled': {'type': 'boolean'},
          'position_mode': {
            'type': 'string',
            'enum': ['ai_choice', 'custom'],
            'description':
                'Omit to preserve the current mode. Use custom only when '
                'the user explicitly requests manual placement.',
          },
          'position_x': {
            'type': 'number',
            'minimum': 0,
            'maximum': 1,
            'description': 'Horizontal center: 0 left, 1 right.',
          },
          'position_y': {
            'type': 'number',
            'minimum': 0,
            'maximum': 1,
            'description': 'Vertical center: 0 top, 1 bottom.',
          },
        },
        'required': <String>[],
      },
      executeFn: (_, params) => _updateCharacter(params),
    ),
    DefinedAgentTool(
      name: 'add_character',
      label: 'Add Character',
      description:
          'Add one ordered character using the current model limit. NovelAI '
          'AI placement is the default; do not estimate coordinates. Use '
          'custom only when the user explicitly requests manual placement, '
          'with both axes (x left-to-right, y top-to-bottom, finite 0..1). '
          'ai_choice conflicts with coordinates. $_characterSectionsNote',
      parameters: const {
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
          'gender': {
            'type': 'string',
            'enum': ['female', 'male', 'other'],
            'description': _genderNote,
          },
          'prompt': {'type': 'string'},
          'negative_prompt': {'type': 'string'},
          'prompt_sections': _characterSectionsSchema,
          'negative_prompt_sections': _characterSectionsSchema,
          'enabled': {'type': 'boolean'},
          'position_mode': {
            'type': 'string',
            'enum': ['ai_choice', 'custom'],
            'description':
                'Default ai_choice. Use custom only for an explicit user '
                'request and provide both coordinates.',
          },
          'position_x': {'type': 'number', 'minimum': 0, 'maximum': 1},
          'position_y': {'type': 'number', 'minimum': 0, 'maximum': 1},
        },
        'required': ['name'],
      },
      executeFn: (_, params) => _addCharacter(params),
    ),
    DefinedAgentTool(
      name: 'set_character_layout_mode',
      label: 'Set Character Layout Mode',
      description:
          'Switch the whole scene between NovelAI AI placement and custom '
          'continuous coordinates. Keep AI placement by default. Call custom '
          'only when the user explicitly requests manual placement; it '
          'assigns stable defaults only where needed. Switching to AI '
          'preserves every saved custom point for later restoration.',
      parameters: const {
        'type': 'object',
        'properties': {
          'mode': {
            'type': 'string',
            'enum': ['ai_choice', 'custom'],
          },
        },
        'required': ['mode'],
      },
      executeFn: (_, params) => _setCharacterLayoutMode(params),
    ),
    DefinedAgentTool(
      name: 'reorder_characters',
      label: 'Reorder Characters',
      description:
          'Set the exact character order using stable IDs. ordered_ids must '
          'contain every current character ID exactly once.',
      parameters: const {
        'type': 'object',
        'properties': {
          'ordered_ids': {
            'type': 'array',
            'items': {'type': 'string'},
          },
        },
        'required': ['ordered_ids'],
      },
      executeFn: (_, params) => _reorderCharacters(params),
    ),
    DefinedAgentTool(
      name: 'remove_character',
      label: 'Remove Character',
      description: 'Remove a character prompt entry matched by id or name.',
      parameters: const {
        'type': 'object',
        'properties': {
          'id': {'type': 'string'},
          'name': {'type': 'string'},
        },
        'required': <String>[],
      },
      executeFn: (_, params) => _removeCharacter(params),
    ),
    DefinedAgentTool(
      name: 'clear_characters',
      label: 'Clear Characters',
      description: 'Remove every character from the current scene.',
      parameters: const {
        'type': 'object',
        'properties': <String, dynamic>{},
        'required': <String>[],
      },
      executeFn: (_, params) => _clearCharacters(),
    ),
  ];

  CharacterPrompt? _findCharacter({String? id, String? name}) {
    final characters = _ref.read(characterPromptNotifierProvider).characters;
    final normalizedId = id?.trim() ?? '';
    final normalizedName = name?.trim().toLowerCase() ?? '';

    if (normalizedId.isNotEmpty) {
      final byId = characters.where((c) => c.id == normalizedId).firstOrNull;
      if (byId == null) return null;
      if (normalizedName.isNotEmpty &&
          byId.name.trim().toLowerCase() != normalizedName) {
        throw const _PromptToolValidationException(
          'invalid_character_selector',
          'The supplied character id and name identify different characters.',
        );
      }
      return byId;
    }

    if (normalizedName.isNotEmpty) {
      final byName = characters
          .where((c) => c.name.trim().toLowerCase() == normalizedName)
          .toList();
      if (byName.length > 1) {
        throw const _PromptToolValidationException(
          'invalid_character_selector',
          'Character name is ambiguous. Call get_prompt_state and use a stable id.',
        );
      }
      return byName.firstOrNull;
    }
    return null;
  }

  Future<AgentToolResult> _updateCharacter(Map<String, dynamic> args) async {
    late final CharacterPrompt? target;
    late final _CharacterPositionChange positionChange;
    try {
      _validateCharacterStringFields(args);
      target = _findCharacter(
        id: args['id'] as String?,
        name: args['name'] as String?,
      );
      positionChange = _parsePositionChange(args);
    } on _PromptToolValidationException catch (error) {
      return agentToolError(error.code, error.message);
    }
    if (target == null) {
      return agentToolError(
        'character_not_found',
        'Character not found. Call get_prompt_state for stable IDs.',
      );
    }
    final sectionState = CharacterSectionState(_ref);
    final List<PromptGroupSectionSnapshot>? positiveSections;
    final List<PromptGroupSectionSnapshot>? negativeSections;
    try {
      positiveSections = sectionState.sectionsFromArgs(
        args,
        negative: false,
        current: target,
      );
      negativeSections = sectionState.sectionsFromArgs(
        args,
        negative: true,
        current: target,
      );
    } on PromptSectionEditException catch (error) {
      return agentToolError(error.code, error.message);
    }
    if (positionChange.mode == CharacterPositionMode.custom &&
        positionChange.x == null &&
        target.customPosition == null) {
      return agentToolError(
        'missing_character_coordinates',
        'position_mode custom requires both coordinates when the character '
            'has no saved manual position.',
      );
    }

    final requestedPositionMode = positionChange.mode;
    if (requestedPositionMode != null) {
      _ref
          .read(characterPromptNotifierProvider.notifier)
          .setGlobalAiChoice(
            requestedPositionMode == CharacterPositionMode.aiChoice,
          );
    }

    var updated = target;
    final newName = (args['new_name'] as String?)?.trim();
    if (newName != null && newName.isNotEmpty) {
      updated = updated.copyWith(name: newName);
    }
    final gender = _parseGender(args['gender']);
    if (gender != null) updated = updated.copyWith(gender: gender);
    // The first tag sets the gender the panel shows and NovelAI reads. A new
    // gender rewrites it; a rewritten prompt keeps the current gender.
    final promptChanged =
        args.containsKey('prompt') || positiveSections != null;
    final currentGender = target.effectiveGender;
    final leadGender =
        gender ??
        (promptChanged && currentGender != CharacterGender.other
            ? currentGender
            : null);
    var positive = positiveSections;
    if (args.containsKey('prompt') && positive == null) {
      final prompt = (args['prompt'] as String?) ?? '';
      updated = updated.copyWith(
        prompt: leadGender == null
            ? prompt
            : CharacterPrompt.leadingWithGender(prompt, leadGender),
      );
    } else if (leadGender != null && positive != null) {
      positive = _sectionsWithGender(positive, leadGender);
    } else if (gender != null) {
      final stored = sectionState.stored(target, negative: false);
      if (stored != null) {
        positive = _sectionsWithGender(stored, gender);
      } else {
        updated = updated.copyWith(
          prompt: CharacterPrompt.leadingWithGender(updated.prompt, gender),
        );
      }
    }
    if (args.containsKey('negative_prompt') && negativeSections == null) {
      updated = updated.copyWith(
        negativePrompt: (args['negative_prompt'] as String?) ?? '',
      );
    }
    if (args.containsKey('enabled')) {
      final enabled = args['enabled'];
      if (enabled is! bool) {
        return agentToolError(
          'invalid_character_enabled',
          'enabled must be a boolean.',
        );
      }
      updated = updated.copyWith(enabled: enabled);
    }
    updated = _applyPositionChange(updated, positionChange);
    // Sections are stored before the character, so an open editor shows them.
    if (positive != null || negativeSections != null) {
      updated = sectionState.storeSections(
        updated,
        positive: positive,
        negative: negativeSections,
      );
    }

    final notifier = _ref.read(characterPromptNotifierProvider.notifier);
    if (!await notifier.updateCharacterPersisted(updated)) {
      return agentToolError(
        'character_persistence_failed',
        'The character changed in memory but could not be persisted.',
      );
    }
    final applied = _findCharacter(id: updated.id)!;
    final order = _ref
        .read(characterPromptNotifierProvider)
        .characters
        .indexWhere((character) => character.id == applied.id);
    return agentToolJsonResult({
      'ok': true,
      'character': characterStateJson(applied, order: order),
    });
  }

  Future<AgentToolResult> _addCharacter(Map<String, dynamic> args) async {
    late final _CharacterPositionChange positionChange;
    try {
      _validateCharacterStringFields(args);
      positionChange = _parsePositionChange(args);
    } on _PromptToolValidationException catch (error) {
      return agentToolError(error.code, error.message);
    }
    final name = (args['name'] as String?)?.trim() ?? '';
    if (name.isEmpty) {
      return agentToolError('invalid_character_name', 'name is required.');
    }

    final notifier = _ref.read(characterPromptNotifierProvider.notifier);
    final limit = notifier.characterLimit;
    final existingCharacters = _ref
        .read(characterPromptNotifierProvider)
        .characters;
    if (limit == 0) {
      final model = _ref.read(generationParamsNotifierProvider).model;
      return agentToolError(
        'model_character_unsupported',
        'Model $model does not support character prompts.',
      );
    }
    if (existingCharacters.length >= limit) {
      return agentToolError(
        'model_character_limit',
        'The current model supports at most $limit characters.',
      );
    }

    final enabled = args['enabled'] ?? true;
    if (enabled is! bool) {
      return agentToolError(
        'invalid_character_enabled',
        'enabled must be a boolean.',
      );
    }
    final sectionState = CharacterSectionState(_ref);
    final gender = _parseGender(args['gender']) ?? CharacterGender.female;
    final List<PromptGroupSectionSnapshot>? positiveSections;
    final List<PromptGroupSectionSnapshot>? negativeSections;
    try {
      final asked = sectionState.sectionsFromArgs(args, negative: false);
      positiveSections = asked == null
          ? null
          : _sectionsWithGender(asked, gender);
      negativeSections = sectionState.sectionsFromArgs(args, negative: true);
    } on PromptSectionEditException catch (error) {
      return agentToolError(error.code, error.message);
    }
    final positionMode = positionChange.mode ?? CharacterPositionMode.aiChoice;
    if (positionMode == CharacterPositionMode.custom &&
        positionChange.x == null) {
      return agentToolError(
        'missing_character_coordinates',
        'A new custom character requires both position_x and position_y.',
      );
    }
    final customPosition = positionChange.x == null
        ? null
        : CharacterPosition(
            mode: CharacterPositionMode.custom,
            row: positionChange.y!,
            column: positionChange.x!,
          );
    // 新角色带坐标必须让整个场景进入自定义布局；不带坐标则不代表其他角色要放弃
    // 已有布局，此处不反向切回 AI 摆放。
    if (positionChange.mode == CharacterPositionMode.custom) {
      notifier.setGlobalAiChoice(false);
    }
    final result = await notifier.addCharacterPersisted(
      gender,
      name: name,
      prompt: positiveSections != null
          ? CharacterSectionState.joinEnabled(positiveSections)
          : CharacterPrompt.leadingWithGender(
              (args['prompt'] as String?) ?? '',
              gender,
            ),
      negativePrompt: negativeSections != null
          ? CharacterSectionState.joinEnabled(negativeSections)
          : args.containsKey('negative_prompt')
          ? (args['negative_prompt'] as String?) ?? ''
          : null,
      enabled: enabled,
      positionMode: positionMode,
      customPosition: customPosition,
    );
    if (result == null) {
      return agentToolError(
        'character_add_failed',
        'Character could not be added.',
      );
    }
    if (!result.persisted) {
      return agentToolError(
        'character_persistence_failed',
        'The character changed in memory but could not be persisted.',
      );
    }
    final created = result.character;
    if (positiveSections != null || negativeSections != null) {
      sectionState.storeSections(
        created,
        positive: positiveSections,
        negative: negativeSections,
      );
    }
    final order = _ref
        .read(characterPromptNotifierProvider)
        .characters
        .indexWhere((character) => character.id == created.id);
    return agentToolJsonResult({
      'ok': true,
      'character': characterStateJson(created, order: order),
    });
  }

  Future<AgentToolResult> _setCharacterLayoutMode(
    Map<String, dynamic> args,
  ) async {
    final mode = args['mode'];
    if (mode != 'ai_choice' && mode != 'custom') {
      return agentToolError(
        'invalid_character_layout_mode',
        'mode must be "ai_choice" or "custom".',
      );
    }
    final notifier = _ref.read(characterPromptNotifierProvider.notifier);
    if (!await notifier.setGlobalAiChoicePersisted(mode == 'ai_choice')) {
      return agentToolError(
        'character_persistence_failed',
        'The layout changed in memory but could not be persisted.',
      );
    }
    final config = _ref.read(characterPromptNotifierProvider);
    return agentToolJsonResult({
      'ok': true,
      'character_layout_mode': mode,
      'characters': [
        for (var index = 0; index < config.characters.length; index++)
          _characterJson(config.characters[index], order: index),
      ],
    });
  }

  Future<AgentToolResult> _reorderCharacters(Map<String, dynamic> args) async {
    final rawIds = args['ordered_ids'];
    if (rawIds is! List || rawIds.any((value) => value is! String)) {
      return agentToolError(
        'invalid_character_order',
        'ordered_ids must be an array of stable character IDs.',
      );
    }
    final ids = rawIds.cast<String>();
    final notifier = _ref.read(characterPromptNotifierProvider.notifier);
    try {
      if (!await notifier.setCharacterOrderPersisted(ids)) {
        return agentToolError(
          'character_persistence_failed',
          'The order changed in memory but could not be persisted.',
        );
      }
    } on FormatException catch (error) {
      return agentToolError('invalid_character_order', error.message);
    }
    final characters = _ref.read(characterPromptNotifierProvider).characters;
    return agentToolJsonResult({
      'ok': true,
      'characters': [
        for (var index = 0; index < characters.length; index++)
          _characterJson(characters[index], order: index),
      ],
    });
  }

  Future<AgentToolResult> _removeCharacter(Map<String, dynamic> args) async {
    late final CharacterPrompt? target;
    try {
      _validateCharacterStringFields(args);
      target = _findCharacter(
        id: args['id'] as String?,
        name: args['name'] as String?,
      );
    } on _PromptToolValidationException catch (error) {
      return agentToolError(error.code, error.message);
    }
    if (target == null) {
      return agentToolError('character_not_found', 'Character not found.');
    }
    final notifier = _ref.read(characterPromptNotifierProvider.notifier);
    if (!await notifier.removeCharacterPersisted(target.id)) {
      return agentToolError(
        'character_persistence_failed',
        'The character was removed in memory but could not be persisted.',
      );
    }
    return agentToolJsonResult({'ok': true, 'removed': target.name});
  }

  Future<AgentToolResult> _clearCharacters() async {
    final notifier = _ref.read(characterPromptNotifierProvider.notifier);
    if (!await notifier.clearAllCharactersPersisted()) {
      return agentToolError(
        'character_persistence_failed',
        'Characters were cleared in memory but could not be persisted.',
      );
    }
    return agentToolJsonResult({'ok': true, 'characters': <Object>[]});
  }

  CharacterPrompt _applyPositionChange(
    CharacterPrompt character,
    _CharacterPositionChange change,
  ) {
    if (!change.hasChange) return character;
    if (change.mode == CharacterPositionMode.aiChoice) {
      return character.copyWith(positionMode: CharacterPositionMode.aiChoice);
    }
    final position = change.x != null
        ? CharacterPosition(
            mode: CharacterPositionMode.custom,
            row: change.y!,
            column: change.x!,
          )
        : character.customPosition!;
    return character.copyWith(
      positionMode: CharacterPositionMode.custom,
      customPosition: position,
    );
  }

  _CharacterPositionChange _parsePositionChange(Map<String, dynamic> args) {
    final rawMode = args['position_mode'];
    final mode = switch (rawMode) {
      null => null,
      'ai_choice' => CharacterPositionMode.aiChoice,
      'custom' => CharacterPositionMode.custom,
      _ => throw const _PromptToolValidationException(
        'invalid_character_position_mode',
        'position_mode must be "ai_choice" or "custom".',
      ),
    };
    final hasX = args.containsKey('position_x');
    final hasY = args.containsKey('position_y');
    if (hasX != hasY) {
      throw const _PromptToolValidationException(
        'partial_character_coordinates',
        'position_x and position_y must be provided together.',
      );
    }
    double? x;
    double? y;
    if (hasX) {
      x = _validateCoordinate(args['position_x'], 'position_x');
      y = _validateCoordinate(args['position_y'], 'position_y');
      if (mode == CharacterPositionMode.aiChoice) {
        throw const _PromptToolValidationException(
          'character_position_conflict',
          'ai_choice cannot be combined with coordinates.',
        );
      }
    }
    return _CharacterPositionChange(
      hasChange: rawMode != null || hasX,
      mode: mode ?? (hasX ? CharacterPositionMode.custom : null),
      x: x,
      y: y,
    );
  }

  double _validateCoordinate(Object? value, String name) {
    if (value is! num) {
      throw _PromptToolValidationException(
        'invalid_character_coordinate',
        '$name must be a finite number between 0 and 1.',
      );
    }
    final coordinate = value.toDouble();
    if (!coordinate.isFinite || coordinate < 0 || coordinate > 1) {
      throw _PromptToolValidationException(
        'invalid_character_coordinate',
        '$name must be a finite number between 0 and 1.',
      );
    }
    return coordinate;
  }

  /// The character as get_prompt_state lists it: [_characterJson] plus the sections in grouped mode and the character
  /// library link.
  Map<String, dynamic> characterStateJson(
    CharacterPrompt character, {
    required int order,
  }) {
    final sections = CharacterSectionState(_ref);
    final library = CharacterLibraryTransfer(_ref.read);
    final entryId = library.linkedEntryId(character.id);
    return {
      ..._characterJson(character, order: order),
      if (sections.groupedMode) ...sections.sectionsJson(character),
      if (entryId != null) ...{
        'library_entry_id': entryId,
        'library_unsaved_changes': library.hasUnsavedChanges(character),
      },
    };
  }

  static Map<String, dynamic> _characterJson(
    CharacterPrompt character, {
    required int order,
  }) => {
    'id': character.id,
    'order': order,
    'name': character.name,
    'gender': character.gender.name,
    'enabled': character.enabled,
    'prompt': character.prompt,
    'negative_prompt': character.negativePrompt,
    'position_mode': character.positionMode == CharacterPositionMode.aiChoice
        ? 'ai_choice'
        : 'custom',
    'position_x': character.customPosition?.column,
    'position_y': character.customPosition?.row,
  };

  void _validateCharacterStringFields(Map<String, dynamic> args) {
    const fields = [
      'id',
      'name',
      'new_name',
      'gender',
      'prompt',
      'negative_prompt',
    ];
    for (final field in fields) {
      if (args.containsKey(field) && args[field] is! String) {
        throw _PromptToolValidationException(
          'invalid_character_field',
          '$field must be a string.',
        );
      }
    }
    if (args.containsKey('gender')) _parseGender(args['gender']);
  }

  /// [sections] with the first included text section led by [gender]'s
  /// tag, which is the first tag of the joined prompt.
  static List<PromptGroupSectionSnapshot> _sectionsWithGender(
    List<PromptGroupSectionSnapshot> sections,
    CharacterGender gender,
  ) {
    var index = sections.indexWhere(
      (section) =>
          section.enabled &&
          section.fixedTagId == null &&
          section.text.trim().isNotEmpty,
    );
    if (index < 0) {
      index = sections.indexWhere((section) => section.fixedTagId == null);
    }
    if (index < 0) return sections;
    final section = sections[index];
    final text = CharacterPrompt.leadingWithGender(section.text, gender);
    if (text == section.text && section.enabled) return sections;
    return [
      ...sections.take(index),
      PromptGroupSectionSnapshot(
        id: section.id,
        text: text,
        collapsed: section.collapsed,
        keepInMain: section.keepInMain,
      ),
      ...sections.skip(index + 1),
    ];
  }

  CharacterGender? _parseGender(Object? raw) => switch (raw) {
    null => null,
    'female' => CharacterGender.female,
    'male' => CharacterGender.male,
    'other' => CharacterGender.other,
    _ => throw const _PromptToolValidationException(
      'invalid_character_gender',
      'gender must be "female", "male", or "other".',
    ),
  };
}

class _CharacterPositionChange {
  const _CharacterPositionChange({
    required this.hasChange,
    required this.mode,
    required this.x,
    required this.y,
  });

  final bool hasChange;
  final CharacterPositionMode? mode;
  final double? x;
  final double? y;
}

class _PromptToolValidationException implements Exception {
  const _PromptToolValidationException(this.code, this.message);

  final String code;
  final String message;
}

const _genderNote =
    'Default for a new character: female. A woman or girl is female, a man '
    'or boy is male; other is only for characters without a gender. The app '
    'starts the prompt with girl or boy to match, so do not add a gender tag '
    'that contradicts it.';

const _characterSectionsNote =
    'When get_prompt_state reports character_editor_mode grouped, keep the '
    "character's sections: prompt / negative_prompt replace only the enabled "
    'text sections with one section (disabled and fixed-tag sections stay), '
    'prompt_sections / negative_prompt_sections set every section of that '
    'side in order (include fixed_tag_id items to keep fixed tags), and '
    'edit_prompt_sections with character_id changes single sections. Split '
    'a new character the way the user does, for example identity, '
    'appearance, outfit and pose.';

const _characterSectionsSchema = {
  'type': 'array',
  'description':
      'Sections in order; NovelAI receives the enabled ones joined with ", ".',
  'items': {
    'type': 'object',
    'properties': {
      'text': {'type': 'string'},
      'fixed_tag_id': {
        'type': 'string',
        'description':
            'Instead of text: a section showing this fixed tag of the same '
            'prompt type.',
      },
      'enabled': {'type': 'boolean'},
      'keep_in_main': {
        'type': 'boolean',
        'description': 'Fixed-tag sections: keep the tag in the main prompt.',
      },
    },
    'additionalProperties': false,
  },
};
