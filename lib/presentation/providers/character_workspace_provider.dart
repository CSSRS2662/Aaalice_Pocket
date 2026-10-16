import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/storage_keys.dart';
import '../../core/storage/local_storage_service.dart';

/// The phone prompt page shows the characters instead of the main prompt.
///
/// It stays on until the character button is tapped again, through
/// generating and switching workbench tabs; it is not kept across launches.
final characterWorkspaceActiveProvider = StateProvider<bool>((ref) => false);

/// The character open for editing in the workspace list.
final characterWorkspaceExpandedProvider = StateProvider<String?>(
  (ref) => null,
);

/// The inline gender/library choice for a new character is showing.
final characterWorkspaceAddingProvider = StateProvider<bool>((ref) => false);

/// Character prompts are edited as sections, like the grouped main prompt.
/// An editing preference of this device, so it is not cloud-synced.
final characterPromptsGroupedProvider =
    NotifierProvider<CharacterPromptsGroupedNotifier, bool>(
      CharacterPromptsGroupedNotifier.new,
    );

class CharacterPromptsGroupedNotifier extends Notifier<bool> {
  @override
  bool build() =>
      ref
          .read(localStorageServiceProvider)
          .getSetting<bool>(StorageKeys.characterPromptsGrouped) ??
      true;

  void set(bool grouped) {
    if (grouped == state) return;
    state = grouped;
    ref
        .read(localStorageServiceProvider)
        .setSetting(StorageKeys.characterPromptsGrouped, grouped);
  }
}
