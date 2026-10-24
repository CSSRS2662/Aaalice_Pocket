import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nai_launcher/core/storage/local_storage_service.dart';
import 'package:nai_launcher/data/models/fixed_tag/fixed_tag_entry.dart';
import 'package:nai_launcher/data/models/fixed_tag/fixed_tag_link.dart';
import 'package:nai_launcher/data/models/fixed_tag/fixed_tag_prompt_type.dart';
import 'package:nai_launcher/data/models/tag_library/tag_library_category.dart';
import 'package:nai_launcher/data/models/tag_library/tag_library_entry.dart';
import 'package:nai_launcher/presentation/providers/fixed_tags_provider.dart';
import 'package:nai_launcher/presentation/providers/tag_library_page_provider.dart';

import '../../helpers/memory_local_storage.dart';

void main() {
  group('FixedTagsState prompt type filtering', () {
    test('keeps existing positive prefix and suffix assembly unchanged', () {
      final state = FixedTagsState(
        entries: [
          FixedTagEntry.create(
            name: 'prefix',
            content: 'masterpiece',
            position: FixedTagPosition.prefix,
          ),
          FixedTagEntry.create(
            name: 'suffix',
            content: 'cinematic lighting',
            position: FixedTagPosition.suffix,
          ),
        ],
      );

      expect(
        state.applyToPrompt('1girl'),
        'masterpiece, 1girl, cinematic lighting',
      );
    });

    test('preserves user repeats and separate entries with equal content', () {
      final entries = [
        FixedTagEntry.create(
          name: 'first',
          content: 'masterpiece',
          sortOrder: 0,
        ),
        FixedTagEntry.create(
          name: 'second',
          content: 'masterpiece',
          sortOrder: 1,
        ),
      ];
      final state = FixedTagsState(entries: entries);

      expect(
        state.applyToPrompt('masterpiece, portrait, masterpiece'),
        'masterpiece, masterpiece, masterpiece, portrait, masterpiece',
      );
      expect(
        entries.applyToPrompt('masterpiece, portrait, masterpiece'),
        state.applyToPrompt('masterpiece, portrait, masterpiece'),
      );
    });

    test('does not apply negative entries to the positive prompt', () {
      final negativeJson = FixedTagEntry.create(
        name: 'negative',
        content: 'bad hands',
        position: FixedTagPosition.prefix,
      ).toJson()..['promptType'] = 'negative';
      final positiveEntry = FixedTagEntry.create(
        name: 'positive',
        content: 'masterpiece',
        position: FixedTagPosition.prefix,
      );

      final state = FixedTagsState(
        entries: [FixedTagEntry.fromJson(negativeJson), positiveEntry],
      );

      expect(state.applyToPrompt('1girl'), 'masterpiece, 1girl');
      expect(state.enabledPrefixes, [positiveEntry]);
      expect(state.enabledCount, 1);
    });

    test('applies negative entries using prefix body suffix assembly', () {
      final state = FixedTagsState(
        entries: [
          FixedTagEntry.create(
            name: 'positive',
            content: 'masterpiece',
            position: FixedTagPosition.prefix,
          ),
          FixedTagEntry.create(
            name: 'negative-prefix',
            content: 'bad hands',
            position: FixedTagPosition.prefix,
            promptType: FixedTagPromptType.negative,
            sortOrder: 0,
          ),
          FixedTagEntry.create(
            name: 'negative-suffix',
            content: 'text',
            position: FixedTagPosition.suffix,
            promptType: FixedTagPromptType.negative,
            sortOrder: 1,
          ),
        ],
      );

      expect(state.applyToNegativePrompt('lowres'), 'bad hands, lowres, text');
      expect(state.applyToPrompt('1girl'), 'masterpiece, 1girl');
      expect(state.negativeEnabledCount, 2);
    });

    test('tracks link endpoints and mismatch state', () {
      final positive = FixedTagEntry.create(
        name: 'positive',
        content: 'masterpiece',
      );
      final negative = FixedTagEntry.create(
        name: 'negative',
        content: 'bad hands',
        promptType: FixedTagPromptType.negative,
        enabled: false,
      );
      final link = FixedTagLink.create(
        positiveEntryId: positive.id,
        negativeEntryId: negative.id,
      );

      final state = FixedTagsState(
        entries: [positive, negative],
        links: [link],
      );

      expect(state.linkedNegativesOf(positive.id), [negative]);
      expect(state.linkedPositivesOf(negative.id), [positive]);
      expect(state.isMismatched(link), isTrue);
      expect(FixedTagLink.fromJson(link.toJson()).negativeEntryId, negative.id);
    });
  });

  group('FixedTagsNotifier.addEntry identity', () {
    test('is idempotent per source, prompt type, and position', () async {
      final storage = _MockLocalStorageService();
      when(storage.getFixedTagsJson).thenReturn(null);
      when(storage.getFixedTagLinksJson).thenReturn(null);
      when(storage.getFixedTagsNegativePanelExpanded).thenReturn(true);
      when(() => storage.setFixedTagsJson(any())).thenAnswer((_) async {});
      final container = ProviderContainer(
        overrides: [localStorageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(fixedTagsNotifierProvider.notifier);

      final positivePrefix = await notifier.addEntry(
        name: 'source',
        content: 'same',
        sourceEntryId: 'library-entry',
      );
      final repeated = await notifier.addEntry(
        name: 'source again',
        content: 'changed payload from the same import',
        sourceEntryId: 'library-entry',
      );
      final negativePrefix = await notifier.addEntry(
        name: 'negative',
        content: 'same',
        sourceEntryId: 'library-entry',
        promptType: FixedTagPromptType.negative,
      );
      final positiveSuffix = await notifier.addEntry(
        name: 'suffix',
        content: 'same',
        sourceEntryId: 'library-entry',
        position: FixedTagPosition.suffix,
      );

      expect(repeated.id, positivePrefix.id);
      expect(negativePrefix.id, isNot(positivePrefix.id));
      expect(positiveSuffix.id, isNot(positivePrefix.id));
      expect(container.read(fixedTagsNotifierProvider).entries, hasLength(3));
    });

    test('does not merge independent entries by prompt text', () async {
      final storage = _MockLocalStorageService();
      when(storage.getFixedTagsJson).thenReturn(null);
      when(storage.getFixedTagLinksJson).thenReturn(null);
      when(storage.getFixedTagsNegativePanelExpanded).thenReturn(true);
      when(() => storage.setFixedTagsJson(any())).thenAnswer((_) async {});
      final container = ProviderContainer(
        overrides: [localStorageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(fixedTagsNotifierProvider.notifier);

      await notifier.addEntry(name: 'one', content: 'same');
      await notifier.addEntry(name: 'two', content: 'same');

      expect(container.read(fixedTagsNotifierProvider).entries, hasLength(2));
    });
  });

  group('FixedTagsNotifier.updateEntry 同步到词库', () {
    Future<
      ({ProviderContainer container, String libraryId, FixedTagEntry fixed})
    >
    linkedPair() async {
      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(MemoryLocalStorage()),
        ],
      );
      addTearDown(container.dispose);
      final library = await container
          .read(tagLibraryPageNotifierProvider.notifier)
          .addEntry(name: '画风', content: 'watercolor', categoryId: 'style');
      final fixed = await container
          .read(fixedTagsNotifierProvider.notifier)
          .addEntry(
            name: '画风',
            content: 'watercolor',
            sourceEntryId: library.id,
            categoryId: 'style',
          );
      return (container: container, libraryId: library.id, fixed: fixed);
    }

    TagLibraryEntry libraryEntry(ProviderContainer container, String id) =>
        container
            .read(tagLibraryPageNotifierProvider)
            .entries
            .singleWhere((e) => e.id == id);

    test('改了分类时词库条目跟着换分类', () async {
      final (:container, :libraryId, :fixed) = await linkedPair();

      await container
          .read(fixedTagsNotifierProvider.notifier)
          .updateEntry(fixed.copyWith(categoryId: 'artist'));

      expect(libraryEntry(container, libraryId).categoryId, 'artist');
    });

    test('只改内容时不动词库条目的分类', () async {
      final (:container, :libraryId, :fixed) = await linkedPair();

      await container
          .read(fixedTagsNotifierProvider.notifier)
          .updateEntry(fixed.update(content: 'oil painting'));

      final entry = libraryEntry(container, libraryId);
      expect(entry.content, 'oil painting');
      expect(entry.categoryId, 'style');
    });
  });

  group('FixedTagsNotifier.syncFromTagLibrary', () {
    test('按修改前的内容收养未关联的手动固定词并补写 sourceEntryId', () async {
      final storage = _MockLocalStorageService();
      when(storage.getFixedTagsJson).thenReturn(null);
      when(storage.getFixedTagLinksJson).thenReturn(null);
      when(storage.getFixedTagsNegativePanelExpanded).thenReturn(true);
      when(() => storage.setFixedTagsJson(any())).thenAnswer((_) async {});
      final container = ProviderContainer(
        overrides: [localStorageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(fixedTagsNotifierProvider.notifier);

      // 手动敲进去的固定词：没有 sourceEntryId，内容与词库条目当前一致
      final manual = await notifier.addEntry(
        name: '手动固定词',
        content: ' masterpiece ',
      );
      // 内容不同的另一条，不应被牵连
      final unrelated = await notifier.addEntry(
        name: '无关',
        content: 'best quality',
      );

      await notifier.syncFromTagLibrary(
        TagLibraryEntry(
          id: 'library-1',
          name: '改名后的词条',
          content: 'masterpiece, ultra detailed',
          categoryId: 'lib-category',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
        previousContent: 'masterpiece',
      );

      final entries = container.read(fixedTagsNotifierProvider).entries;
      final adopted = entries.firstWhere((e) => e.id == manual.id);
      expect(adopted.sourceEntryId, 'library-1');
      expect(adopted.name, '改名后的词条');
      expect(adopted.content, 'masterpiece, ultra detailed');
      expect(adopted.categoryId, 'lib-category');

      final untouched = entries.firstWhere((e) => e.id == unrelated.id);
      expect(untouched.sourceEntryId, isNull);
      expect(untouched.content, 'best quality');
    });

    test('不传 previousContent 时只同步 sourceEntryId 匹配的固定词', () async {
      final storage = _MockLocalStorageService();
      when(storage.getFixedTagsJson).thenReturn(null);
      when(storage.getFixedTagLinksJson).thenReturn(null);
      when(storage.getFixedTagsNegativePanelExpanded).thenReturn(true);
      when(() => storage.setFixedTagsJson(any())).thenAnswer((_) async {});
      final container = ProviderContainer(
        overrides: [localStorageServiceProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(fixedTagsNotifierProvider.notifier);

      final manual = await notifier.addEntry(
        name: '手动固定词',
        content: 'masterpiece',
      );

      await notifier.syncFromTagLibrary(
        TagLibraryEntry(
          id: 'library-1',
          name: '改名后的词条',
          content: 'masterpiece, ultra detailed',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      );

      final entries = container.read(fixedTagsNotifierProvider).entries;
      final untouched = entries.firstWhere((e) => e.id == manual.id);
      expect(untouched.sourceEntryId, isNull);
      expect(untouched.content, 'masterpiece');
    });
  });

  group('category grouping', () {
    test('positiveByCategory groups positive entries only', () {
      final negative = FixedTagEntry.create(
        name: 'negative',
        content: 'bad hands',
        promptType: FixedTagPromptType.negative,
        categoryId: 'neg-cat',
      );
      final state = FixedTagsState(
        entries: [
          FixedTagEntry.create(
            name: 'artist1',
            content: 'artist:fuzichoco',
            categoryId: 'artist',
            sortOrder: 1,
          ),
          FixedTagEntry.create(
            name: 'artist2',
            content: 'artist:swav',
            categoryId: 'artist',
            sortOrder: 0,
          ),
          FixedTagEntry.create(
            name: 'quality',
            content: 'masterpiece',
            categoryId: 'quality',
          ),
          FixedTagEntry.create(name: 'uncategorized', content: 'tag'),
          negative,
        ],
      );

      final grouped = state.positiveByCategory;

      expect(grouped['artist']?.map((e) => e.name), ['artist2', 'artist1']);
      expect(grouped['quality'], hasLength(1));
      expect(grouped[null], hasLength(1));
      expect(grouped.containsKey('neg-cat'), isFalse);
    });

    TagLibraryEntry libraryEntry(String id, String? categoryId) =>
        TagLibraryEntry(
          id: id,
          name: id,
          content: 'tag',
          categoryId: categoryId,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );
    TagLibraryCategory category(String id) =>
        TagLibraryCategory(id: id, name: id, createdAt: DateTime(2026));

    test('reconcile makes linked tags follow their library entry', () {
      final linked = FixedTagEntry.create(
        name: 'linked',
        content: 'tag',
        sourceEntryId: 'lib-1',
        categoryId: 'old',
      );
      final reconciled = reconcileFixedTagCategories(
        [linked],
        [libraryEntry('lib-1', 'scene')],
        [category('old'), category('scene')],
      );

      expect(reconciled.single.categoryId, 'scene');
    });

    test('reconcile ungroups tags whose group is gone', () {
      final manual = FixedTagEntry.create(
        name: 'manual',
        content: 'tag',
        categoryId: 'deleted',
      );
      final orphanLink = FixedTagEntry.create(
        name: 'orphan',
        content: 'tag',
        sourceEntryId: 'missing-entry',
        categoryId: 'kept',
      );
      final reconciled = reconcileFixedTagCategories(
        [manual, orphanLink],
        const [],
        [category('kept')],
      );

      expect(reconciled[0].categoryId, isNull);
      // A tag whose library entry was deleted keeps its own group.
      expect(reconciled[1].categoryId, 'kept');
    });

    test('effective group prefers the linked entry', () {
      final linked = FixedTagEntry.create(
        name: 'linked',
        content: 'tag',
        sourceEntryId: 'lib-1',
        categoryId: 'stale',
      );
      expect(
        effectiveFixedTagCategoryId(linked, {
          'lib-1': libraryEntry('lib-1', 'fresh'),
        }),
        'fresh',
      );
      expect(effectiveFixedTagCategoryId(linked, const {}), 'stale');
    });
  });

  group('词库移动与删除分组时固定词跟随', () {
    Future<({ProviderContainer container, String entryId, String tagId})>
    linkedEntry() async {
      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWithValue(MemoryLocalStorage()),
        ],
      );
      addTearDown(container.dispose);
      final library = container.read(tagLibraryPageNotifierProvider.notifier);
      final scene = await library.addCategory(name: '场景');
      final style = await library.addCategory(name: '风格');
      final entry = await library.addEntry(
        name: '夜景',
        content: 'night',
        categoryId: scene!.id,
      );
      final tag = await container
          .read(fixedTagsNotifierProvider.notifier)
          .addEntry(
            name: '夜景',
            content: 'night',
            sourceEntryId: entry.id,
            categoryId: scene.id,
          );
      expect(style, isNotNull);
      return (container: container, entryId: entry.id, tagId: tag.id);
    }

    String? tagCategory(ProviderContainer container, String id) => container
        .read(fixedTagsNotifierProvider)
        .entries
        .singleWhere((e) => e.id == id)
        .categoryId;

    test('移动词条到另一分组时关联的固定词一起移动', () async {
      final (:container, :entryId, :tagId) = await linkedEntry();
      final style = container
          .read(tagLibraryPageNotifierProvider)
          .categories
          .singleWhere((c) => c.name == '风格');

      await container
          .read(tagLibraryPageNotifierProvider.notifier)
          .moveEntryToCategory(entryId, style.id);

      expect(tagCategory(container, tagId), style.id);
    });

    test('删除分组后固定词回到未分组', () async {
      final (:container, :entryId, :tagId) = await linkedEntry();
      final scene = container
          .read(tagLibraryPageNotifierProvider)
          .categories
          .singleWhere((c) => c.name == '场景');

      await container
          .read(tagLibraryPageNotifierProvider.notifier)
          .deleteCategory(scene.id);

      expect(tagCategory(container, tagId), isNull);
    });
  });

  group('library preview resolution', () {
    test('prefers sourceEntryId over matching content and name', () {
      final linked = TagLibraryEntry.create(name: 'linked', content: 'same');
      final duplicate = TagLibraryEntry.create(
        name: 'duplicate',
        content: 'same',
      );
      final fixed = FixedTagEntry.create(
        name: duplicate.name,
        content: duplicate.content,
        sourceEntryId: linked.id,
      );

      expect(resolveFixedTagLibraryEntry(fixed, [duplicate, linked]), linked);
    });

    test('restores legacy library association by exact content', () {
      final libraryEntry = TagLibraryEntry.create(
        name: 'library name',
        content: '1girl, blue eyes',
      );
      final legacyFixed = FixedTagEntry.create(
        name: 'old fixed name',
        content: ' 1girl, blue eyes ',
      );

      expect(
        resolveFixedTagLibraryEntry(legacyFixed, [libraryEntry]),
        libraryEntry,
      );
    });
  });

  group('library picker filtering', () {
    test('excludes library entries already linked from any fixed-tag list', () {
      final available = TagLibraryEntry.create(name: 'available', content: 'a');
      final linkedPositive = TagLibraryEntry.create(
        name: 'positive',
        content: 'b',
      );
      final linkedNegative = TagLibraryEntry.create(
        name: 'negative',
        content: 'c',
      );
      final manualFixedTag = FixedTagEntry.create(name: 'manual', content: 'd');

      final filtered = filterUnlinkedLibraryEntries(
        libraryEntries: [linkedPositive, available, linkedNegative],
        fixedEntries: [
          FixedTagEntry.create(
            name: linkedPositive.name,
            content: linkedPositive.content,
            sourceEntryId: linkedPositive.id,
          ),
          FixedTagEntry.create(
            name: linkedNegative.name,
            content: linkedNegative.content,
            promptType: FixedTagPromptType.negative,
            sourceEntryId: linkedNegative.id,
          ),
          manualFixedTag,
        ],
      );

      expect(filtered, [available]);
    });

    test('preserves the original list when no fixed tag is library-linked', () {
      final entries = [
        TagLibraryEntry.create(name: 'first', content: 'a'),
        TagLibraryEntry.create(name: 'second', content: 'b'),
      ];

      final filtered = filterUnlinkedLibraryEntries(
        libraryEntries: entries,
        fixedEntries: [FixedTagEntry.create(name: 'manual', content: 'a')],
      );

      expect(identical(filtered, entries), isTrue);
    });
  });

  group('filtered reorder', () {
    test('reorders only visible ids while preserving hidden entries', () {
      final a1 = FixedTagEntry.create(
        name: 'a1',
        content: 'a1',
        categoryId: 'a',
        sortOrder: 0,
      );
      final b = FixedTagEntry.create(
        name: 'b',
        content: 'b',
        categoryId: 'b',
        sortOrder: 1,
      );
      final a2 = FixedTagEntry.create(
        name: 'a2',
        content: 'a2',
        categoryId: 'a',
        sortOrder: 2,
      );

      final reordered = reorderFixedTagsWithinVisibleIds(
        entries: [a1, b, a2],
        promptType: FixedTagPromptType.positive,
        visibleIds: [a1.id, a2.id],
        oldIndex: 0,
        newIndex: 1,
      );

      expect(reordered.map((e) => e.id), [a2.id, b.id, a1.id]);
      expect(reordered.map((e) => e.sortOrder), [0, 1, 2]);
    });

    test('does not reorder when indexes are invalid', () {
      final entry = FixedTagEntry.create(name: 'a', content: 'a');

      final reordered = reorderFixedTagsWithinVisibleIds(
        entries: [entry],
        promptType: FixedTagPromptType.positive,
        visibleIds: [entry.id],
        oldIndex: 5,
        newIndex: 0,
      );

      expect(reordered, [entry]);
    });
  });
}

class _MockLocalStorageService extends Mock implements LocalStorageService {}
