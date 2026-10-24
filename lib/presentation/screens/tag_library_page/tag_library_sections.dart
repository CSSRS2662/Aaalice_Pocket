import 'package:flutter/foundation.dart';

import '../../../data/models/tag_library/tag_library_category.dart';
import '../../../data/models/tag_library/tag_library_entry.dart';
import '../../providers/tag_library_page_provider.dart';

/// What a headed run of entries in the library list stands for.
enum TagLibrarySectionKind {
  /// Favorites pulled out to the top of 全部.
  favorites,

  /// A group, with the entries of its subgroups when they are not shown as
  /// sections of their own.
  group,

  /// Entries outside any group the library still has.
  ungrouped,

  /// Search results: one run, ranked, without a header.
  results,
}

@immutable
class TagLibrarySection {
  const TagLibrarySection({
    required this.kind,
    required this.entries,
    this.category,
  });

  final TagLibrarySectionKind kind;

  /// The group for [TagLibrarySectionKind.group].
  final TagLibraryCategory? category;
  final List<TagLibraryEntry> entries;

  String get key => switch (kind) {
    TagLibrarySectionKind.group => 'group-${category!.id}',
    _ => kind.name,
  };
}

/// Splits [entries], already filtered and sorted for the page, into the
/// sections the list shows.
///
/// - A search shows one ranked run.
/// - 全部 shows favorites first when [favoritesFirst], then each top-level
///   group with its subgroups' entries, then ungrouped entries.
/// - A group shows its own entries, then one section per subgroup.
/// - 收藏 shows the favorites under their top-level groups.
List<TagLibrarySection> buildTagLibrarySections({
  required List<TagLibraryEntry> entries,
  required List<TagLibraryCategory> categories,
  required String? selectedCategoryId,
  required bool favoritesFirst,
  required bool searching,
}) {
  if (searching) {
    return [
      if (entries.isNotEmpty)
        TagLibrarySection(
          kind: TagLibrarySectionKind.results,
          entries: entries,
        ),
    ];
  }
  final tree = TagLibraryGroupTree(categories);
  final selected = tree.byId(selectedCategoryId);
  if (selected != null) {
    return [
      _group(selected, entries.where((e) => e.categoryId == selected.id)),
      for (final child in tree.childrenOf(selected.id))
        _group(
          child,
          entries.where((e) => tree.isWithin(e.categoryId, child.id)),
        ),
    ].where((section) => section.entries.isNotEmpty).toList();
  }

  final pullFavorites =
      favoritesFirst && selectedCategoryId != tagLibraryFavoritesFilter;
  final favorites = pullFavorites
      ? entries.where((entry) => entry.isFavorite).toList()
      : const <TagLibraryEntry>[];
  final rest = pullFavorites
      ? entries.where((entry) => !entry.isFavorite).toList()
      : entries;
  return [
    if (favorites.isNotEmpty)
      TagLibrarySection(
        kind: TagLibrarySectionKind.favorites,
        entries: favorites,
      ),
    for (final root in tree.roots)
      _group(root, rest.where((e) => tree.isWithin(e.categoryId, root.id))),
    TagLibrarySection(
      kind: TagLibrarySectionKind.ungrouped,
      entries: [
        for (final entry in rest)
          if (tree.byId(entry.categoryId) == null) entry,
      ],
    ),
  ].where((section) => section.entries.isNotEmpty).toList();
}

TagLibrarySection _group(
  TagLibraryCategory category,
  Iterable<TagLibraryEntry> entries,
) => TagLibrarySection(
  kind: TagLibrarySectionKind.group,
  category: category,
  entries: entries.toList(growable: false),
);

/// Lookups over the group hierarchy, built once per list.
class TagLibraryGroupTree {
  TagLibraryGroupTree(List<TagLibraryCategory> categories)
    : _byId = {for (final category in categories) category.id: category},
      _children = {} {
    for (final category in categories.sortedByOrder()) {
      _children.putIfAbsent(category.parentId, () => []).add(category);
    }
  }

  final Map<String, TagLibraryCategory> _byId;
  final Map<String?, List<TagLibraryCategory>> _children;

  List<TagLibraryCategory> get roots => childrenOf(null);

  TagLibraryCategory? byId(String? id) => id == null ? null : _byId[id];

  List<TagLibraryCategory> childrenOf(String? id) => _children[id] ?? const [];

  /// The top-level group that [id] belongs to.
  TagLibraryCategory? rootOf(String? id) {
    var current = byId(id);
    final seen = <String>{};
    while (current != null &&
        current.parentId != null &&
        seen.add(current.id)) {
      final parent = byId(current.parentId);
      if (parent == null) break;
      current = parent;
    }
    return current;
  }

  /// Whether group [id] is [ancestorId] or lies under it.
  bool isWithin(String? id, String ancestorId) {
    var current = byId(id);
    final seen = <String>{};
    while (current != null && seen.add(current.id)) {
      if (current.id == ancestorId) return true;
      current = byId(current.parentId);
    }
    return false;
  }

  /// Group names from the top down to [id], such as 人物 › 发型.
  List<String> pathOf(String? id) {
    final names = <String>[];
    var current = byId(id);
    final seen = <String>{};
    while (current != null && seen.add(current.id)) {
      names.insert(0, current.displayName);
      current = byId(current.parentId);
    }
    return names;
  }
}
