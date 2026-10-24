import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/constants/storage_keys.dart';
import 'package:nai_launcher/core/storage/local_storage_service.dart';
import 'package:nai_launcher/presentation/providers/fixed_tag_usage_provider.dart';
import 'package:nai_launcher/presentation/providers/fixed_tags_sort_provider.dart';
import 'package:nai_launcher/presentation/providers/pending_prompt_provider.dart';
import 'package:nai_launcher/presentation/providers/tag_library_page_provider.dart';

import '../../helpers/memory_local_storage.dart';

ProviderContainer _container(MemoryLocalStorage storage) {
  final container = ProviderContainer(
    overrides: [localStorageServiceProvider.overrideWithValue(storage)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('library sort', () {
    test('sort and favorites-first are saved and read back', () {
      final storage = MemoryLocalStorage();
      final first = _container(storage);
      first
          .read(tagLibraryPageNotifierProvider.notifier)
          .setSortBy(TagLibrarySortBy.recentlyUsed);
      first
          .read(tagLibraryPageNotifierProvider.notifier)
          .setFavoritesFirst(false);

      final second = _container(storage);
      final state = second.read(tagLibraryPageNotifierProvider);
      expect(state.sortBy, TagLibrarySortBy.recentlyUsed);
      expect(state.favoritesFirst, isFalse);
    });

    test('frequent and recently used order entries by use', () async {
      final container = _container(MemoryLocalStorage());
      final notifier = container.read(tagLibraryPageNotifierProvider.notifier);
      final never = await notifier.addEntry(name: 'never', content: 'a');
      final once = await notifier.addEntry(name: 'once', content: 'b');
      final often = await notifier.addEntry(name: 'often', content: 'c');
      await notifier.recordUsages([once.id, often.id]);
      await notifier.recordUsages([often.id]);

      notifier.setSortBy(TagLibrarySortBy.frequent);
      expect(
        container
            .read(tagLibraryPageNotifierProvider)
            .filteredEntries
            .map((e) => e.id),
        [often.id, once.id, never.id],
      );

      notifier.setSortBy(TagLibrarySortBy.recentlyUsed);
      expect(
        container.read(tagLibraryPageNotifierProvider).filteredEntries.last.id,
        never.id,
      );
    });

    test('batch favorite and move save every entry at once', () async {
      final container = _container(MemoryLocalStorage());
      final notifier = container.read(tagLibraryPageNotifierProvider.notifier);
      final group = await notifier.addCategory(name: '场景');
      final a = await notifier.addEntry(name: 'a', content: 'a');
      final b = await notifier.addEntry(name: 'b', content: 'b');

      await notifier.setFavorite([a.id, b.id], true);
      await notifier.moveEntriesToCategory([a.id, b.id], group!.id);

      final entries = container.read(tagLibraryPageNotifierProvider).entries;
      expect(entries.every((e) => e.isFavorite), isTrue);
      expect(entries.every((e) => e.categoryId == group.id), isTrue);
    });
  });

  group('fixed tag usage', () {
    test('each generated image counts once per tag and persists', () {
      final storage = MemoryLocalStorage();
      final container = _container(storage);
      final at = DateTime(2026, 10, 24);

      container
          .read(fixedTagUsageProvider.notifier)
          .record(['a', 'b', 'a'], images: 4, at: at);

      final usage = container.read(fixedTagUsageProvider);
      expect(usage['a']!.count, 4);
      expect(usage['b']!.scoreAt(at), 4);
      expect(storage.values[StorageKeys.fixedTagUsageScores], isA<String>());

      final restored = _container(storage).read(fixedTagUsageProvider);
      expect(restored['a']!.count, 4);
    });

    test('sort preferences default to frequent with enabled first', () {
      final storage = MemoryLocalStorage();
      final container = _container(storage);
      expect(container.read(fixedTagsSortProvider), const FixedTagsSortPrefs());

      container.read(fixedTagsSortProvider.notifier)
        ..setSort(FixedTagsSort.name)
        ..setEnabledFirst(false);

      expect(
        _container(storage).read(fixedTagsSortProvider),
        const FixedTagsSortPrefs(sort: FixedTagsSort.name, enabledFirst: false),
      );
    });
  });

  test('unconsumed appends to the prompt are merged, not replaced', () {
    final container = _container(MemoryLocalStorage());
    final pending = container.read(pendingPromptNotifierProvider.notifier);

    pending.appendToMainPrompt('night');
    pending.appendToMainPrompt('rooftop');

    final state = container.read(pendingPromptNotifierProvider);
    expect(state.prompt, 'night, rooftop');
    expect(state.targetType, SendTargetType.mainPrompt);

    pending.consume();
    pending.appendToMainPrompt('solo');
    expect(container.read(pendingPromptNotifierProvider).prompt, 'solo');
  });
}
