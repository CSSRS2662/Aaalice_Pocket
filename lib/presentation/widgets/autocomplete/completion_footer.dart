import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/autocomplete/autocomplete_settings.dart';
import '../../../core/autocomplete/completion_models.dart';
import '../../../core/autocomplete/cooccurrence_data_pack_service.dart';
import '../../../core/autocomplete/zh_dictionary_service.dart';
import '../../../core/utils/localization_extension.dart';
import '../../adaptive/interaction_policy.dart';
import 'completion_popup_buttons.dart';
import 'completion_source_style.dart';

/// The popup footer: the state of each completion source as a dot and an
/// icon, which double as the legend of the source dots on the candidate
/// tiles (the words are in the tooltips); the multi-select actions centred
/// on the bar while that mode is on; then the settings button and the 分词
/// key at the end.
class CompletionFooter extends StatelessWidget {
  const CompletionFooter({
    super.key,
    required this.state,
    required this.settings,
    required this.dictionaryState,
    required this.cooccurrenceDataPackState,
    required this.onOpenSettings,
    this.onInsertSeparator,
    this.pickActions,
  });

  final CompletionState state;
  final AutocompleteSettings settings;
  final ZhDictionaryState dictionaryState;
  final CooccurrenceDataPackState cooccurrenceDataPackState;
  final VoidCallback onOpenSettings;
  final VoidCallback? onInsertSeparator;

  /// The multi-select actions; given while that mode is on.
  final Widget? pickActions;

  /// Height of the footer for the current input and text scale.
  static double extentOf(BuildContext context) {
    final minimumHeight = context.interactionPolicy.touchAvailable
        ? context.interactionPolicy.minimumControlExtent
        : 31.0;
    final scaledHeight = MediaQuery.textScalerOf(context).scale(11) * 1.35 + 16;
    return scaledHeight > minimumHeight ? scaledHeight : minimumHeight;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final footerHeight = extentOf(context);
    final pickActions = this.pickActions;
    return Container(
      key: const ValueKey('autocomplete-popup-footer'),
      height: footerHeight,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 560;
          final related = state.query?.relatedTag != null;
          final listsLibrary = state.candidates.any(
            (candidate) =>
                candidate.sources.contains(CompletionSourceKind.library),
          );
          final statuses = <_StatusDescriptor>[
            if (related) _relatedStatus(context) else _baseStatus(context),
            _dictionaryStatus(context),
            _onlineStatus(context),
            if (!compact || settings.llmTranslationEnabled) _aiStatus(context),
            if (listsLibrary) _libraryLegend(context),
          ];
          return CustomMultiChildLayout(
            delegate: _FooterLayout(),
            children: [
              LayoutId(
                id: _FooterSlot.statuses,
                child: _StatusRow(statuses: statuses),
              ),
              if (pickActions != null)
                LayoutId(
                  id: _FooterSlot.picks,
                  // Only narrows when enlarged text leaves no room; the
                  // height is the bar's, so the buttons are never scaled
                  // for their touch padding.
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SizedBox(
                      height: constraints.maxHeight,
                      child: pickActions,
                    ),
                  ),
                ),
              LayoutId(
                id: _FooterSlot.actions,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CompletionPopupIconButton(
                      key: const ValueKey('autocomplete-popup-settings'),
                      tooltip: context.l10n.autocomplete_openSettings,
                      icon: Icons.settings_rounded,
                      onPressed: onOpenSettings,
                    ),
                    if (onInsertSeparator case final split?) ...[
                      Container(
                        height: 19,
                        width: 1,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        color: theme.colorScheme.outlineVariant.withValues(
                          alpha: 0.46,
                        ),
                      ),
                      CompletionSplitButton(onPressed: split),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Tag library entries have no service state; listed only for the legend.
  _StatusDescriptor _libraryLegend(BuildContext context) => _StatusDescriptor(
    key: 'autocomplete-status-library',
    source: CompletionSourceKind.library,
    icon: Icons.collections_bookmark_rounded,
    label: context.l10n.autocomplete_categoryLibrary,
    value:
        '${state.candidates.where((candidate) => candidate.sources.contains(CompletionSourceKind.library)).length}',
    tone: _StatusTone.ready,
  );

  _StatusDescriptor _baseStatus(BuildContext context) => _StatusDescriptor(
    key: 'autocomplete-status-base',
    source: CompletionSourceKind.base,
    icon: Icons.storage_rounded,
    label: context.l10n.autocomplete_statusBase,
    value: context.l10n.autocomplete_statusReady,
    tone: _StatusTone.ready,
    tooltip:
        '${context.l10n.autocomplete_baseCatalog}: ${context.l10n.autocomplete_statusReady}',
  );

  _StatusDescriptor _relatedStatus(BuildContext context) {
    if (!settings.relatedTagsEnabled) {
      return _StatusDescriptor(
        key: 'autocomplete-status-related',
        source: CompletionSourceKind.cooccurrence,
        icon: Icons.hub_outlined,
        label: context.l10n.autocomplete_statusRelated,
        value: context.l10n.autocomplete_statusDisabled,
        tone: _StatusTone.inactive,
      );
    }
    if (state.isLocalLoading) {
      return _StatusDescriptor(
        key: 'autocomplete-status-related',
        source: CompletionSourceKind.cooccurrence,
        icon: Icons.hub_outlined,
        label: context.l10n.autocomplete_statusRelated,
        value: context.l10n.autocomplete_statusSearching,
        tone: _StatusTone.loading,
        loading: true,
      );
    }
    if (state.localError?.isNotEmpty == true) {
      return _StatusDescriptor(
        key: 'autocomplete-status-related',
        source: CompletionSourceKind.cooccurrence,
        icon: Icons.hub_outlined,
        label: context.l10n.autocomplete_statusRelated,
        value: context.l10n.autocomplete_statusError,
        tone: _StatusTone.error,
        tooltip: state.localError,
      );
    }
    if (!cooccurrenceDataPackState.hasInstalledData) {
      final downloading =
          cooccurrenceDataPackState.status ==
          CooccurrenceDataPackStatus.downloading;
      return _StatusDescriptor(
        key: 'autocomplete-status-related',
        source: CompletionSourceKind.cooccurrence,
        icon: downloading ? Icons.downloading_rounded : Icons.cloud_outlined,
        label: context.l10n.autocomplete_statusRelated,
        value: context.l10n.autocomplete_statusOnlineOnly,
        tone: downloading ? _StatusTone.loading : _StatusTone.inactive,
        loading: downloading,
        tooltip: context.l10n.autocomplete_statusOnlineOnlyTooltip,
      );
    }
    final localCount = state.candidates
        .where(
          (candidate) =>
              candidate.sources.contains(CompletionSourceKind.cooccurrence),
        )
        .length;
    return _StatusDescriptor(
      key: 'autocomplete-status-related',
      source: CompletionSourceKind.cooccurrence,
      icon: Icons.hub_rounded,
      label: context.l10n.autocomplete_statusRelated,
      value: '$localCount',
      tone: _StatusTone.ready,
      tooltip: context.l10n.autocomplete_sourceRelated,
    );
  }

  _StatusDescriptor _dictionaryStatus(BuildContext context) {
    if (dictionaryState.isBusy) {
      final progress = (dictionaryState.progress * 100).round().clamp(0, 100);
      return _StatusDescriptor(
        key: 'autocomplete-status-dictionary',
        source: CompletionSourceKind.zhDictionary,
        icon: Icons.translate_rounded,
        label: context.l10n.autocomplete_statusDictionary,
        value: context.l10n.autocomplete_statusDownloading(progress),
        tone: _StatusTone.loading,
        loading: true,
      );
    }
    if (dictionaryState.error?.isNotEmpty == true) {
      return _StatusDescriptor(
        key: 'autocomplete-status-dictionary',
        source: CompletionSourceKind.zhDictionary,
        icon: Icons.translate_rounded,
        label: context.l10n.autocomplete_statusDictionary,
        value: context.l10n.autocomplete_statusError,
        tone: _StatusTone.error,
        tooltip: dictionaryState.error,
      );
    }
    if (!dictionaryState.isInstalled) {
      return _StatusDescriptor(
        key: 'autocomplete-status-dictionary',
        source: CompletionSourceKind.zhDictionary,
        icon: Icons.translate_rounded,
        label: context.l10n.autocomplete_statusDictionary,
        value: context.l10n.autocomplete_statusNotInstalled,
        tone: _StatusTone.warning,
        tooltip: context.l10n.autocomplete_zhNotInstalled,
      );
    }
    if (dictionaryState.updateAvailable) {
      return _StatusDescriptor(
        key: 'autocomplete-status-dictionary',
        source: CompletionSourceKind.zhDictionary,
        icon: Icons.translate_rounded,
        label: context.l10n.autocomplete_statusDictionary,
        value: context.l10n.autocomplete_statusUpdateAvailable,
        tone: _StatusTone.warning,
      );
    }
    final translatedCount = state.candidates
        .where((candidate) => candidate.translation?.isNotEmpty == true)
        .length;
    final totalCount = state.candidates.length;
    return _StatusDescriptor(
      key: 'autocomplete-status-dictionary',
      source: CompletionSourceKind.zhDictionary,
      icon: Icons.translate_rounded,
      label: context.l10n.autocomplete_statusDictionary,
      value: totalCount == 0
          ? context.l10n.autocomplete_statusReady
          : '$translatedCount/$totalCount',
      tone: _StatusTone.ready,
      tooltip: totalCount == 0
          ? context.l10n.autocomplete_entryCount(dictionaryState.tagCount)
          : context.l10n.autocomplete_translationCoverage(
              translatedCount,
              totalCount,
            ),
    );
  }

  _StatusDescriptor _onlineStatus(BuildContext context) {
    if (!settings.danbooruEnabled) {
      return _StatusDescriptor(
        key: 'autocomplete-status-online',
        source: CompletionSourceKind.danbooruApi,
        icon: Icons.public_rounded,
        label: context.l10n.autocomplete_statusOnline,
        value: context.l10n.autocomplete_statusDisabled,
        tone: _StatusTone.inactive,
      );
    }
    if (state.isRemoteLoading) {
      return _StatusDescriptor(
        key: 'autocomplete-status-online',
        source: CompletionSourceKind.danbooruApi,
        icon: Icons.public_rounded,
        label: context.l10n.autocomplete_statusOnline,
        value: context.l10n.autocomplete_statusSearching,
        tone: _StatusTone.loading,
        loading: true,
      );
    }
    if (state.remoteError?.isNotEmpty == true) {
      return _StatusDescriptor(
        key: 'autocomplete-status-online',
        source: CompletionSourceKind.danbooruApi,
        icon: Icons.public_off_rounded,
        label: context.l10n.autocomplete_statusOnline,
        value: context.l10n.autocomplete_statusError,
        tone: _StatusTone.error,
        tooltip: state.remoteError,
      );
    }
    return _StatusDescriptor(
      key: 'autocomplete-status-online',
      source: CompletionSourceKind.danbooruApi,
      icon: Icons.public_rounded,
      label: context.l10n.autocomplete_statusOnline,
      value: context.l10n.autocomplete_statusReady,
      tone: _StatusTone.ready,
      tooltip: context.l10n.autocomplete_danbooruPrivacy,
    );
  }

  _StatusDescriptor _aiStatus(BuildContext context) {
    if (!settings.llmTranslationEnabled) {
      return _StatusDescriptor(
        key: 'autocomplete-status-ai',
        source: CompletionSourceKind.ai,
        icon: Icons.auto_awesome_outlined,
        label: context.l10n.autocomplete_statusAi,
        value: context.l10n.autocomplete_statusDisabled,
        tone: _StatusTone.inactive,
      );
    }
    if (state.candidates.any((candidate) => candidate.isTranslating)) {
      return _StatusDescriptor(
        key: 'autocomplete-status-ai',
        source: CompletionSourceKind.ai,
        icon: Icons.auto_awesome_rounded,
        label: context.l10n.autocomplete_statusAi,
        value: context.l10n.autocomplete_statusTranslating,
        tone: _StatusTone.loading,
        loading: true,
      );
    }
    if (state.translationError?.isNotEmpty == true) {
      return _StatusDescriptor(
        key: 'autocomplete-status-ai',
        source: CompletionSourceKind.ai,
        icon: Icons.auto_awesome_outlined,
        label: context.l10n.autocomplete_statusAi,
        value: context.l10n.autocomplete_statusError,
        tone: _StatusTone.error,
        tooltip: state.translationError,
      );
    }
    return _StatusDescriptor(
      key: 'autocomplete-status-ai',
      source: CompletionSourceKind.ai,
      icon: Icons.auto_awesome_rounded,
      label: context.l10n.autocomplete_statusAi,
      value: context.l10n.autocomplete_statusReady,
      tone: _StatusTone.ready,
    );
  }
}

enum _StatusTone { ready, loading, warning, error, inactive }

class _StatusDescriptor {
  const _StatusDescriptor({
    required this.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.tone,
    required this.source,
    this.loading = false,
    this.tooltip,
  });

  final String key;

  /// The source this status reports; its colour is the legend of the dots.
  final CompletionSourceKind source;
  final IconData icon;
  final String label;
  final String value;
  final _StatusTone tone;
  final bool loading;
  final String? tooltip;
}

enum _FooterSlot { statuses, picks, actions }

/// Places the actions at the end, the multi-select actions on the centre of
/// the bar (moved left only as far as the actions need) and the statuses in
/// the room left at the start.
class _FooterLayout extends MultiChildLayoutDelegate {
  static const double leadingInset = 9;
  static const double gap = 8;

  @override
  void performLayout(Size size) {
    double centred(Size child) => (size.height - child.height) / 2;
    final actions = layoutChild(
      _FooterSlot.actions,
      BoxConstraints.loose(size),
    );
    final actionsLeft = size.width - actions.width;
    positionChild(_FooterSlot.actions, Offset(actionsLeft, centred(actions)));
    var statusesEnd = actionsLeft - gap;
    if (hasChild(_FooterSlot.picks)) {
      final room = math.max(0.0, actionsLeft - gap - leadingInset);
      final picks = layoutChild(
        _FooterSlot.picks,
        BoxConstraints.loose(Size(room, size.height)),
      );
      final left = math.max(
        leadingInset,
        math.min(
          (size.width - picks.width) / 2,
          actionsLeft - gap - picks.width,
        ),
      );
      positionChild(_FooterSlot.picks, Offset(left, centred(picks)));
      statusesEnd = left - gap;
    }
    final statuses = layoutChild(
      _FooterSlot.statuses,
      BoxConstraints.loose(
        Size(math.max(0.0, statusesEnd - leadingInset), size.height),
      ),
    );
    positionChild(
      _FooterSlot.statuses,
      Offset(leadingInset, centred(statuses)),
    );
  }

  @override
  bool shouldRelayout(_FooterLayout oldDelegate) => false;
}

/// As many statuses as fit, in order; each is a dot and an icon of fixed
/// width, so the rest are left out rather than squeezed.
class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.statuses});

  final List<_StatusDescriptor> statuses;

  static const double gap = 11;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fitting =
            ((constraints.maxWidth + gap) / (_StatusIndicator.width + gap))
                .floor()
                .clamp(0, statuses.length);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < fitting; index++) ...[
              if (index > 0) const SizedBox(width: gap),
              _StatusIndicator(
                key: ValueKey(statuses[index].key),
                descriptor: statuses[index],
              ),
            ],
          ],
        );
      },
    );
  }
}

class _StatusIndicator extends StatelessWidget {
  const _StatusIndicator({super.key, required this.descriptor});

  final _StatusDescriptor descriptor;

  static const double _dotGap = 3;
  static const double _iconSize = 14;
  static const double width =
      CompletionSourceDots.dotSize + _dotGap + _iconSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final toneColor = switch (descriptor.tone) {
      _StatusTone.ready => const Color(0xff4fb77b),
      _StatusTone.loading => theme.colorScheme.primary,
      _StatusTone.warning => const Color(0xffd99a3b),
      _StatusTone.error => theme.colorScheme.error,
      _StatusTone.inactive => theme.colorScheme.outline,
    };
    final tooltip = descriptor.tooltip?.isNotEmpty == true
        ? '${descriptor.label}: ${descriptor.value}\n${descriptor.tooltip}'
        : '${descriptor.label}: ${descriptor.value}';
    return Tooltip(
      message: tooltip,
      child: Semantics(
        label: '${descriptor.label}: ${descriptor.value}',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              key: ValueKey('${descriptor.key}-dot'),
              width: CompletionSourceDots.dotSize,
              height: CompletionSourceDots.dotSize,
              decoration: BoxDecoration(
                color: CompletionSourceStyle.color(theme, descriptor.source),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: _dotGap),
            SizedBox.square(
              dimension: _iconSize,
              child: descriptor.loading
                  ? Padding(
                      padding: const EdgeInsets.all(1),
                      child: CircularProgressIndicator(
                        value: MediaQuery.disableAnimationsOf(context)
                            ? 0.75
                            : null,
                        strokeWidth: 1.7,
                        color: toneColor,
                      ),
                    )
                  : Icon(descriptor.icon, size: _iconSize, color: toneColor),
            ),
          ],
        ),
      ),
    );
  }
}
