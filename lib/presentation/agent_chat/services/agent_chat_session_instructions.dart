import '../../../core/constants/storage_keys.dart';
import '../../../core/storage/local_storage_service.dart';
import '../../../data/models/agent/agent_settings.dart';

/// Instructions the user set for one conversation, kept on this device next
/// to its transcript. Agent sessions are not cloud-synced, and neither are
/// these; deleting a session deletes them.
class AgentChatSessionInstructions {
  const AgentChatSessionInstructions(this._storage);

  static const int maxLength = AgentSettings.maxCustomPromptLength;

  final LocalStorageService _storage;

  String read(String sessionId) {
    if (sessionId.isEmpty) return '';
    return _storage.getSetting<String>(_key(sessionId), defaultValue: '') ?? '';
  }

  /// Stores [text] trimmed; empty text removes the instructions.
  Future<void> write(String sessionId, String text) async {
    if (sessionId.isEmpty) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return delete(sessionId);
    if (trimmed.length > maxLength) {
      throw const FormatException('Conversation instructions are too long.');
    }
    await _storage.setSetting(_key(sessionId), trimmed);
  }

  Future<void> delete(String sessionId) async {
    if (sessionId.isEmpty) return;
    await _storage.deleteSetting(_key(sessionId));
  }

  static String _key(String sessionId) =>
      '${StorageKeys.agentChatSessionInstructionsPrefix}$sessionId';
}
