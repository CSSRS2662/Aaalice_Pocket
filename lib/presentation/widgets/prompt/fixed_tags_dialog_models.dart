import 'package:flutter/material.dart';

import '../../../core/utils/usage_frecency.dart';
import '../../../data/models/fixed_tag/fixed_tag_entry.dart';
import '../../../data/models/fixed_tag/fixed_tag_prompt_type.dart';
import '../../../data/models/tag_library/tag_library_category.dart';
import '../../../data/models/tag_library/tag_library_entry.dart';
import '../../providers/fixed_tags_provider.dart';
import '../../providers/fixed_tags_sort_provider.dart';
import '../../providers/name_sort_key_provider.dart';
import 'fixed_tag_category_sections.dart';
import 'fixed_tags_ordering.dart';

class FixedTagsDialogViewData {
  FixedTagsDialogViewData({
    required this.state,
    required this.libraryEntries,
    this.libraryCategories = const [],
    this.sort = const FixedTagsSortPrefs(),
    this.usage = const {},
    this.nameSortKey,
  });

  final FixedTagsState state;
  final List<TagLibraryEntry> libraryEntries;

  /// Groups the grid the same way as the sidebar.
  final List<TagLibraryCategory> libraryCategories;
  final FixedTagsSortPrefs sort;

  /// How much each tag has been used lately, by tag id.
  final Map<String, UsageFrecency> usage;
  final NameSortKey? nameSortKey;

  late final Map<String, TagLibraryEntry> _libraryById = {
    for (final entry in libraryEntries) entry.id: entry,
  };

  /// The library entry a tag came from, if it still exists.
  TagLibraryEntry? libraryEntryOf(FixedTagEntry entry) {
    final id = entry.sourceEntryId;
    return id == null ? null : _libraryById[id];
  }

  /// The group a tag shows under: its library entry's, else its own.
  String? categoryOf(FixedTagEntry entry) =>
      effectiveFixedTagCategoryId(entry, _libraryById);

  List<FixedTagEntry> entriesFor(
    FixedTagPromptType promptType,
    String query, {
    bool enabledOnly = false,
  }) {
    final normalized = query.trim().toLowerCase();
    final matching =
        (promptType == FixedTagPromptType.positive
                ? state.positiveEntries
                : state.negativeEntries)
            .where((entry) {
              if (enabledOnly && !entry.enabled) return false;
              return normalized.isEmpty ||
                  entry.name.toLowerCase().contains(normalized) ||
                  entry.content.toLowerCase().contains(normalized);
            })
            .toList(growable: false);
    return orderFixedTags(
      matching,
      prefs: sort,
      usage: usage,
      nameSortKey: nameSortKey,
    );
  }

  /// [entries] under their groups for the custom order, in display order.
  List<FixedTagCategorySection> sectionsOf(List<FixedTagEntry> entries) =>
      groupFixedTagsByCategory(
        entries,
        libraryCategories,
        categoryOf: categoryOf,
      );
}

@immutable
class FixedTagsDialogCommands {
  const FixedTagsDialogCommands({
    required this.close,
    required this.openLibraryPage,
    required this.toggleNegativePanel,
    required this.undo,
    required this.redo,
    required this.setAllEnabled,
    required this.setPromptTypeEnabled,
    required this.toggleEntry,
    required this.showDetails,
    required this.togglePosition,
    required this.setWeight,
    required this.moveToCategory,
    required this.reorder,
    required this.editEntry,
    required this.deleteEntry,
    required this.clearAll,
    required this.pickFromLibrary,
    required this.showLinkManager,
    required this.showSortOptions,
  });

  final VoidCallback close;
  final VoidCallback openLibraryPage;
  final VoidCallback toggleNegativePanel;
  final VoidCallback undo;
  final VoidCallback redo;
  final ValueChanged<bool> setAllEnabled;
  final void Function(FixedTagPromptType promptType, bool enabled)
  setPromptTypeEnabled;
  final ValueChanged<FixedTagEntry> toggleEntry;
  final ValueChanged<FixedTagEntry> showDetails;
  final ValueChanged<FixedTagEntry> togglePosition;
  final void Function(FixedTagEntry entry, double weight) setWeight;

  /// Lets the user pick a group; a linked tag moves its library entry too.
  final ValueChanged<FixedTagEntry> moveToCategory;
  final void Function(FixedTagPromptType promptType, int oldIndex, int newIndex)
  reorder;
  final void Function(
    FixedTagEntry? entry,
    FixedTagPromptType initialPromptType,
  )
  editEntry;
  final ValueChanged<FixedTagEntry> deleteEntry;
  final VoidCallback clearAll;
  final ValueChanged<FixedTagPromptType> pickFromLibrary;
  final ValueChanged<FixedTagEntry> showLinkManager;
  final VoidCallback showSortOptions;
}
