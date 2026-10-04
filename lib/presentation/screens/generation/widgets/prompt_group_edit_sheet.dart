import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../adaptive/adaptive_presenter.dart';
import '../../../prompt_assistant/providers/prompt_assistant_history_provider.dart';
import '../../../prompt_assistant/widgets/prompt_assistant_overlay.dart';
import '../../../providers/image_generation_provider.dart';
import '../../../themes/core/input_surface_style.dart';
import '../../../themes/core/layered_surface_style.dart';
import '../../../widgets/autocomplete/autocomplete.dart';
import '../../../widgets/prompt/unified/unified_prompt_config.dart';
import '../../../widgets/prompt/unified/unified_prompt_input.dart';
import 'prompt_group_controller.dart';
import 'prompt_input_models.dart';

/// What the section editor needs from the host besides the sections.
class PromptGroupEditCallbacks {
  const PromptGroupEditCallbacks({
    required this.onChanged,
    required this.onToggleEnabled,
    required this.onDuplicate,
    required this.onMoveToFront,
    required this.onDelete,
    required this.onOpenAssistantSettings,
    this.onComfyuiImport,
  });

  /// Section text or order changed; the host recombines the prompt.
  final VoidCallback onChanged;
  final ValueChanged<String> onToggleEnabled;
  final ValueChanged<String> onDuplicate;
  final ValueChanged<String> onMoveToFront;

  /// Called after the editor has closed, so the host can offer undo.
  final ValueChanged<String> onDelete;
  final VoidCallback onOpenAssistantSettings;
  final PromptImportCallback? onComfyuiImport;
}

/// Opens one section in a bottom sheet (a dialog on wide windows). Swiping
/// the title or using its arrows moves to the neighbouring sections.
Future<void> showPromptGroupEditSheet(
  BuildContext context, {
  required PromptGroupCollection groups,
  required String sectionId,
  required bool negative,
  required bool numericEmphasisEnabled,
  required PromptGroupEditCallbacks callbacks,
}) {
  final current = ValueNotifier(sectionId);
  String? pendingDelete;
  return AdaptivePresenter.showPanel<void>(
    context: context,
    initialChildSize: 0.9,
    minChildSize: 0.5,
    maxChildSize: 0.9,
    titleBuilder: (context) =>
        _PromptGroupEditTitle(groups: groups, current: current),
    builder: (context, scrollController) => _PromptGroupEditBody(
      groups: groups,
      current: current,
      negative: negative,
      numericEmphasisEnabled: numericEmphasisEnabled,
      callbacks: callbacks,
      scrollController: scrollController,
      onDeleteRequested: (id) => pendingDelete = id,
    ),
  ).whenComplete(() {
    current.dispose();
    final id = pendingDelete;
    if (id != null) callbacks.onDelete(id);
  });
}

void _step(
  PromptGroupCollection groups,
  ValueNotifier<String> current,
  int by,
) {
  final index = groups.indexOf(current.value) + by;
  if (index < 0 || index >= groups.sections.length) return;
  FocusManager.instance.primaryFocus?.unfocus();
  current.value = groups.sections[index].id;
}

class _PromptGroupEditTitle extends StatelessWidget {
  const _PromptGroupEditTitle({required this.groups, required this.current});

  final PromptGroupCollection groups;
  final ValueNotifier<String> current;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([groups, current]),
      builder: (context, _) {
        final index = groups.indexOf(current.value);
        final total = groups.sections.length;
        return Row(
          children: [
            IconButton(
              key: const ValueKey('prompt_group_edit_previous'),
              tooltip: l10n.prompt_previousGroup,
              onPressed: index > 0 ? () => _step(groups, current, -1) : null,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragEnd: (details) {
                  final velocity = details.primaryVelocity ?? 0;
                  if (velocity.abs() < 250) return;
                  _step(groups, current, velocity < 0 ? 1 : -1);
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.prompt_groupPosition(index + 1, total),
                      key: const ValueKey('prompt_group_edit_title'),
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      l10n.prompt_groupSwipeHint,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              key: const ValueKey('prompt_group_edit_next'),
              tooltip: l10n.prompt_nextGroup,
              onPressed: index >= 0 && index < total - 1
                  ? () => _step(groups, current, 1)
                  : null,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        );
      },
    );
  }
}

class _PromptGroupEditBody extends ConsumerStatefulWidget {
  const _PromptGroupEditBody({
    required this.groups,
    required this.current,
    required this.negative,
    required this.numericEmphasisEnabled,
    required this.callbacks,
    required this.scrollController,
    required this.onDeleteRequested,
  });

  final PromptGroupCollection groups;
  final ValueNotifier<String> current;
  final bool negative;
  final bool numericEmphasisEnabled;
  final PromptGroupEditCallbacks callbacks;
  final ScrollController scrollController;
  final ValueChanged<String> onDeleteRequested;

  @override
  ConsumerState<_PromptGroupEditBody> createState() =>
      _PromptGroupEditBodyState();
}

class _PromptGroupEditBodyState extends ConsumerState<_PromptGroupEditBody> {
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    // A new, empty section is opened to be typed into straight away.
    final section = widget.groups.sectionById(widget.current.value);
    if (section != null && section.controller.text.trim().isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && section.focusNode.canRequestFocus) {
          section.focusNode.requestFocus();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.groups, widget.current]),
      builder: (context, _) {
        final section = widget.groups.sectionById(widget.current.value);
        if (section == null) {
          _closeOnce();
          return const SizedBox.shrink();
        }
        return ListView(
          controller: widget.scrollController,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          children: [
            _buildTools(context, section),
            const SizedBox(height: 12),
            KeyedSubtree(
              key: ValueKey('prompt_group_input_${section.id}'),
              child: _buildInput(context, section),
            ),
          ],
        );
      },
    );
  }

  void _closeOnce() {
    if (_closing) return;
    _closing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  String get _modeSessionId => widget.negative
      ? PromptHistorySessionIds.generationNegative
      : PromptHistorySessionIds.generationPrompt;

  Widget _buildTools(BuildContext context, PromptGroupSection section) {
    final l10n = context.l10n;
    final colors = Theme.of(context).colorScheme;
    final callbacks = widget.callbacks;
    return Row(
      children: [
        Flexible(
          child: Material(
            color: sectionSurfaceColor(colors),
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: const ValueKey('prompt_group_edit_enabled'),
              onTap: () => callbacks.onToggleEnabled(section.id),
              child: Padding(
                padding: const EdgeInsetsDirectional.only(start: 4, end: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ExcludeFocus(
                      child: Switch.adaptive(
                        value: section.enabled,
                        onChanged: (_) => callbacks.onToggleEnabled(section.id),
                      ),
                    ),
                    Flexible(
                      child: Text(
                        l10n.prompt_groupIncluded,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const Spacer(),
        PromptAssistantOverlay(
          key: ValueKey('prompt_group_assistant_${section.id}'),
          placement: PromptAssistantPlacement.inline,
          expandInPlace: false,
          iconOnly: true,
          compactDesktopToolbar: true,
          supportsTagMode: true,
          tagModeSessionId: _modeSessionId,
          sessionId: '${_modeSessionId}_group_${section.id}',
          controller: section.controller,
          onChanged: (_) => callbacks.onChanged(),
          onOpenSettings: callbacks.onOpenAssistantSettings,
        ),
        PopupMenuButton<String>(
          key: const ValueKey('prompt_group_edit_menu'),
          tooltip: l10n.common_moreActions,
          onSelected: (value) {
            switch (value) {
              case 'duplicate':
                callbacks.onDuplicate(section.id);
              case 'front':
                callbacks.onMoveToFront(section.id);
              case 'delete':
                // Deleted once the sheet has closed, where undo is offered.
                widget.onDeleteRequested(section.id);
                Navigator.of(context).maybePop();
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'duplicate',
              child: _MenuRow(
                icon: Icons.copy_all_rounded,
                label: l10n.prompt_groupDuplicate,
              ),
            ),
            PopupMenuItem(
              value: 'front',
              child: _MenuRow(
                icon: Icons.vertical_align_top_rounded,
                label: l10n.prompt_groupMoveToFront,
              ),
            ),
            PopupMenuItem(
              value: 'delete',
              child: _MenuRow(
                icon: Icons.delete_outline_rounded,
                label: l10n.prompt_deleteGroup,
                color: colors.error,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInput(BuildContext context, PromptGroupSection section) {
    final colors = Theme.of(context).colorScheme;
    final callbacks = widget.callbacks;
    return UnifiedPromptInput(
      controller: section.controller,
      focusNode: section.focusNode,
      sessionId: '${_modeSessionId}_group_${section.id}',
      tagModeSessionId: _modeSessionId,
      surfaceColor: inputSurfaceFillColor(colors),
      config: UnifiedPromptConfig(
        enableSyntaxHighlight: ref.watch(highlightEmphasisSettingsProvider),
        numericEmphasisEnabled: widget.numericEmphasisEnabled,
        enableAutocomplete: ref.watch(autocompleteSettingsProvider),
        enableAutoFormat: ref.watch(autoFormatPromptSettingsProvider),
        enableSdSyntaxAutoConvert: ref.watch(
          sdSyntaxAutoConvertSettingsProvider,
        ),
        enableComfyuiImport: !widget.negative,
        enableTagMode: true,
        autocompleteConfig: AutocompleteConfig(
          showTranslation: true,
          showCategory: !widget.negative,
          showCount: !widget.negative,
          autoInsertComma: true,
        ),
        hintText: context.l10n.prompt_groupHint,
      ),
      decoration: const InputDecoration(contentPadding: EdgeInsets.all(12)),
      minLines: 8,
      maxLines: null,
      fitContent: true,
      enableAssistant: false,
      onOpenAssistantSettings: callbacks.onOpenAssistantSettings,
      onComfyuiImport: callbacks.onComfyuiImport,
      onChanged: (_) => callbacks.onChanged(),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 12),
        Flexible(
          child: Text(label, style: TextStyle(color: color)),
        ),
      ],
    );
  }
}
