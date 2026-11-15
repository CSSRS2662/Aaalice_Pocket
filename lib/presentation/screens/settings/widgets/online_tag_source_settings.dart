import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/autocomplete/autocomplete_settings.dart';
import '../../../../core/autocomplete/completion_models.dart';
import '../../../../core/utils/localization_extension.dart';

class OnlineTagSourceSettings extends ConsumerWidget {
  const OnlineTagSourceSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(autocompleteSettingsProvider);
    final notifier = ref.read(autocompleteSettingsProvider.notifier);
    final enabled = settings.danbooruEnabled;
    return Column(
      children: [
        SwitchListTile.adaptive(
          title: Text(l10n.autocomplete_onlineSupplement),
          subtitle: Text(l10n.autocomplete_onlinePrivacy),
          value: enabled,
          onChanged: notifier.setDanbooruEnabled,
        ),
        ListTile(
          enabled: enabled,
          title: Text(l10n.autocomplete_defaultOnlineSource),
          subtitle: DropdownButton<OnlineTagProvider>(
            key: const ValueKey('autocomplete-online-source'),
            isExpanded: true,
            value: settings.onlineTagProvider,
            items: [
              for (final provider in OnlineTagProvider.values)
                DropdownMenuItem(
                  value: provider,
                  child: Text(provider.label, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: enabled
                ? (provider) {
                    if (provider != null) {
                      notifier.setOnlineTagProvider(provider);
                    }
                  }
                : null,
          ),
        ),
        SwitchListTile.adaptive(
          title: Text(l10n.autocomplete_onlineFallback),
          subtitle: Text(
            l10n.autocomplete_onlineFallbackHint(
              settings.onlineTagProvider.alternate.label,
            ),
          ),
          value: settings.onlineTagFallback,
          onChanged: enabled ? notifier.setOnlineTagFallback : null,
        ),
      ],
    );
  }
}
