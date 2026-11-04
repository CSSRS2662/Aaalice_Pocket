import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/pocket_update_service.dart';
import '../../../core/utils/localization_extension.dart';
import 'action_notice.dart';
import 'pocket_update_panel.dart';

final pocketStartupUpdateProvider = StateProvider<PocketRelease?>(
  (ref) => null,
);

class PocketStartupUpdateNotice extends ConsumerStatefulWidget {
  const PocketStartupUpdateNotice({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<PocketStartupUpdateNotice> createState() =>
      _PocketStartupUpdateNoticeState();
}

class _PocketStartupUpdateNoticeState
    extends ConsumerState<PocketStartupUpdateNotice> {
  @override
  void initState() {
    super.initState();
    ref.listenManual(pocketStartupUpdateProvider, (_, release) {
      if (release == null) return;
      final binding = WidgetsBinding.instance;
      binding.addPostFrameCallback((_) {
        if (!mounted || ref.read(pocketStartupUpdateProvider) != release) {
          return;
        }
        ref.read(pocketStartupUpdateProvider.notifier).state = null;
        ActionNotice.show(
          context,
          message: '${context.l10n.updateAvailable} · v${release.version}',
          actionLabel: context.l10n.updateViewDetails,
          displayDuration: const Duration(seconds: 8),
          onAction: () {
            if (mounted) unawaited(showPocketUpdateDetails(context, release));
          },
        );
      });
      binding.ensureVisualUpdate();
    }, fireImmediately: true);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
