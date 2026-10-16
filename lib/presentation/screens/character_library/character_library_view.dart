import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/localization_extension.dart';
import '../../../data/models/character/character_library_entry.dart';
import '../../../data/models/fixed_tag/fixed_tag_entry.dart';
import '../../../data/models/gallery/prompt_group_snapshot.dart';
import '../../providers/character_library_provider.dart';
import '../../providers/fixed_tags_provider.dart';
import 'character_library_actions.dart';
import 'character_library_row.dart';

enum CharacterLibrarySort { recent, used, name }

/// The character library as an index: favorites first, then one group per
/// category, each row opening in place. A selection mode adds several
/// characters to the character bar at once.
class CharacterLibraryView extends ConsumerStatefulWidget {
  const CharacterLibraryView({super.key});

  @override
  ConsumerState<CharacterLibraryView> createState() =>
      _CharacterLibraryViewState();
}

class _CharacterLibraryViewState extends ConsumerState<CharacterLibraryView> {
  final _search = TextEditingController();
  CharacterLibrarySort _sort = CharacterLibrarySort.recent;
  String? _expanded;
  bool _selecting = false;
  final Set<String> _picked = {};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<CharacterLibraryEntry> _sorted(List<CharacterLibraryEntry> entries) {
    final sorted = [...entries];
    switch (_sort) {
      case CharacterLibrarySort.recent:
        DateTime at(CharacterLibraryEntry entry) =>
            entry.lastUsedAt ?? entry.updatedAt;
        sorted.sort((a, b) => at(b).compareTo(at(a)));
      case CharacterLibrarySort.used:
        sorted.sort((a, b) => b.useCount.compareTo(a.useCount));
      case CharacterLibrarySort.name:
        sorted.sort((a, b) => a.name.compareTo(b.name));
    }
    return sorted;
  }

  bool _matches(
    CharacterLibraryEntry entry,
    String query,
    Map<String, FixedTagEntry> fixedTags,
  ) {
    if (query.isEmpty) return true;
    bool has(String text) => text.toLowerCase().contains(query);
    return has(entry.name) ||
        has(entry.category) ||
        [...entry.positiveSections, ...entry.negativeSections].any(
          (section) =>
              has(section.text) ||
              (section.fixedTagId != null &&
                  has(fixedTags[section.fixedTagId]?.displayName ?? '')),
        );
  }

  void _toggleSection(
    CharacterLibraryEntry entry,
    bool negative,
    String sectionId,
  ) {
    List<PromptGroupSectionSnapshot> flip(
      List<PromptGroupSectionSnapshot> sections,
    ) => [
      for (final section in sections)
        section.id == sectionId
            ? PromptGroupSectionSnapshot(
                id: section.id,
                text: section.text,
                enabled: !section.enabled,
                collapsed: section.collapsed,
                fixedTagId: section.fixedTagId,
                keepInMain: section.keepInMain,
              )
            : section,
    ];
    final current = ref.read(characterLibraryProvider.notifier).byId(entry.id);
    if (current == null) return;
    ref
        .read(characterLibraryProvider.notifier)
        .update(
          negative
              ? current.copyWith(
                  negativeSections: flip(current.negativeSections),
                )
              : current.copyWith(
                  positiveSections: flip(current.positiveSections),
                ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final library = ref.watch(characterLibraryProvider);
    final fixedTags = {
      for (final entry in ref.watch(
        fixedTagsNotifierProvider.select((state) => state.entries),
      ))
        entry.id: entry,
    };
    String? content(String id) => fixedTags[id]?.weightedContent;
    final query = _search.text.trim().toLowerCase();
    final visible = _sorted([
      for (final entry in library)
        if (_matches(entry, query, fixedTags)) entry.resolveFixedTags(content),
    ]);
    final groups = <(String, List<CharacterLibraryEntry>)>[];
    final favorites = visible.where((entry) => entry.favorite).toList();
    if (query.isEmpty && favorites.isNotEmpty) {
      groups.add((l10n.characterLibrary_groupFavorites, favorites));
    }
    final rest = query.isEmpty
        ? visible.where((entry) => !entry.favorite).toList()
        : visible;
    final categories = {for (final entry in rest) entry.category}.toList()
      ..sort((a, b) => a.isEmpty ? 1 : (b.isEmpty ? -1 : a.compareTo(b)));
    for (final category in categories) {
      groups.add((
        category.isEmpty ? l10n.characterLibrary_uncategorized : category,
        [
          for (final entry in rest)
            if (entry.category == category) entry,
        ],
      ));
    }

    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              count: library.length,
              selecting: _selecting,
              onToggleSelect: () => setState(() {
                _selecting = !_selecting;
                _picked.clear();
              }),
              onCreate: () => CharacterLibraryActions.create(context, ref),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: TextField(
                key: const ValueKey('character_library_search'),
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: l10n.characterLibrary_searchHint,
                  prefixIcon: const Icon(Icons.search_rounded),
                  isDense: true,
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            _SortRow(
              sort: _sort,
              onChanged: (sort) => setState(() => _sort = sort),
            ),
            Expanded(
              child: library.isEmpty
                  ? _Empty(
                      onCreate: () =>
                          CharacterLibraryActions.create(context, ref),
                    )
                  : visible.isEmpty
                  ? Center(child: Text(l10n.characterLibrary_noMatch))
                  : ListView(
                      key: const ValueKey('character_library_list'),
                      padding: EdgeInsets.only(bottom: _selecting ? 96 : 16),
                      children: [
                        for (final (title, entries) in groups) ...[
                          _GroupTitle(title: title, count: entries.length),
                          for (final entry in entries)
                            CharacterLibraryRow(
                              key: ValueKey('character_library_${entry.id}'),
                              entry: entry,
                              fixedTags: fixedTags,
                              expanded: _expanded == entry.id,
                              selecting: _selecting,
                              picked: _picked.contains(entry.id),
                              onTap: () => setState(() {
                                if (_selecting) {
                                  _picked.contains(entry.id)
                                      ? _picked.remove(entry.id)
                                      : _picked.add(entry.id);
                                } else {
                                  _expanded = _expanded == entry.id
                                      ? null
                                      : entry.id;
                                }
                              }),
                              onToggleSection: (negative, id) =>
                                  _toggleSection(entry, negative, id),
                              onAdd: () => CharacterLibraryActions.addToPanel(
                                context,
                                ref,
                                [entry],
                              ),
                              onEdit: () => CharacterLibraryActions.openEditor(
                                context,
                                entry.id,
                              ),
                              onToggleFavorite: () => ref
                                  .read(characterLibraryProvider.notifier)
                                  .toggleFavorite(entry.id),
                              onDuplicate: () =>
                                  CharacterLibraryActions.duplicate(
                                    context,
                                    ref,
                                    entry,
                                  ),
                              onDelete: () => CharacterLibraryActions.delete(
                                context,
                                ref,
                                entry,
                              ),
                            ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
        if (_selecting && _picked.isNotEmpty)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: SafeArea(
              top: false,
              child: _SelectionBar(
                count: _picked.length,
                onAdd: () {
                  final picked = [
                    for (final entry in visible)
                      if (_picked.contains(entry.id)) entry,
                  ];
                  CharacterLibraryActions.addToPanel(context, ref, picked);
                  setState(() {
                    _selecting = false;
                    _picked.clear();
                  });
                },
              ),
            ),
          ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.count,
    required this.selecting,
    required this.onToggleSelect,
    required this.onCreate,
  });

  final int count;
  final bool selecting;
  final VoidCallback onToggleSelect;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l10n.characterLibrary_count(count),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (count > 0)
            selecting
                ? FilledButton(
                    key: const ValueKey('character_library_select'),
                    onPressed: onToggleSelect,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 44),
                    ),
                    child: Text(l10n.common_done),
                  )
                : TextButton(
                    key: const ValueKey('character_library_select'),
                    onPressed: onToggleSelect,
                    style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
                    child: Text(l10n.common_multiSelect),
                  ),
          IconButton.filled(
            key: const ValueKey('character_library_create'),
            onPressed: onCreate,
            tooltip: l10n.characterLibrary_new,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
    );
  }
}

class _SortRow extends StatelessWidget {
  const _SortRow({required this.sort, required this.onChanged});

  final CharacterLibrarySort sort;
  final ValueChanged<CharacterLibrarySort> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final labels = {
      CharacterLibrarySort.recent: l10n.characterLibrary_sortRecent,
      CharacterLibrarySort.used: l10n.characterLibrary_sortUsed,
      CharacterLibrarySort.name: l10n.characterLibrary_sortName,
    };
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          for (final MapEntry(key: value, value: label) in labels.entries)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                key: ValueKey('character_library_sort_${value.name}'),
                label: Text(label),
                selected: sort == value,
                showCheckmark: false,
                onSelected: (_) => onChanged(value),
              ),
            ),
        ],
      ),
    );
  }
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Text(
        '$title  $count',
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({required this.count, required this.onAdd});

  final int count;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = context.l10n;
    return Material(
      color: colors.inverseSurface,
      borderRadius: BorderRadius.circular(18),
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                l10n.characterLibrary_selectedCount(count),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colors.onInverseSurface,
                ),
              ),
            ),
            FilledButton(
              key: const ValueKey('character_library_add_selected'),
              onPressed: onAdd,
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              child: Text(l10n.characterLibrary_addSelected),
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.people_outline_rounded,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.characterLibrary_empty,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.characterLibrary_emptyHint,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add_rounded),
              label: Text(l10n.characterLibrary_new),
            ),
          ],
        ),
      ),
    );
  }
}
