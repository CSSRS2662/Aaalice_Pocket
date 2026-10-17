import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/storage_keys.dart';
import '../../../core/storage/local_storage_service.dart';

/// Whether the agent asks ChatGPT (Codex) logins for the Fast service tier.
///
/// Kept on this device and out of cloud backups: it decides how quickly
/// this device spends the subscription quota.
final agentChatFastModeProvider =
    NotifierProvider<AgentChatFastModeNotifier, bool>(
      AgentChatFastModeNotifier.new,
    );

class AgentChatFastModeNotifier extends Notifier<bool> {
  LocalStorageService get _storage => ref.read(localStorageServiceProvider);

  @override
  bool build() =>
      _storage.getSetting<bool>(
        StorageKeys.agentChatFastMode,
        defaultValue: false,
      ) ??
      false;

  Future<void> setEnabled(bool enabled) async {
    if (state == enabled) return;
    state = enabled;
    await _storage.setSetting(StorageKeys.agentChatFastMode, enabled);
  }
}
