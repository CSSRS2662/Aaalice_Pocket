import 'package:flutter/material.dart';

import '../../../../data/models/gallery/prompt_group_snapshot.dart';
import '../../../../data/services/prompt_group/character_section_store.dart';
import '../../../widgets/prompt/nai_syntax_controller.dart';

enum PromptEditorMode { single, grouped }

/// What [PromptGroupCollection.remove] took out, enough to put it back.
typedef RemovedPromptGroup = ({int index, PromptGroupSectionSnapshot snapshot});

/// One user-defined prompt partition.
///
/// Partitions deliberately have no title or category: their meaning belongs to
/// the user, while the editor only owns ordering and inclusion in the request.
///
/// A section can instead show a fixed tag ([fixedTagId]): its text then
/// follows the tag, see [PromptGroupCollection.resolveFixedTags].
class PromptGroupSection {
  PromptGroupSection({
    required this.id,
    required String text,
    this.enabled = true,
    this.collapsed = false,
    this.fixedTagId,
    this.keepInMain = false,
  }) : controller = NaiSyntaxController(text: text),
       focusNode = FocusNode();

  PromptGroupSection.fromSnapshot(
    PromptGroupSectionSnapshot snapshot, {
    String? id,
  }) : this(
         id: id ?? snapshot.id,
         text: snapshot.text,
         enabled: snapshot.enabled,
         collapsed: snapshot.collapsed,
         fixedTagId: snapshot.fixedTagId,
         keepInMain: snapshot.keepInMain,
       );

  final String id;
  final NaiSyntaxController controller;
  final FocusNode focusNode;
  bool enabled;
  bool collapsed;

  /// The fixed tag this section shows, or null for a section of its own text.
  String? fixedTagId;

  /// See [PromptGroupSectionSnapshot.keepInMain].
  bool keepInMain;

  bool get isFixedTag => fixedTagId != null;

  Map<String, Object?> toJson() => toSnapshot().toJson();

  PromptGroupSectionSnapshot toSnapshot() => PromptGroupSectionSnapshot(
    id: id,
    text: controller.text,
    enabled: enabled,
    collapsed: collapsed,
    fixedTagId: fixedTagId,
    keepInMain: keepInMain,
  );

  void dispose() {
    controller.dispose();
    focusNode.dispose();
  }
}

class PromptGroupCollection extends ChangeNotifier {
  PromptGroupCollection.single(String text) {
    _insert(PromptGroupSection(id: _newId(), text: text));
  }

  PromptGroupCollection.fromJson(Object? raw, {required String fallbackText}) {
    if (raw is List) {
      for (final value in raw.take(64)) {
        final snapshot = PromptGroupSectionSnapshot.fromJson(value);
        if (snapshot == null) continue;
        _insert(
          PromptGroupSection.fromSnapshot(
            snapshot,
            id: snapshot.id.trim().isEmpty ? _newId() : snapshot.id,
          ),
        );
      }
    }
    if (_sections.isEmpty) {
      _insert(PromptGroupSection(id: _newId(), text: fallbackText));
    }
  }

  static int _nextId = 0;
  final List<PromptGroupSection> _sections = [];

  /// A section the editor UI should open next; set when one is added.
  String? _editRequest;

  List<PromptGroupSection> get sections => List.unmodifiable(_sections);

  String get effectiveText => joinPromptSections(
    _sections
        .where((section) => section.enabled)
        .map((section) => section.controller.text),
  );

  /// Whether the included sections still add up to [prompt], ignoring the
  /// separators at its ends that joining drops.
  bool matchesPrompt(String prompt) =>
      effectiveText == joinPromptSections([prompt]);

  bool get hasFixedTags => _sections.any((section) => section.isFixedTag);

  /// Brings fixed-tag sections up to date: [contentOf] gives a tag's content
  /// as it goes into a prompt, or null when the tag is gone, which keeps the
  /// last content. Returns whether any text changed.
  bool resolveFixedTags(String? Function(String fixedTagId) contentOf) {
    var changed = false;
    for (final section in _sections) {
      final id = section.fixedTagId;
      if (id == null) continue;
      final content = contentOf(id);
      if (content == null || content == section.controller.text) continue;
      section.controller.text = content;
      changed = true;
    }
    if (changed) notifyListeners();
    return changed;
  }

  /// Adds a section showing a fixed tag, at the start where prefix tags go
  /// or at the end, and returns it.
  PromptGroupSection addFixedTag(
    String fixedTagId,
    String content, {
    bool atStart = true,
  }) {
    final section = PromptGroupSection(
      id: _newId(),
      text: content,
      fixedTagId: fixedTagId,
    );
    _insert(section, atStart ? 0 : null);
    notifyListeners();
    return section;
  }

  /// Makes a fixed-tag section an ordinary one holding its current text.
  void detachFixedTag(String id) {
    final section = _find(id);
    if (section == null || !section.isFixedTag) return;
    section.fixedTagId = null;
    section.keepInMain = false;
    notifyListeners();
  }

  void setKeepInMain(String id, bool keep) {
    final section = _find(id);
    if (section == null || !section.isFixedTag || section.keepInMain == keep) {
      return;
    }
    section.keepInMain = keep;
    notifyListeners();
  }

  void _insert(PromptGroupSection section, [int? index]) {
    if (index == null) {
      _sections.add(section);
    } else {
      _sections.insert(index, section);
    }
  }

  static String _newId() {
    _nextId++;
    return '${DateTime.now().microsecondsSinceEpoch}_$_nextId';
  }

  /// Adds an empty section at the end and asks the editor UI to open it;
  /// an editor that is already open and moves to it itself passes
  /// [requestEdit] false.
  PromptGroupSection add({bool requestEdit = true}) {
    final section = PromptGroupSection(id: _newId(), text: '');
    _insert(section);
    if (requestEdit) _editRequest = section.id;
    notifyListeners();
    return section;
  }

  /// Adds [text] as a new section at the end, or fills the only section when
  /// it is still empty, without opening an editor.
  PromptGroupSection addText(String text) {
    final blank =
        _sections.length == 1 &&
            !_sections.single.isFixedTag &&
            _sections.single.controller.text.trim().isEmpty
        ? _sections.single
        : null;
    if (blank != null) {
      blank
        ..controller.text = text
        ..enabled = true;
      notifyListeners();
      return blank;
    }
    final section = PromptGroupSection(id: _newId(), text: text);
    _insert(section);
    notifyListeners();
    return section;
  }

  /// Returns and clears the section the editor UI should open, if any.
  String? takeEditRequest() {
    final id = _editRequest;
    _editRequest = null;
    return id;
  }

  PromptGroupSection? sectionById(String id) => _find(id);

  int indexOf(String id) => _sections.indexWhere((section) => section.id == id);

  RemovedPromptGroup? remove(String id) {
    final index = indexOf(id);
    if (index < 0) return null;
    final removed = _sections.removeAt(index);
    final snapshot = removed.toSnapshot();
    removed.dispose();
    notifyListeners();
    return (index: index, snapshot: snapshot);
  }

  /// Undoes [remove], keeping the section's id and position.
  void restoreRemoved(RemovedPromptGroup removed) {
    if (_find(removed.snapshot.id) != null) return;
    _insert(
      PromptGroupSection.fromSnapshot(removed.snapshot),
      removed.index.clamp(0, _sections.length).toInt(),
    );
    notifyListeners();
  }

  /// Inserts a copy right after the section and returns it.
  PromptGroupSection? duplicate(String id) {
    final index = indexOf(id);
    if (index < 0) return null;
    final source = _sections[index];
    final copy = PromptGroupSection(
      id: _newId(),
      text: source.controller.text,
      enabled: source.enabled,
      fixedTagId: source.fixedTagId,
      keepInMain: source.keepInMain,
    );
    _insert(copy, index + 1);
    notifyListeners();
    return copy;
  }

  /// Moves a section so it ends up at [toIndex] in the new order.
  void move(String id, int toIndex) {
    final from = indexOf(id);
    if (from < 0) return;
    final target = toIndex.clamp(0, _sections.length - 1).toInt();
    if (target == from) return;
    _sections.insert(target, _sections.removeAt(from));
    notifyListeners();
  }

  void setEnabled(String id, bool enabled) {
    final section = _find(id);
    if (section == null || section.enabled == enabled) return;
    section.enabled = enabled;
    notifyListeners();
  }

  void toggleCollapsed(String id) {
    final section = _find(id);
    if (section == null) return;
    section.collapsed = !section.collapsed;
    notifyListeners();
  }

  void reorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _sections.length) return;
    var target = newIndex;
    if (target > oldIndex) target--;
    target = target.clamp(0, _sections.length - 1).toInt();
    if (target == oldIndex) return;
    final section = _sections.removeAt(oldIndex);
    _sections.insert(target, section);
    notifyListeners();
  }

  void replaceWith(String text) {
    for (final section in _sections) {
      section.dispose();
    }
    _sections.clear();
    _insert(PromptGroupSection(id: _newId(), text: text));
    notifyListeners();
  }

  void restore(Iterable<PromptGroupSectionSnapshot> snapshots) {
    for (final section in _sections) {
      section.dispose();
    }
    _sections.clear();
    for (final snapshot in snapshots.take(64)) {
      _insert(
        PromptGroupSection.fromSnapshot(
          snapshot,
          id: snapshot.id.trim().isEmpty ? _newId() : snapshot.id,
        ),
      );
    }
    if (_sections.isEmpty) {
      _insert(PromptGroupSection(id: _newId(), text: ''));
    }
    notifyListeners();
  }

  void configureHighlighting({
    required bool enabled,
    required bool numericEmphasisEnabled,
  }) {
    for (final section in _sections) {
      section.controller.highlightEnabled = enabled;
      section.controller.numericEmphasisEnabled = numericEmphasisEnabled;
    }
  }

  List<Map<String, Object?>> toJson() => [
    for (final section in _sections) section.toJson(),
  ];

  List<PromptGroupSectionSnapshot> toSnapshot() => [
    for (final section in _sections) section.toSnapshot(),
  ];

  PromptGroupSection? _find(String id) {
    for (final section in _sections) {
      if (section.id == id) return section;
    }
    return null;
  }

  @override
  void dispose() {
    for (final section in _sections) {
      section.dispose();
    }
    _sections.clear();
    super.dispose();
  }
}

@visibleForTesting
String joinPromptSections(Iterable<String> values) =>
    CharacterSectionStore.join(values);
