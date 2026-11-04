import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_version.dart';
import '../../../core/services/pocket_update_service.dart';
import '../../../core/services/verified_resumable_downloader.dart';
import '../../../core/utils/localization_extension.dart';
import '../../adaptive/adaptive_form_footer.dart';
import '../../adaptive/adaptive_presenter.dart';
import '../../adaptive/content_sized_adaptive_form.dart';
import 'app_toast.dart';

Future<void> openPocketProject(BuildContext context) =>
    _openLink(context, PocketUpdateService.projectUrl);

Future<void> _openLink(BuildContext context, Uri uri) async {
  try {
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
  } on PlatformException {
    // Use the same feedback if the platform cannot resolve the link.
  }
  if (context.mounted) AppToast.error(context, context.l10n.cannotOpenUrl);
}

Future<void> showPocketUpdateDetails(
  BuildContext context,
  PocketRelease release,
) => AdaptivePresenter.showForm<void>(
  context: context,
  title: '${context.l10n.updateAvailable} · v${release.version}',
  headerScrollsWithContent: true,
  builder: (context, controller) =>
      _PocketUpdatePanel(release: release, scrollController: controller),
);

class _PocketUpdatePanel extends ConsumerStatefulWidget {
  const _PocketUpdatePanel({
    required this.release,
    required this.scrollController,
  });

  final PocketRelease release;
  final ScrollController scrollController;

  @override
  ConsumerState<_PocketUpdatePanel> createState() => _PocketUpdatePanelState();
}

class _PocketUpdatePanelState extends ConsumerState<_PocketUpdatePanel> {
  CancelToken? _download;
  double? _progress;
  String? _status;

  @override
  void dispose() {
    _download?.cancel();
    super.dispose();
  }

  Future<void> _install() async {
    final l10n = context.l10n;
    final cancelToken = CancelToken();
    setState(() {
      _download = cancelToken;
      _progress = null;
      _status = null;
    });
    String? status;
    try {
      await ref
          .read(pocketUpdateServiceProvider)
          .install(
            widget.release,
            cancelToken: cancelToken,
            onProgress: (progress) {
              if (mounted) setState(() => _progress = progress.progress);
            },
          );
      if (!cancelToken.isCancelled) status = l10n.updateInstallReady;
    } on VerifiedDownloadCancelledException {
      // A cancelled transfer can resume on the next attempt.
    } on VerifiedDownloadException catch (error) {
      status = switch (error.failure) {
        VerifiedDownloadFailure.sizeMismatch ||
        VerifiedDownloadFailure.checksumMismatch => l10n.updateInvalidPackage,
        _ => l10n.updateInstallFailed,
      };
    } on PlatformException catch (error) {
      status = switch (error.code) {
        'install_permission_denied' ||
        'install_permission_unavailable' => l10n.updateInstallPermission,
        'invalid_update_apk' => l10n.updateInvalidPackage,
        _ => l10n.updateInstallFailed,
      };
    } on Exception {
      status = l10n.updateInstallFailed;
    } finally {
      if (mounted) {
        setState(() {
          _download = null;
          _status = status;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final release = widget.release;
    final download = _download;
    final progress = _progress;
    final busy = download != null;
    final status = busy
        ? progress == 1
              ? l10n.updateVerifying
              : l10n.updateDownloadProgress(((progress ?? 0) * 100).floor())
        : _status;

    return ContentSizedAdaptiveForm(
      scrollController: widget.scrollController,
      content: [
        Text(
          '${l10n.currentVersion} v${AppVersion.versionName}'
          '  →  v${release.version} · '
          '${(release.apkSize / (1024 * 1024)).toStringAsFixed(0)} MiB',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        if (release.notes.isEmpty)
          Text(l10n.updateNoNotes)
        else
          MarkdownBody(
            data: release.notes,
            onTapLink: (_, href, _) {
              final uri = Uri.tryParse(href ?? '');
              if (uri != null && uri.scheme == 'https' && uri.hasAuthority) {
                unawaited(_openLink(context, uri));
              }
            },
          ),
      ],
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (status != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (busy) ...[
                    LinearProgressIndicator(value: progress),
                    const SizedBox(height: 6),
                  ],
                  Semantics(liveRegion: !busy, child: Text(status)),
                ],
              ),
            ),
          AdaptiveFormFooter(
            leading: [
              TextButton(
                onPressed: () => openPocketProject(context),
                child: Text(l10n.updateProjectPage),
              ),
            ],
            cancelLabel: busy ? l10n.common_cancel : l10n.common_close,
            onCancel: download?.cancel,
            primary: FilledButton(
              onPressed: busy ? null : _install,
              child: Text(l10n.updateInstall),
            ),
          ),
        ],
      ),
    );
  }
}
