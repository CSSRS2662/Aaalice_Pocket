import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/models/tag_library/tag_library_category.dart';
import 'package:nai_launcher/data/models/tag_library/tag_library_entry.dart';
import 'package:nai_launcher/presentation/providers/tag_library_page_provider.dart';
import 'package:nai_launcher/presentation/screens/tag_library_page/tag_library_sections.dart';

TagLibraryCategory _category(String id, {String? parent, int order = 0}) =>
    TagLibraryCategory(
      id: id,
      name: id,
      parentId: parent,
      sortOrder: order,
      createdAt: DateTime(2026),
    );

TagLibraryEntry _entry(String id, String? category, {bool favorite = false}) =>
    TagLibraryEntry(
      id: id,
      name: id,
      content: id,
      categoryId: category,
      isFavorite: favorite,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

void main() {
  final categories = [
    _category('person'),
    _category('hair', parent: 'person'),
    _category('eyes', parent: 'person', order: 1),
    _category('scene', order: 1),
  ];
  final entries = [
    _entry('fav', 'scene', favorite: true),
    _entry('girl', 'person'),
    _entry('twintails', 'hair'),
    _entry('heterochromia', 'eyes'),
    _entry('rooftop', 'scene'),
    _entry('loose', null),
    _entry('stale', 'deleted-group'),
  ];

  /// Each section as `kind:group:entry,entry`.
  List<String> describe(List<TagLibrarySection> sections) => [
    for (final section in sections)
      '${section.kind.name}:${section.category?.id ?? ''}:'
          '${section.entries.map((entry) => entry.id).join(',')}',
  ];

  test('全部 pulls favorites out, then top-level groups, then ungrouped', () {
    final sections = buildTagLibrarySections(
      entries: entries,
      categories: categories,
      selectedCategoryId: null,
      favoritesFirst: true,
      searching: false,
    );

    expect(describe(sections), [
      'favorites::fav',
      'group:person:girl,twintails,heterochromia',
      'group:scene:rooftop',
      'ungrouped::loose,stale',
    ]);
  });

  test('without favorites first they stay in their groups', () {
    final sections = buildTagLibrarySections(
      entries: entries,
      categories: categories,
      selectedCategoryId: null,
      favoritesFirst: false,
      searching: false,
    );

    expect(sections.first.kind, TagLibrarySectionKind.group);
    expect(
      sections
          .firstWhere((s) => s.category?.id == 'scene')
          .entries
          .map((e) => e.id),
      ['fav', 'rooftop'],
    );
  });

  test('a group shows its own entries then one section per subgroup', () {
    final sections = buildTagLibrarySections(
      entries: entries,
      categories: categories,
      selectedCategoryId: 'person',
      favoritesFirst: true,
      searching: false,
    );

    expect(describe(sections), [
      'group:person:girl',
      'group:hair:twintails',
      'group:eyes:heterochromia',
    ]);
  });

  test('收藏 shows favorites under their groups', () {
    final sections = buildTagLibrarySections(
      entries: [entries.first],
      categories: categories,
      selectedCategoryId: tagLibraryFavoritesFilter,
      favoritesFirst: true,
      searching: false,
    );

    expect(describe(sections), ['group:scene:fav']);
  });

  test('a search is one ranked run, and nothing gives no sections', () {
    final results = buildTagLibrarySections(
      entries: entries.take(2).toList(),
      categories: categories,
      selectedCategoryId: null,
      favoritesFirst: true,
      searching: true,
    );
    expect(describe(results), ['results::fav,girl']);
    expect(
      buildTagLibrarySections(
        entries: const [],
        categories: categories,
        selectedCategoryId: null,
        favoritesFirst: true,
        searching: true,
      ),
      isEmpty,
    );
  });

  test('group tree finds roots, membership and paths', () {
    final tree = TagLibraryGroupTree(categories);

    expect(tree.roots.map((c) => c.id), ['person', 'scene']);
    expect(tree.rootOf('eyes')?.id, 'person');
    expect(tree.isWithin('hair', 'person'), isTrue);
    expect(tree.isWithin('scene', 'person'), isFalse);
    expect(tree.pathOf('hair'), ['person', 'hair']);
  });
}
