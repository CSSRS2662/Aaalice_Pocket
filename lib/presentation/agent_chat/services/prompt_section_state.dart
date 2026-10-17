import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/storage_keys.dart';
import '../../../core/storage/local_storage_service.dart';
import '../../../data/models/gallery/prompt_group_snapshot.dart';
import '../../providers/generation/generation_params_notifier.dart';
import '../../providers/prompt_group_state_provider.dart';

/// Reads and writes the prompt partitions behind the generation prompt for
/// writers that are not the prompt editor, such as the agent.
///
/// The editor widget owns the live partitions, so writes travel through the
/// restore request that metadata import already uses. The stored editor state
/// and the published snapshot change as well, so a generation page that is not
/// on screen opens with the new partitions and the next result records them.
class PromptSectionState {
  PromptSectionState(this._ref);

  final Ref _ref;

  /// Current partitions; a side whose stored partitions no longer produce the
  /// generation prompt falls back to one partition holding that prompt.
  PromptGroupSnapshot read() {
    final params = _ref.read(generationParamsNotifierProvider);
    final live = _ref.read(currentPromptGroupSnapshotProvider);
    final stored = _readStored();
    List<PromptGroupSectionSnapshot> side({required bool negative}) {
      final prompt = negative ? params.negativePrompt : params.prompt;
      final prefix = negative ? 'n' : 'p';
      if (live != null &&
          (negative ? live.negativePrompt : live.positivePrompt) == prompt) {
        return _withIds(
          negative ? live.negativeSections : live.positiveSections,
          prefix,
        );
      }
      if (stored != null &&
          (negative ? stored.negativePrompt : stored.positivePrompt) ==
              prompt) {
        return _withIds(
          negative
              ? stored.snapshot.negativeSections
              : stored.snapshot.positiveSections,
          prefix,
        );
      }
      return [PromptGroupSectionSnapshot(id: '$prefix-1', text: prompt)];
    }

    return PromptGroupSnapshot(
      groupedMode: live?.groupedMode ?? stored?.snapshot.groupedMode ?? false,
      positiveSections: side(negative: false),
      negativeSections: side(negative: true),
    );
  }

  /// Publishes [next] to the editor, the stored editor state and the
  /// generation prompt, then waits until the prompt has been applied.
  Future<void> write(
    PromptGroupSnapshot next, {
    required bool positive,
    required bool negative,
  }) async {
    // The request goes first: a change that keeps the same tags, such as
    // editing a disabled partition, is applied by the editor right away and
    // never changes the generation prompt.
    _ref
        .read(promptGroupRestoreRequestProvider.notifier)
        .state = PromptGroupRestoreRequest(
      snapshot: next,
      restorePositive: positive,
      restoreNegative: negative,
    );
    await _ref
        .read(localStorageServiceProvider)
        .setSetting(
          StorageKeys.promptGroupEditorState,
          jsonEncode(next.toJson()),
        );
    _ref.read(currentPromptGroupSnapshotProvider.notifier).state = next;
    final params = _ref.read(generationParamsNotifierProvider);
    final notifier = _ref.read(generationParamsNotifierProvider.notifier);
    if (positive && params.prompt != next.positivePrompt) {
      notifier.updatePrompt(next.positivePrompt);
    }
    if (negative && params.negativePrompt != next.negativePrompt) {
      notifier.updateNegativePrompt(next.negativePrompt);
    }
    // updatePrompt writes its state in a microtask.
    await Future<void>.delayed(Duration.zero);
  }

  _StoredState? _readStored() {
    final raw = _ref
        .read(localStorageServiceProvider)
        .getSetting<String>(StorageKeys.promptGroupEditorState);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final snapshot = PromptGroupSnapshot.fromJson(decoded);
      if (snapshot == null) return null;
      return _StoredState(
        snapshot: snapshot,
        positivePrompt: decoded['positivePrompt'],
        negativePrompt: decoded['negativePrompt'],
      );
    } on FormatException {
      return null;
    }
  }

  /// Partitions read back from older states may lack ids; positional ids keep
  /// them addressable until the editor adopts them.
  static List<PromptGroupSectionSnapshot> _withIds(
    List<PromptGroupSectionSnapshot> sections,
    String prefix,
  ) => PromptSectionEdits.withIds(sections, prefix);
}

class _StoredState {
  const _StoredState({
    required this.snapshot,
    required this.positivePrompt,
    required this.negativePrompt,
  });

  final PromptGroupSnapshot snapshot;

  /// The editor text saved with the partitions; the editor itself only
  /// restores them while this still equals the generation prompt.
  final Object? positivePrompt;
  final Object? negativePrompt;
}

/// The section fields the agent sees; collapse state belongs to the editor.
List<Map<String, Object?>> promptSectionsJson(
  Iterable<PromptGroupSectionSnapshot> sections, {
  String? Function(String fixedTagId)? fixedTagName,
}) => [
  for (final section in sections)
    {
      'id': section.id,
      'text': section.text,
      'enabled': section.enabled,
      if (section.fixedTagId case final fixedTagId?) ...{
        'fixed_tag_id': fixedTagId,
        if (fixedTagName?.call(fixedTagId) case final name?)
          'fixed_tag_name': name,
        'keep_in_main': section.keepInMain,
      },
    },
];

/// Pure edits on one side's partitions. Each returns a new list or throws
/// [PromptSectionEditException].
abstract final class PromptSectionEdits {
  static const int maxSections = 64;

  static int _idCounter = 0;

  static String newId() {
    _idCounter++;
    return 'agent_${DateTime.now().microsecondsSinceEpoch}_$_idCounter';
  }

  static int indexOf(List<PromptGroupSectionSnapshot> sections, String id) =>
      sections.indexWhere((section) => section.id == id);

  /// Sections read back from older states may lack ids; positional ids keep
  /// them addressable until the editor adopts them.
  static List<PromptGroupSectionSnapshot> withIds(
    List<PromptGroupSectionSnapshot> sections,
    String prefix,
  ) => [
    for (var index = 0; index < sections.length; index++)
      sections[index].id.trim().isNotEmpty
          ? sections[index]
          : PromptGroupSectionSnapshot(
              id: '$prefix-${index + 1}',
              text: sections[index].text,
              enabled: sections[index].enabled,
              collapsed: sections[index].collapsed,
              fixedTagId: sections[index].fixedTagId,
              keepInMain: sections[index].keepInMain,
            ),
  ];

  static List<PromptGroupSectionSnapshot> add(
    List<PromptGroupSectionSnapshot> sections, {
    required PromptGroupSectionSnapshot section,
    int? index,
  }) {
    if (sections.length >= maxSections) {
      throw const PromptSectionEditException(
        'too_many_sections',
        'A prompt holds at most $maxSections sections.',
      );
    }
    final target = (index ?? sections.length).clamp(0, sections.length);
    return [...sections]..insert(target, section);
  }

  /// A fixed-tag section follows its tag, so its text cannot be rewritten;
  /// [keepInMain] applies to fixed-tag sections only.
  static List<PromptGroupSectionSnapshot> update(
    List<PromptGroupSectionSnapshot> sections,
    String id, {
    String? text,
    bool? enabled,
    bool? keepInMain,
  }) {
    final index = _require(sections, id);
    final current = sections[index];
    final fixedTagId = current.fixedTagId;
    if (fixedTagId != null && text != null && text != current.text) {
      throw PromptSectionEditException(
        'fixed_tag_section',
        'Section "$id" shows fixed tag $fixedTagId and follows its content. '
            'Change the tag with update_fixed_tag, or remove this section and '
            'add a text section instead.',
      );
    }
    if (fixedTagId == null && keepInMain != null) {
      throw PromptSectionEditException(
        'invalid_operations',
        'keep_in_main applies only to fixed-tag sections; "$id" is text.',
      );
    }
    return [...sections]
      ..[index] = PromptGroupSectionSnapshot(
        id: current.id,
        text: text ?? current.text,
        enabled: enabled ?? current.enabled,
        collapsed: current.collapsed,
        fixedTagId: fixedTagId,
        keepInMain: keepInMain ?? current.keepInMain,
      );
  }

  static List<PromptGroupSectionSnapshot> move(
    List<PromptGroupSectionSnapshot> sections,
    String id,
    int index,
  ) {
    final from = _require(sections, id);
    final next = [...sections];
    final section = next.removeAt(from);
    next.insert(index.clamp(0, next.length), section);
    return next;
  }

  static List<PromptGroupSectionSnapshot> remove(
    List<PromptGroupSectionSnapshot> sections,
    String id,
  ) {
    final index = _require(sections, id);
    final next = [...sections]..removeAt(index);
    // The editor always keeps one partition to type into.
    return next.isEmpty
        ? [PromptGroupSectionSnapshot(id: newId(), text: '')]
        : next;
  }

  /// Replaces every enabled text partition with one holding [text]; disabled
  /// partitions are not part of the prompt and stay where they are, and so
  /// do fixed-tag sections, which reference a tag rather than hold text.
  static List<PromptGroupSectionSnapshot> replaceEnabled(
    List<PromptGroupSectionSnapshot> sections,
    String text,
  ) {
    bool replaced(PromptGroupSectionSnapshot section) =>
        section.enabled && section.fixedTagId == null;
    final firstReplaced = sections.indexWhere(replaced);
    final kept = [
      for (final section in sections)
        if (!replaced(section)) section,
    ];
    final insertAt = firstReplaced < 0
        ? kept.length
        : sections.take(firstReplaced).where((s) => !replaced(s)).length;
    return kept
      ..insert(insertAt, PromptGroupSectionSnapshot(id: newId(), text: text));
  }

  static int _require(List<PromptGroupSectionSnapshot> sections, String id) {
    final index = indexOf(sections, id);
    if (index < 0) {
      throw PromptSectionEditException(
        'section_not_found',
        'No prompt section has id "$id". Call get_prompt_state for the '
            'current section ids.',
      );
    }
    return index;
  }
}

class PromptSectionEditException implements Exception {
  const PromptSectionEditException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}
