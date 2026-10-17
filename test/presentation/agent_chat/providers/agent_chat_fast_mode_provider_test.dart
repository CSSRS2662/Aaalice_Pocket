import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/constants/storage_keys.dart';
import 'package:nai_launcher/core/storage/local_storage_service.dart';
import 'package:nai_launcher/presentation/agent_chat/providers/agent_chat_fast_mode_provider.dart';

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
}

void main() {
  ProviderContainer container(_MemoryLocalStorage storage) {
    final container = ProviderContainer(
      overrides: [localStorageServiceProvider.overrideWithValue(storage)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('Fast mode starts off and is kept on this device', () async {
    final storage = _MemoryLocalStorage();
    final first = container(storage);
    expect(first.read(agentChatFastModeProvider), isFalse);

    await first.read(agentChatFastModeProvider.notifier).setEnabled(true);

    expect(first.read(agentChatFastModeProvider), isTrue);
    expect(storage.values[StorageKeys.agentChatFastMode], isTrue);
    expect(container(storage).read(agentChatFastModeProvider), isTrue);
  });
}
