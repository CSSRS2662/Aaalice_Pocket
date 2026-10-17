import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/agent/agent_types.dart';
import '../../../data/models/character/character_prompt.dart';
import '../../../data/models/gallery/prompt_group_snapshot.dart';
import '../../providers/character_prompt_provider.dart';
import 'character_section_state.dart';
import 'defined_agent_tool.dart';
import 'prompt_section_state.dart';
import 'toolbox_json.dart';

/// Tools for the prompt editors' grouped mode, where the user splits a
/// prompt into untitled sections: the main prompt and, with character_id,
/// a character's prompts. NovelAI receives the enabled sections joined with
/// ", "; disabled sections stay in the editor but are not sent.
class PromptSectionToolbox {
  PromptSectionToolbox(Ref ref)
    : _ref = ref,
      _state = PromptSectionState(ref),
      _characters = CharacterSectionState(ref);

  final Ref _ref;
  final PromptSectionState _state;
  final CharacterSectionState _characters;

  static const int maxOperations = 20;

  List<AgentTool> tools() => [_edit(), _remove()];

  /// set_positive_prompt / set_negative_prompt in grouped mode, keeping the
  /// user's sections: append and prepend add a section, replace swaps the
  /// enabled sections for one. Returns null in single mode.
  Future<AgentToolResult?> setGroupedPrompt({
    required bool positive,
    required String text,
    required String mode,
  }) async {
    final snapshot = _state.read();
    if (!snapshot.groupedMode) return null;
    final current = _sectionsOf(snapshot, negative: !positive);
    final List<PromptGroupSectionSnapshot> sections;
    try {
      sections = switch (mode) {
        'append' || 'prepend' => PromptSectionEdits.add(
          current,
          section: PromptGroupSectionSnapshot(
            id: PromptSectionEdits.newId(),
            text: text,
          ),
          index: mode == 'prepend' ? 0 : null,
        ),
        _ => PromptSectionEdits.replaceEnabled(current, text),
      };
    } on PromptSectionEditException catch (error) {
      return agentToolError(error.code, error.message);
    }
    final next = await _write(snapshot, sections, negative: !positive);
    return agentToolJsonResult({
      'ok': true,
      positive ? 'positive_prompt' : 'negative_prompt': positive
          ? next.positivePrompt
          : next.negativePrompt,
      'prompt_editor_mode': 'grouped',
      positive ? 'positive_sections' : 'negative_sections': promptSectionsJson(
        sections,
      ),
    });
  }

  DefinedAgentTool _edit() => DefinedAgentTool(
    name: 'edit_prompt_sections',
    label: 'Edit Prompt Sections',
    description:
        'Add, rewrite, enable/disable or move sections of the positive or '
        'negative prompt while the editor is in grouped mode '
        '(get_prompt_state reports prompt_editor_mode and section ids). '
        'Pass character_id to edit that character\'s sections instead of '
        'the main prompt (get_prompt_state reports character_editor_mode '
        'and each character\'s sections). NovelAI receives the enabled '
        'sections joined with ", "; disabled sections stay in the editor for '
        'later but are not sent. Operations apply in order and '
        'all-or-nothing; sections you do not mention are left untouched. '
        'Keep the user\'s own division into sections instead of merging '
        'them. Character sections may show a fixed tag: add one with '
        'fixed_tag_id instead of text; its text follows the tag and cannot be '
        'rewritten here. A character that includes an enabled fixed tag '
        'takes it from the main prompt for that generation unless '
        'keep_in_main is true. To delete a section use remove_prompt_section. '
        'In single mode this tool fails unless enable_grouped_mode is true, '
        'which switches that editor to grouped mode; do that only when the '
        'user asks for sections.',
    parameters: toolboxObject(
      properties: {
        'prompt_type': {
          'type': 'string',
          'enum': ['positive', 'negative'],
        },
        'character_id': {
          'type': 'string',
          'description': 'Stable character id; omit to edit the main prompt.',
        },
        'operations': {
          'type': 'array',
          'minItems': 1,
          'maxItems': maxOperations,
          'items': {
            'type': 'object',
            'properties': {
              'action': {
                'type': 'string',
                'enum': ['add', 'update', 'move'],
              },
              'id': {
                'type': 'string',
                'description': 'Section id, required for update and move.',
              },
              'text': {
                'type': 'string',
                'description':
                    'Section text: add needs text or fixed_tag_id; optional '
                    'for update.',
              },
              'fixed_tag_id': {
                'type': 'string',
                'description':
                    'add only, characters only: a section showing this fixed '
                    'tag (list_fixed_tags) of the same prompt type.',
              },
              'keep_in_main': {
                'type': 'boolean',
                'description':
                    'Fixed-tag sections only: true keeps the tag in the main '
                    'prompt as well. Default false.',
              },
              'enabled': {
                'type': 'boolean',
                'description': 'add defaults to true.',
              },
              'index': {
                'type': 'integer',
                'minimum': 0,
                'description':
                    '0-based position: optional for add (default end), '
                    'required for move.',
              },
            },
            'required': ['action'],
            'additionalProperties': false,
          },
        },
        'enable_grouped_mode': {'type': 'boolean'},
      },
      required: const ['prompt_type', 'operations'],
    ),
    executeFn: (_, params) => _executeEdit(params),
  );

  DefinedAgentTool _remove() => DefinedAgentTool(
    name: 'remove_prompt_section',
    label: 'Remove Prompt Section',
    description:
        'Delete one section of the positive or negative prompt in grouped '
        'mode, including its text; pass character_id for a character\'s '
        'section. Prefer disabling it with edit_prompt_sections when the user '
        'may want it back.',
    parameters: toolboxObject(
      properties: {
        'prompt_type': {
          'type': 'string',
          'enum': ['positive', 'negative'],
        },
        'character_id': {'type': 'string'},
        'id': {'type': 'string', 'minLength': 1},
      },
      required: const ['prompt_type', 'id'],
    ),
    executeFn: (_, params) async {
      final negative = params['prompt_type'] == 'negative';
      final id = params['id'] as String;
      if (params['character_id'] case final String characterId) {
        final character = _findCharacter(characterId);
        if (character == null) return _characterNotFound(characterId);
        if (!_characters.groupedMode) return _charactersNotGrouped();
        try {
          final sections = PromptSectionEdits.remove(
            _characters.read(character, negative: negative),
            id,
          );
          return _commitCharacter(character, sections, negative: negative);
        } on PromptSectionEditException catch (error) {
          return agentToolError(error.code, error.message);
        }
      }
      final snapshot = _state.read();
      if (!snapshot.groupedMode) return _notGrouped();
      final List<PromptGroupSectionSnapshot> sections;
      try {
        sections = PromptSectionEdits.remove(
          _sectionsOf(snapshot, negative: negative),
          id,
        );
      } on PromptSectionEditException catch (error) {
        return agentToolError(error.code, error.message);
      }
      return _commit(snapshot, sections, negative: negative);
    },
  );

  Future<AgentToolResult> _executeEdit(Map<String, dynamic> params) async {
    final negative = params['prompt_type'] == 'negative';
    final enableGrouped = params['enable_grouped_mode'] == true;
    final operations = params['operations'];
    if (operations is! List || operations.isEmpty) {
      return agentToolError(
        'invalid_operations',
        'operations must be a non-empty array.',
      );
    }
    if (operations.length > maxOperations) {
      return agentToolError(
        'invalid_operations',
        'At most $maxOperations operations per call.',
      );
    }
    if (params['character_id'] case final String characterId) {
      final character = _findCharacter(characterId);
      if (character == null) return _characterNotFound(characterId);
      if (!_characters.groupedMode && !enableGrouped) {
        return _charactersNotGrouped();
      }
      try {
        final (sections, added) = _apply(
          _characters.read(character, negative: negative),
          operations,
          fixedTagSection: (id, {required enabled, required keepInMain}) =>
              _characters.fixedTagSection(
                id,
                negative: negative,
                enabled: enabled,
                keepInMain: keepInMain,
              ),
        );
        if (!_characters.groupedMode) _characters.enableGroupedMode();
        return _commitCharacter(
          character,
          sections,
          negative: negative,
          extra: {if (added.isNotEmpty) 'added_section_ids': added},
        );
      } on PromptSectionEditException catch (error) {
        return agentToolError(error.code, error.message);
      }
    }

    final snapshot = _state.read();
    if (!snapshot.groupedMode && !enableGrouped) return _notGrouped();
    final List<PromptGroupSectionSnapshot> sections;
    final List<String> added;
    try {
      (sections, added) = _apply(
        _sectionsOf(snapshot, negative: negative),
        operations,
      );
    } on PromptSectionEditException catch (error) {
      return agentToolError(error.code, error.message);
    }
    return _commit(
      snapshot,
      sections,
      negative: negative,
      groupedMode: true,
      extra: {if (added.isNotEmpty) 'added_section_ids': added},
    );
  }

  /// Applies [operations] in order; [fixedTagSection] makes the sections of
  /// fixed-tag adds and is null where fixed-tag sections do not exist.
  (List<PromptGroupSectionSnapshot>, List<String>) _apply(
    List<PromptGroupSectionSnapshot> initial,
    List<Object?> operations, {
    PromptGroupSectionSnapshot Function(
      String fixedTagId, {
      required bool enabled,
      required bool keepInMain,
    })?
    fixedTagSection,
  }) {
    var sections = initial;
    final added = <String>[];
    for (final (index, raw) in operations.indexed) {
      if (raw is! Map) {
        throw PromptSectionEditException(
          'invalid_operations',
          'Operation ${index + 1} must be an object.',
        );
      }
      final operation = _Operation.parse(raw, index);
      if ((operation.fixedTagId != null || operation.keepInMain != null) &&
          fixedTagSection == null) {
        throw PromptSectionEditException(
          'invalid_operations',
          'Operation ${index + 1}: fixed-tag sections exist only in '
              'characters. Enabled fixed tags reach the main prompt on their '
              'own; manage them with the fixed tag tools.',
        );
      }
      switch (operation.action) {
        case 'add':
          final PromptGroupSectionSnapshot section;
          if (operation.fixedTagId case final fixedTagId?) {
            section = _uniqueFixedTag(
              sections,
              fixedTagSection!(
                fixedTagId,
                enabled: operation.enabled ?? true,
                keepInMain: operation.keepInMain ?? false,
              ),
            );
          } else {
            section = PromptGroupSectionSnapshot(
              id: PromptSectionEdits.newId(),
              text: operation.text!,
              enabled: operation.enabled ?? true,
            );
          }
          sections = PromptSectionEdits.add(
            sections,
            section: section,
            index: operation.index,
          );
          added.add(section.id);
        case 'update':
          sections = PromptSectionEdits.update(
            sections,
            operation.id!,
            text: operation.text,
            enabled: operation.enabled,
            keepInMain: operation.keepInMain,
          );
        case 'move':
          sections = PromptSectionEdits.move(
            sections,
            operation.id!,
            operation.index!,
          );
      }
    }
    return (sections, added);
  }

  static PromptGroupSectionSnapshot _uniqueFixedTag(
    List<PromptGroupSectionSnapshot> sections,
    PromptGroupSectionSnapshot section,
  ) {
    if (sections.any((s) => s.fixedTagId == section.fixedTagId)) {
      throw PromptSectionEditException(
        'duplicate_fixed_tag',
        'Fixed tag ${section.fixedTagId} is already one of these sections.',
      );
    }
    return section;
  }

  Future<AgentToolResult> _commit(
    PromptGroupSnapshot snapshot,
    List<PromptGroupSectionSnapshot> sections, {
    required bool negative,
    bool? groupedMode,
    Map<String, Object?> extra = const {},
  }) async {
    final next = await _write(
      snapshot,
      sections,
      negative: negative,
      groupedMode: groupedMode,
    );
    return agentToolJsonResult({
      'ok': true,
      'prompt_type': negative ? 'negative' : 'positive',
      'prompt_editor_mode': 'grouped',
      'prompt': negative ? next.negativePrompt : next.positivePrompt,
      'sections': promptSectionsJson(sections),
      ...extra,
    });
  }

  AgentToolResult _commitCharacter(
    CharacterPrompt character,
    List<PromptGroupSectionSnapshot> sections, {
    required bool negative,
    Map<String, Object?> extra = const {},
  }) {
    final updated = _characters.write(
      character,
      positive: negative ? null : sections,
      negative: negative ? sections : null,
    );
    return agentToolJsonResult({
      'ok': true,
      'character_id': updated.id,
      'prompt_type': negative ? 'negative' : 'positive',
      'character_editor_mode': 'grouped',
      'prompt': negative ? updated.negativePrompt : updated.prompt,
      'sections': promptSectionsJson(
        sections,
        fixedTagName: (id) => _characters.fixedTag(id)?.name,
      ),
      ...extra,
    });
  }

  Future<PromptGroupSnapshot> _write(
    PromptGroupSnapshot snapshot,
    List<PromptGroupSectionSnapshot> sections, {
    required bool negative,
    bool? groupedMode,
  }) async {
    final next = PromptGroupSnapshot(
      groupedMode: groupedMode ?? snapshot.groupedMode,
      positiveSections: negative ? snapshot.positiveSections : sections,
      negativeSections: negative ? sections : snapshot.negativeSections,
    );
    await _state.write(next, positive: !negative, negative: negative);
    return next;
  }

  CharacterPrompt? _findCharacter(String id) =>
      _ref.read(characterPromptNotifierProvider).findCharacterById(id);

  static List<PromptGroupSectionSnapshot> _sectionsOf(
    PromptGroupSnapshot snapshot, {
    required bool negative,
  }) => negative ? snapshot.negativeSections : snapshot.positiveSections;

  static AgentToolResult _notGrouped() => agentToolError(
    'prompt_not_grouped',
    'The prompt editor is in single mode, so the prompt has no sections. '
        'Use set_positive_prompt / set_negative_prompt, or pass '
        'enable_grouped_mode=true to edit_prompt_sections when the user wants '
        'sections.',
  );

  static AgentToolResult _charactersNotGrouped() => agentToolError(
    'character_prompts_not_grouped',
    'Character prompts are edited in single mode, so they have no sections. '
        'Use update_character, or pass enable_grouped_mode=true to '
        'edit_prompt_sections when the user wants sections.',
  );

  static AgentToolResult _characterNotFound(String id) => agentToolError(
    'character_not_found',
    'No character has id "$id". Call get_prompt_state for character ids.',
  );
}

/// Appended to the set_positive_prompt / set_negative_prompt descriptions.
const promptSectionGroupedWriteNote =
    "In grouped mode (see get_prompt_state) the user's sections are kept: "
    'append / prepend add a new section, replace swaps all enabled sections '
    'for one new section and keeps disabled ones. Use edit_prompt_sections '
    'to change a specific section.';

class _Operation {
  const _Operation({
    required this.action,
    this.id,
    this.text,
    this.fixedTagId,
    this.keepInMain,
    this.enabled,
    this.index,
  });

  final String action;
  final String? id;
  final String? text;
  final String? fixedTagId;
  final bool? keepInMain;
  final bool? enabled;
  final int? index;

  static _Operation parse(Map raw, int position) {
    PromptSectionEditException invalid(String message) =>
        PromptSectionEditException(
          'invalid_operations',
          'Operation ${position + 1}: $message',
        );
    final action = raw['action'];
    final id = raw['id'];
    final text = raw['text'];
    final fixedTagId = raw['fixed_tag_id'];
    final keepInMain = raw['keep_in_main'];
    final enabled = raw['enabled'];
    final index = raw['index'];
    if (id != null && id is! String) throw invalid('id must be a string.');
    if (text != null && text is! String) {
      throw invalid('text must be a string.');
    }
    if (fixedTagId != null && (fixedTagId is! String || fixedTagId.isEmpty)) {
      throw invalid('fixed_tag_id must be a non-empty string.');
    }
    if (keepInMain != null && keepInMain is! bool) {
      throw invalid('keep_in_main must be a boolean.');
    }
    if (enabled != null && enabled is! bool) {
      throw invalid('enabled must be a boolean.');
    }
    if (index != null && (index is! int || index < 0)) {
      throw invalid('index must be a non-negative integer.');
    }
    switch (action) {
      case 'add':
        if (fixedTagId != null) {
          if (text != null) {
            throw invalid('add takes text or fixed_tag_id, not both.');
          }
        } else {
          if (text is! String || text.trim().isEmpty) {
            throw invalid('add needs non-empty text or a fixed_tag_id.');
          }
          if (keepInMain != null) {
            throw invalid('keep_in_main needs fixed_tag_id.');
          }
        }
      case 'update':
        if (id is! String || id.isEmpty) throw invalid('update needs id.');
        if (fixedTagId != null) {
          throw invalid('fixed_tag_id can only be set when adding.');
        }
        if (text == null && enabled == null && keepInMain == null) {
          throw invalid('update needs text, enabled or keep_in_main.');
        }
      case 'move':
        if (id is! String || id.isEmpty) throw invalid('move needs id.');
        if (index == null) throw invalid('move needs index.');
      default:
        throw invalid('action must be add, update or move.');
    }
    return _Operation(
      action: action as String,
      id: id as String?,
      text: (text as String?)?.trim(),
      fixedTagId: fixedTagId as String?,
      keepInMain: keepInMain as bool?,
      enabled: enabled as bool?,
      index: index as int?,
    );
  }
}
