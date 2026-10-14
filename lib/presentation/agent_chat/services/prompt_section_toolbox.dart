import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/agent/agent_types.dart';
import '../../../data/models/gallery/prompt_group_snapshot.dart';
import 'defined_agent_tool.dart';
import 'prompt_section_state.dart';
import 'toolbox_json.dart';

/// Tools for the prompt editor's grouped mode, where the user splits a prompt
/// into untitled sections. NovelAI receives the enabled sections joined with
/// ", "; disabled sections stay in the editor but are not sent.
class PromptSectionToolbox {
  PromptSectionToolbox(Ref ref) : _state = PromptSectionState(ref);

  final PromptSectionState _state;

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
        'NovelAI receives the enabled sections joined with ", "; disabled '
        'sections stay in the editor for later but are not sent. Operations '
        'apply in order and all-or-nothing; sections you do not mention are '
        'left untouched. Keep the user\'s own division into sections instead '
        'of merging them. To delete a section use remove_prompt_section. In '
        'single mode this tool fails unless enable_grouped_mode is true, '
        'which switches the editor to grouped mode; do that only when the '
        'user asks for sections.',
    parameters: toolboxObject(
      properties: {
        'prompt_type': {
          'type': 'string',
          'enum': ['positive', 'negative'],
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
                    'Section text: required for add, optional for update.',
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
        'mode, including its text. Prefer disabling it with '
        'edit_prompt_sections when the user may want it back.',
    parameters: toolboxObject(
      properties: {
        'prompt_type': {
          'type': 'string',
          'enum': ['positive', 'negative'],
        },
        'id': {'type': 'string', 'minLength': 1},
      },
      required: const ['prompt_type', 'id'],
    ),
    executeFn: (_, params) async {
      final negative = params['prompt_type'] == 'negative';
      final snapshot = _state.read();
      if (!snapshot.groupedMode) return _notGrouped();
      final List<PromptGroupSectionSnapshot> sections;
      try {
        sections = PromptSectionEdits.remove(
          _sectionsOf(snapshot, negative: negative),
          params['id'] as String,
        );
      } on PromptSectionEditException catch (error) {
        return agentToolError(error.code, error.message);
      }
      return _commit(snapshot, sections, negative: negative);
    },
  );

  Future<AgentToolResult> _executeEdit(Map<String, dynamic> params) async {
    final negative = params['prompt_type'] == 'negative';
    final snapshot = _state.read();
    final enableGrouped = params['enable_grouped_mode'] == true;
    if (!snapshot.groupedMode && !enableGrouped) return _notGrouped();
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
    var sections = _sectionsOf(snapshot, negative: negative);
    final added = <String>[];
    try {
      for (final (index, raw) in operations.indexed) {
        if (raw is! Map) {
          throw PromptSectionEditException(
            'invalid_operations',
            'Operation ${index + 1} must be an object.',
          );
        }
        final operation = _Operation.parse(raw, index);
        switch (operation.action) {
          case 'add':
            final id = PromptSectionEdits.newId();
            sections = PromptSectionEdits.add(
              sections,
              section: PromptGroupSectionSnapshot(
                id: id,
                text: operation.text!,
                enabled: operation.enabled ?? true,
              ),
              index: operation.index,
            );
            added.add(id);
          case 'update':
            sections = PromptSectionEdits.update(
              sections,
              operation.id!,
              text: operation.text,
              enabled: operation.enabled,
            );
          case 'move':
            sections = PromptSectionEdits.move(
              sections,
              operation.id!,
              operation.index!,
            );
        }
      }
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
}

/// Appended to the set_positive_prompt / set_negative_prompt descriptions.
const promptSectionGroupedWriteNote =
    "In grouped mode (see get_prompt_state) the user's sections are kept: "
    'append / prepend add a new section, replace swaps all enabled sections '
    'for one new section and keeps disabled ones. Use edit_prompt_sections '
    'to change a specific section.';

/// The section fields the agent sees; collapse state belongs to the editor.
List<Map<String, Object?>> promptSectionsJson(
  Iterable<PromptGroupSectionSnapshot> sections,
) => [
  for (final section in sections)
    {'id': section.id, 'text': section.text, 'enabled': section.enabled},
];

class _Operation {
  const _Operation({
    required this.action,
    this.id,
    this.text,
    this.enabled,
    this.index,
  });

  final String action;
  final String? id;
  final String? text;
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
    final enabled = raw['enabled'];
    final index = raw['index'];
    if (id != null && id is! String) throw invalid('id must be a string.');
    if (text != null && text is! String) {
      throw invalid('text must be a string.');
    }
    if (enabled != null && enabled is! bool) {
      throw invalid('enabled must be a boolean.');
    }
    if (index != null && (index is! int || index < 0)) {
      throw invalid('index must be a non-negative integer.');
    }
    switch (action) {
      case 'add':
        if (text is! String || text.trim().isEmpty) {
          throw invalid('add needs non-empty text.');
        }
      case 'update':
        if (id is! String || id.isEmpty) throw invalid('update needs id.');
        if (text == null && enabled == null) {
          throw invalid('update needs text or enabled.');
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
      enabled: enabled as bool?,
      index: index as int?,
    );
  }
}
