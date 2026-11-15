import 'package:flutter/widgets.dart';

import '../../../core/autocomplete/completion_models.dart';
import '../../../core/utils/localization_extension.dart';

extension CompletionRemoteErrorMessage on CompletionRemoteError {
  String summary(BuildContext context) {
    final l10n = context.l10n;
    return switch (kind) {
      CompletionRemoteErrorKind.http => switch (statusCode!) {
        429 => l10n.autocomplete_remoteRateLimited,
        503 => l10n.autocomplete_remoteUnavailable,
        final status => l10n.autocomplete_remoteHttpFailure(status),
      },
      CompletionRemoteErrorKind.timeout => l10n.autocomplete_remoteTimeout,
      CompletionRemoteErrorKind.dns => l10n.autocomplete_remoteDnsFailure,
      CompletionRemoteErrorKind.tls => l10n.autocomplete_remoteTlsFailure,
      CompletionRemoteErrorKind.connection =>
        l10n.autocomplete_remoteConnectionFailure,
      CompletionRemoteErrorKind.invalidResponse =>
        l10n.autocomplete_remoteInvalidResponse,
      CompletionRemoteErrorKind.cooldown => l10n.autocomplete_remoteCooldown,
      CompletionRemoteErrorKind.unexpected => l10n.autocomplete_statusError,
    };
  }

  String details(
    BuildContext context, {
    required bool related,
    required OnlineTagProvider provider,
  }) {
    final endpoint = related ? '/related_tag.json' : '/tags.json';
    return [
      '${provider.label} · $endpoint',
      summary(context),
      if (waitSeconds case final seconds?)
        context.l10n.autocomplete_remoteWait(seconds),
    ].join('\n');
  }
}
