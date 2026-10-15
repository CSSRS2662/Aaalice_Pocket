import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/agent/agent_types.dart';
import 'package:nai_launcher/presentation/agent_chat/services/application_context_toolbox.dart';
import 'package:nai_launcher/presentation/screens/settings/settings_section.dart';

final _refProvider = Provider<Ref>((ref) => ref);

AgentTool _navigate() {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  return ApplicationContextToolbox(
    container.read(_refProvider),
  ).tools().firstWhere((tool) => tool.name == 'navigate_application');
}

void main() {
  test('settings sections follow the settings page of this platform', () {
    final properties =
        _navigate().parameters['properties'] as Map<String, dynamic>;
    final sections = (properties['settings_section'] as Map)['enum'] as List;
    expect(sections, [
      for (final section in SettingsSection.values)
        if (section.isAvailable) section.id,
    ]);
    expect(sections, containsAll(['agent', 'cloud-sync']));
    final tabs = (properties['generation_tab'] as Map)['enum'] as List;
    expect(tabs, ['image', 'prompt', 'params', 'references', 'history']);
  });

  test('a workbench tab is only valid for the generation page', () async {
    final result = await _navigate().execute('nav', const {
      'destination': 'settings',
      'generation_tab': 'prompt',
    });
    expect(result.isError, isTrue);
    expect(result.details['code'], 'invalid_generation_tab');
  });
}
