import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/agent/agent_types.dart';
import '../../../core/agent/harness/env/dart_io_execution_env.dart';
import '../../../core/agent/harness/harness_types.dart';
import '../../providers/character_prompt_provider.dart';
import '../../providers/generation/generation_params_notifier.dart';
import 'character_section_state.dart';
import 'character_toolbox.dart';
import 'defined_agent_tool.dart';
import 'prompt_section_state.dart';
import 'prompt_section_toolbox.dart';
import '../../../core/agent/harness/skills.dart';
import '../../../core/agent/private_data_guard.dart';
import '../../../core/constants/model_capabilities.dart';

/// 提示词工具集。
///
/// 通过注入的 [Ref] 读写现有 Riverpod providers，任何改动都会即时
/// 反映到生成页 UI。
class PromptToolbox {
  PromptToolbox(
    this._ref, {
    Map<String, HarnessSkill>? skills,
    List<SkillDiagnostic>? skillDiagnostics,
    Future<int> Function()? reloadSkills,
  }) : _skills = skills ?? const {},
       _skillDiagnostics = skillDiagnostics ?? const [],
       _reloadSkills = reloadSkills;

  final Ref _ref;
  final Map<String, HarnessSkill> _skills;
  final List<SkillDiagnostic> _skillDiagnostics;
  final Future<int> Function()? _reloadSkills;
  late final CharacterToolbox _characters = CharacterToolbox(_ref);

  List<AgentTool> tools() {
    return [
      DefinedAgentTool(
        name: 'get_prompt_state',
        label: 'Get Prompt State',
        description:
            'Read the complete NovelAI prompt and character orchestration '
            'state. Returns stable character IDs, exact order, independent '
            'positive/negative prompts, enabled state, per-character saved '
            'position mode and continuous x/y centers, global AI/custom '
            'layout mode, current model, and its effective character limit. '
            'positive_prompt / negative_prompt are what NovelAI receives. '
            'prompt_editor_mode is single or grouped; in grouped mode the '
            'user split the prompt into sections, returned as '
            'positive_sections / negative_sections (id, text, enabled), and '
            'only enabled sections are sent. character_editor_mode tells '
            'the same for character prompts: in grouped mode every character '
            'carries its own positive_sections / negative_sections, edited '
            'with edit_prompt_sections and character_id. A character section '
            'with fixed_tag_id shows that fixed tag; an enabled character '
            'that includes an enabled fixed tag takes it out of the main '
            'prompt for that generation unless keep_in_main is true. '
            'library_entry_id names the character library entry a character '
            'came from or was saved to. '
            'Call this before editing anything.',
        parameters: const {
          'type': 'object',
          'properties': <String, dynamic>{},
          'required': <String>[],
        },
        executeFn: (_, __) async {
          final params = _ref.read(generationParamsNotifierProvider);
          final config = _ref.read(characterPromptNotifierProvider);
          final capabilities = ModelCapabilityRegistry.of(params.model);
          final sections = PromptSectionState(_ref).read();
          final characterSections = CharacterSectionState(_ref);
          return agentToolJsonResult({
            'model': params.model,
            'model_character_limit': capabilities.maxCharacters,
            'supports_characters': capabilities.maxCharacters > 0,
            'character_layout_mode': config.globalAiChoice
                ? 'ai_choice'
                : 'custom',
            'positive_prompt': params.prompt,
            'negative_prompt': params.negativePrompt,
            'prompt_editor_mode': sections.groupedMode ? 'grouped' : 'single',
            if (sections.groupedMode) ...{
              'positive_sections': promptSectionsJson(
                sections.positiveSections,
              ),
              'negative_sections': promptSectionsJson(
                sections.negativeSections,
              ),
            },
            'character_editor_mode': characterSections.groupedMode
                ? 'grouped'
                : 'single',
            'characters': [
              for (var index = 0; index < config.characters.length; index++)
                _characters.characterStateJson(
                  config.characters[index],
                  order: index,
                ),
            ],
          });
        },
      ),
      DefinedAgentTool(
        name: 'set_positive_prompt',
        label: 'Set Positive Prompt',
        description:
            'Write the main positive prompt. mode: "replace" '
            '(default), "append" (add at the end), or "prepend" (add at the '
            'beginning). Content should be English danbooru-style tags '
            'separated by commas. Use NovelAI emphasis syntax — {tag} / '
            '[tag] on every model, 1.3::tag :: numeric on V4+ — never '
            '(tag:1.2) which is Stable Diffusion syntax. '
            '$promptSectionGroupedWriteNote',
        parameters: const {
          'type': 'object',
          'properties': {
            'text': {
              'type': 'string',
              'description': 'The prompt text or tags to write.',
            },
            'mode': {
              'type': 'string',
              'enum': ['replace', 'append', 'prepend'],
              'description': 'How to apply the text. Default: replace.',
            },
          },
          'required': ['text'],
        },
        executeFn: (_, params) async =>
            _setPrompt(positive: true, args: params),
      ),
      DefinedAgentTool(
        name: 'set_negative_prompt',
        label: 'Set Negative Prompt',
        description:
            'Write the negative prompt (Undesired Content). mode: '
            '"replace" (default), "append", or "prepend". '
            '$promptSectionGroupedWriteNote',
        parameters: const {
          'type': 'object',
          'properties': {
            'text': {
              'type': 'string',
              'description': 'The negative prompt text or tags to write.',
            },
            'mode': {
              'type': 'string',
              'enum': ['replace', 'append', 'prepend'],
              'description': 'How to apply the text. Default: replace.',
            },
          },
          'required': ['text'],
        },
        executeFn: (_, params) async =>
            _setPrompt(positive: false, args: params),
      ),
      ..._characters.tools(),
      if (_skills.isNotEmpty)
        DefinedAgentTool(
          name: 'read_skill',
          label: 'Read Skill',
          description:
              'Read the full instructions of an available skill '
              'listed in the system prompt. Returns the SKILL.md content.',
          parameters: const {
            'type': 'object',
            'properties': {
              'name': {'type': 'string', 'description': 'Skill name.'},
            },
            'required': ['name'],
          },
          executeFn: (_, params) => _readSkill(params),
        ),
      if (_skills.isNotEmpty)
        DefinedAgentTool(
          name: 'read_skill_resource',
          label: 'Read Skill Resource',
          description:
              'Read a text reference, template, or script belonging to an '
              'available skill. The relative path is strictly confined to '
              'that skill directory. Use offset and limit for long files.',
          parameters: const {
            'type': 'object',
            'properties': {
              'name': {'type': 'string', 'description': 'Skill name.'},
              'path': {
                'type': 'string',
                'description': 'Path relative to the skill directory.',
              },
              'offset': {
                'type': 'integer',
                'minimum': 0,
                'description': 'Zero-based starting line. Default 0.',
              },
              'limit': {
                'type': 'integer',
                'minimum': 1,
                'maximum': 1000,
                'description': 'Maximum lines to return, 1-1000. Default 200.',
              },
            },
            'required': ['name', 'path'],
          },
          executeFn: (_, params) => _readSkillResource(params),
        ),
      DefinedAgentTool(
        name: 'get_skill_diagnostics',
        label: 'Get Skill Diagnostics',
        description:
            'List warnings from the latest skill discovery pass, including '
            'invalid metadata and unreadable files.',
        parameters: const {
          'type': 'object',
          'properties': <String, dynamic>{},
          'required': <String>[],
        },
        executeFn: (_, __) async => agentToolJsonResult({
          'count': _skillDiagnostics.length,
          'diagnostics': [
            for (final diagnostic in _skillDiagnostics)
              {
                'code': diagnostic.code.name,
                'message': PrivateDataGuard.redactAbsolutePaths(
                  diagnostic.message,
                ),
                'path': _agentSafePath(diagnostic.path),
              },
          ],
        }),
      ),
      if (_reloadSkills != null)
        DefinedAgentTool(
          name: 'reload_skills',
          label: 'Reload Skills',
          description:
              'Rediscover skills from workspace and user-global directories. '
              'The refreshed inventory and tools apply to subsequent model '
              'turns.',
          parameters: const {
            'type': 'object',
            'properties': <String, dynamic>{},
            'required': <String>[],
          },
          executeFn: (_, __) async {
            final count = await _reloadSkills();
            final available = _skills.keys.toList()..sort();
            return agentToolJsonResult({
              'ok': true,
              'count': count,
              'skills': available,
              'diagnostic_count': _skillDiagnostics.length,
            });
          },
        ),
    ];
  }

  Future<AgentToolResult> _setPrompt({
    required bool positive,
    required Map<String, dynamic> args,
  }) async {
    final text = (args['text'] as String?)?.trim() ?? '';
    if (text.isEmpty) {
      return agentToolError(
        'invalid_prompt_text',
        'Parameter "text" must be a non-empty string.',
      );
    }
    final mode = (args['mode'] as String?) ?? 'replace';
    final grouped = await PromptSectionToolbox(
      _ref,
    ).setGroupedPrompt(positive: positive, text: text, mode: mode);
    if (grouped != null) return grouped;
    final params = _ref.read(generationParamsNotifierProvider);
    final current = positive ? params.prompt : params.negativePrompt;
    final combined = combinePromptText(current, text, mode);

    final notifier = _ref.read(generationParamsNotifierProvider.notifier);
    if (positive) {
      notifier.updatePrompt(combined);
    } else {
      notifier.updateNegativePrompt(combined);
    }
    // updatePrompt 内部经 Future.microtask 写入 state，冲刷微任务队列后
    // 再回读，保证返回给模型的是已生效的值。
    await Future<void>.delayed(Duration.zero);
    final applied = _ref.read(generationParamsNotifierProvider);
    return agentToolJsonResult({
      'ok': true,
      positive ? 'positive_prompt' : 'negative_prompt': positive
          ? applied.prompt
          : applied.negativePrompt,
    });
  }

  Future<AgentToolResult> _readSkill(Map<String, dynamic> args) async {
    final name = (args['name'] as String?)?.trim() ?? '';
    final skill = _skills[name];
    if (skill == null) {
      final available = _skills.keys.toList()..sort();
      return agentToolError(
        'skill_not_found',
        'Skill "$name" not found. Available skills: ${available.join(', ')}.',
      );
    }
    // 代理 的 Skill.content 即 SKILL.md 正文（加载时已剥离 frontmatter）。
    final content = PrivateDataGuard.redactAbsolutePaths(skill.content);
    return agentToolTextResult(content.isEmpty ? '(empty)' : content);
  }

  Future<AgentToolResult> _readSkillResource(Map<String, dynamic> args) async {
    final name = (args['name'] as String?)?.trim() ?? '';
    final relativePath = (args['path'] as String?)?.trim() ?? '';
    final skill = _skills[name];
    if (skill == null) {
      return agentToolError('skill_not_found', 'Skill "$name" not found.');
    }
    if (relativePath.isEmpty) {
      return agentToolError(
        'missing_skill_resource_path',
        'Parameter "path" is required.',
      );
    }
    final offset = (args['offset'] as num?)?.toInt() ?? 0;
    final limit = (args['limit'] as num?)?.toInt() ?? 200;
    if (offset < 0) {
      return agentToolError(
        'invalid_skill_resource_offset',
        'Parameter "offset" must be at least 0.',
      );
    }
    if (limit < 1 || limit > 1000) {
      return agentToolError(
        'invalid_skill_resource_limit',
        'Parameter "limit" must be between 1 and 1000.',
      );
    }

    final skillRoot = File(skill.filePath).parent.path;
    final env = DartIoExecutionEnv(workingDirectory: skillRoot);
    final resolved = await env.absolutePath(relativePath);
    final absolutePath = resolved.valueOrNull;
    if (absolutePath == null) {
      return agentToolError(
        'skill_resource_path_not_permitted',
        'Skill resource path is not permitted.',
      );
    }
    final info = await env.fileInfo(absolutePath);
    if (info.valueOrNull?.kind != FileKind.file) {
      return agentToolError(
        'skill_resource_not_readable',
        'Skill resource is not a readable text file.',
      );
    }
    final result = await env.readTextFile(absolutePath);
    final content = result.valueOrNull;
    if (content == null) {
      return agentToolError(
        'skill_resource_read_failed',
        'Failed to read skill resource.',
      );
    }
    final lines = content.split(RegExp(r'\r?\n'));
    final selected = offset >= lines.length
        ? const <String>[]
        : lines.skip(offset).take(limit).toList(growable: false);
    return agentToolJsonResult({
      'path': relativePath,
      'offset': offset,
      'returned_lines': selected.length,
      'total_lines': lines.length,
      'truncated': offset + selected.length < lines.length,
      'content': PrivateDataGuard.redactAbsolutePaths(selected.join('\n')),
    });
  }

  String _agentSafePath(String path) {
    final normalized = path.replaceAll('\\', '/');
    final segments = normalized
        .split('/')
        .where((segment) => segment.isNotEmpty && !segment.endsWith(':'))
        .toList(growable: false);
    if (segments.isEmpty) return '(unknown)';
    final start = segments.length > 3 ? segments.length - 3 : 0;
    return '.../${segments.skip(start).join('/')}';
  }
}

/// 按 NAI 逗号分隔习惯合并提示词文本。
String combinePromptText(String current, String addition, String mode) {
  final cur = current.trim();
  final add = addition.trim();
  switch (mode) {
    case 'append':
      if (cur.isEmpty) {
        return add;
      }
      return '$cur, $add';
    case 'prepend':
      if (cur.isEmpty) {
        return add;
      }
      return '$add, $cur';
    default:
      return add;
  }
}
