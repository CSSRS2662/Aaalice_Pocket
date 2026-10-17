import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/storage/local_storage_service.dart';
import 'package:nai_launcher/presentation/agent_chat/services/agent_chat_session_instructions.dart';

class _MemoryLocalStorage extends LocalStorageService {
  final Map<String, Object?> values = {};

  @override
  T? getSetting<T>(String key, {T? defaultValue}) {
    final value = values[key];
    return value == null ? defaultValue : value as T;
  }

  @override
  Future<void> setSetting<T>(String key, T value) async {
    values[key] = value;
  }

  @override
  Future<void> deleteSetting(String key) async {
    values.remove(key);
  }
}

void main() {
  test('each conversation keeps its own trimmed instructions', () async {
    final storage = _MemoryLocalStorage();
    final store = AgentChatSessionInstructions(storage);

    await store.write('a', '  draw night scenes  ');
    await store.write('b', 'keep it short');

    expect(store.read('a'), 'draw night scenes');
    expect(store.read('b'), 'keep it short');
    expect(store.read('c'), isEmpty);
    expect(store.read(''), isEmpty);
  });

  test('empty text and deleting a session remove the instructions', () async {
    final storage = _MemoryLocalStorage();
    final store = AgentChatSessionInstructions(storage);
    await store.write('a', 'one');
    await store.write('b', 'two');

    await store.write('a', '   ');
    await store.delete('b');

    expect(store.read('a'), isEmpty);
    expect(store.read('b'), isEmpty);
    expect(storage.values, isEmpty);
  });

  test('instructions longer than the custom prompt limit are refused', () {
    final store = AgentChatSessionInstructions(_MemoryLocalStorage());

    expect(
      store.write('a', 'x' * (AgentChatSessionInstructions.maxLength + 1)),
      throwsFormatException,
    );
  });
}
