import '../../../core/platform/platform_capabilities.dart';

enum SettingsSection {
  account('account'),
  appearance('appearance'),
  generation('generation'),
  agent('agent'),
  storage('storage'),
  cloudSync('cloud-sync'),
  privacy('privacy'),
  network('network'),
  shortcuts('shortcuts'),
  integrations('integrations'),
  about('about');

  const SettingsSection(this.id);

  final String id;

  /// Whether this platform shows the section; hidden ones open Account.
  bool get isAvailable {
    final capabilities = PlatformCapabilities.current;
    return switch (this) {
      SettingsSection.network => capabilities.supportsAppProxy,
      SettingsSection.shortcuts =>
        capabilities.supportsKeyboardShortcutConfiguration,
      _ => true,
    };
  }

  static SettingsSection fromId(String? value) => values.firstWhere(
    (section) => section.id == value,
    orElse: () => SettingsSection.account,
  );
}
