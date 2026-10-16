import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/localization_extension.dart';
import '../character_library/character_library_view.dart';
import '../tag_library_page/tag_library_page_screen.dart';
import 'dictionary_tab_provider.dart';

/// The 词库 page: tag library entries and the character library, switched
/// at the top. Both halves stay built so each keeps its place.
class DictionaryScreen extends ConsumerWidget {
  const DictionaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final tab = ref.watch(dictionaryTabProvider);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: SegmentedButton<DictionaryTab>(
                key: const ValueKey('dictionary_tabs'),
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: DictionaryTab.entries,
                    label: Text(l10n.characterLibrary_tabEntries),
                    icon: const Icon(Icons.bookmarks_outlined),
                  ),
                  ButtonSegment(
                    value: DictionaryTab.characters,
                    label: Text(l10n.characterLibrary_title),
                    icon: const Icon(Icons.people_outline_rounded),
                  ),
                ],
                selected: {tab},
                onSelectionChanged: (selection) =>
                    ref.read(dictionaryTabProvider.notifier).state =
                        selection.first,
              ),
            ),
            Expanded(
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: IndexedStack(
                  index: tab.index,
                  children: const [
                    TagLibraryPageScreen(showPageTitle: false),
                    CharacterLibraryView(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
