import 'package:flutter_riverpod/flutter_riverpod.dart';

enum DictionaryTab { entries, characters }

/// Which half of the 词库 page shows: tag library entries or characters.
/// Lasts for the session; other pages open the character half through it.
final dictionaryTabProvider = StateProvider<DictionaryTab>(
  (ref) => DictionaryTab.entries,
);
