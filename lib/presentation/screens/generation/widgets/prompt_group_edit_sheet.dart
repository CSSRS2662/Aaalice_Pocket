import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../adaptive/adaptive_presenter.dart';
import '../../../prompt_assistant/providers/prompt_assistant_history_provider.dart';
import '../../../prompt_assistant/widgets/prompt_assistant_overlay.dart';
import '../../../providers/image_generation_provider.dart';
import '../../../themes/core/input_surface_style.dart';
import '../../../widgets/autocomplete/autocomplete.dart';
import '../../../widgets/prompt/prompt_footer_style.dart';
import '../../../widgets/prompt/prompt_tag_mode_toggle.dart';
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

/// Opens one section as a full-height editor: a navigation row on top, the
/// prompt field filling the middle and the editing tools at the bottom, so
/// with the keyboard up the tools sit right above it.
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
    initialChildSize: 0.92,
    minChildSize: 0.5,
    maxChildSize: 0.92,
    showHeader: false,
    animateKeyboardInset: false,
    builder: (context, _) => _PromptGroupEditor(
      groups: groups,
      current: current,
      negative: negative,
      numericEmphasisEnabled: numericEmphasisEnabled,
      callbacks: callbacks,
      onDeleteRequested: (id) => pendingDelete = id,
    ),
  ).whenComplete(() {
    current.dispose();
    final id = pendingDelete;
    if (id != null) callbacks.onDelete(id);
  });
}

class _PromptGroupEditor extends ConsumerStatefulWidget {
  const _PromptGroupEditor({
    required this.groups,
    required this.current,
    required this.negative,
    required this.numericEmphasisEnabled,
    required this.callbacks,
    required this.onDeleteRequested,
  });

  final PromptGroupCollection groups;
  final ValueNotifier<String> current;
  final bool negative;
  final bool numericEmphasisEnabled;
  final PromptGroupEditCallbacks callbacks;
  final ValueChanged<String> onDeleteRequested;

  @override
  ConsumerState<_PromptGroupEditor> createState() => _PromptGroupEditorState();
}

class _PromptGroupEditorState extends ConsumerState<_PromptGroupEditor> {
  /// Direction of the last section change, for the slide between sections.
  int _direction = 0;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    // Opening a section is for typing: caret at the end, keyboard up.
    _focusAtEndAfterBuild();
  }

  void _focusAtEndAfterBuild() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final section = widget.groups.sectionById(widget.current.value);
      if (!mounted || section == null || !section.focusNode.canRequestFocus) {
        return;
      }
      final controller = section.controller;
      controller.selection = TextSelection.collapsed(
        offset: controller.text.length,
      );
      section.focusNode.requestFocus();
    });
  }

  String get _modeSessionId => widget.negative
      ? PromptHistorySessionIds.generationNegative
      : PromptHistorySessionIds.generationPrompt;

  void _step(int by) {
    final groups = widget.groups;
    final index = groups.indexOf(widget.current.value) + by;
    if (index < 0 || index >= groups.sections.length) return;
    final typing =
        groups.sectionById(widget.current.value)?.focusNode.hasFocus ?? false;
    _direction = by.sign;
    widget.current.value = groups.sections[index].id;
    // Keep the keyboard up when moving on while typing.
    if (typing) _focusAtEndAfterBuild();
  }

  void _close() => Navigator.of(context).maybePop();

  void _closeOnce() {
    if (_closing) return;
    _closing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _close();
    });
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
        final inputKey = ValueKey('prompt_group_input_${section.id}');
        final content = Column(
          children: [
            _EditorHeader(
              index: widget.groups.indexOf(section.id),
              total: widget.groups.sections.length,
              onStep: _step,
              onDone: _close,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _slideBetweenSections(
                  context,
                  inputKey,
                  KeyedSubtree(
                    key: inputKey,
                    child: _buildInput(context, section),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 12, 12),
              child: _buildToolbar(context, section),
            ),
          ],
        );
        // Centered dialogs on wide windows give a loose height.
        return LayoutBuilder(
          builder: (context, constraints) => constraints.hasBoundedHeight
              ? content
              : SizedBox(height: 560, child: content),
        );
      },
    );
  }

  /// The incoming section slides in from the side it was asked for; the
  /// outgoing one leaves towards the other side.
  Widget _slideBetweenSections(
    BuildContext context,
    Key currentKey,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final direction = _direction.toDouble();
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (current, previous) =>
          Stack(fit: StackFit.expand, children: [...previous, ?current]),
      transitionBuilder: (child, animation) {
        final incoming = child.key == currentKey;
        final offset = Tween<Offset>(
          begin: Offset(0.12 * (incoming ? direction : -direction), 0),
          end: Offset.zero,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: offset, child: child),
        );
      },
      child: child,
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
      decoration: const InputDecoration(contentPadding: EdgeInsets.all(14)),
      maxLines: null,
      expands: true,
      enableAssistant: false,
      showTagModeSwitch: false,
      onOpenAssistantSettings: callbacks.onOpenAssistantSettings,
      onComfyuiImport: callbacks.onComfyuiImport,
      onChanged: (_) => callbacks.onChanged(),
    );
  }

  Widget _buildToolbar(BuildContext context, PromptGroupSection section) {
    final callbacks = widget.callbacks;
    return Row(
      children: [
        Flexible(
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: _IncludeToggle(
              enabled: section.enabled,
              onTap: () => callbacks.onToggleEnabled(section.id),
            ),
          ),
        ),
        const SizedBox(width: 4),
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
        const SizedBox(width: 4),
        PromptTagModeToggle(sessionId: _modeSessionId),
        _buildMenu(context, section),
      ],
    );
  }

  Widget _buildMenu(BuildContext context, PromptGroupSection section) {
    final l10n = context.l10n;
    final colors = Theme.of(context).colorScheme;
    final callbacks = widget.callbacks;
    return PopupMenuButton<String>(
      key: const ValueKey('prompt_group_edit_menu'),
      tooltip: l10n.common_moreActions,
      icon: const Icon(Icons.more_horiz_rounded),
      onSelected: (value) {
        switch (value) {
          case 'duplicate':
            callbacks.onDuplicate(section.id);
          case 'front':
            callbacks.onMoveToFront(section.id);
          case 'delete':
            // Deleted once the sheet has closed, where undo is offered.
            widget.onDeleteRequested(section.id);
            _close();
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
    );
  }
}

/// Section position with neighbours: arrows around a swipeable title with
/// page dots, and Done on the right.
class _EditorHeader extends StatelessWidget {
  const _EditorHeader({
    required this.index,
    required this.total,
    required this.onStep,
    required this.onDone,
  });

  /// More dots than this stop telling anything at a glance.
  static const int maxDots = 9;

  final int index;
  final int total;
  final ValueChanged<int> onStep;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(4, 2, 12, 6),
      child: Row(
        children: [
          // The title keeps all spare width; actions stay at their size.
          Expanded(
            child: Row(
              children: [
                IconButton(
                  key: const ValueKey('prompt_group_edit_previous'),
                  tooltip: l10n.prompt_previousGroup,
                  onPressed: index > 0 ? () => onStep(-1) : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Flexible(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragEnd: (details) {
                      final velocity = details.primaryVelocity ?? 0;
                      if (velocity.abs() >= 250) onStep(velocity < 0 ? 1 : -1);
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: l10n.prompt_groupLabel(index + 1)),
                              TextSpan(
                                text: ' / $total',
                                style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                          key: const ValueKey('prompt_group_edit_title'),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (total > 1 && total <= maxDots) ...[
                          const SizedBox(height: 6),
                          _PageDots(index: index, total: total),
                        ],
                      ],
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('prompt_group_edit_next'),
                  tooltip: l10n.prompt_nextGroup,
                  onPressed: index < total - 1 ? () => onStep(1) : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            key: const ValueKey('prompt_group_edit_done'),
            onPressed: onDone,
            child: Text(l10n.common_done),
          ),
        ],
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.index, required this.total});

  final int index;
  final int total;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var dot = 0; dot < total; dot++)
            AnimatedContainer(
              duration: duration,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: dot == index ? 14 : 5,
              height: 5,
              decoration: BoxDecoration(
                color: dot == index ? colors.primary : colors.outlineVariant,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
        ],
      ),
    );
  }
}

/// Whether the section goes into the prompt, as a pill the size of the
/// neighbouring text/tag toggle.
class _IncludeToggle extends StatelessWidget {
  const _IncludeToggle({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = Theme.of(context).colorScheme;
    final foreground = enabled
        ? colors.onPrimaryContainer
        : colors.onSurfaceVariant;
    return Semantics(
      toggled: enabled,
      child: Tooltip(
        message: enabled ? l10n.prompt_groupDisable : l10n.prompt_groupEnable,
        child: TextButton.icon(
          key: const ValueKey('prompt_group_edit_enabled'),
          onPressed: onTap,
          style: PromptFooterStyle.button(context).copyWith(
            backgroundColor: WidgetStatePropertyAll(
              enabled ? colors.primaryContainer : colors.surfaceContainerHigh,
            ),
            foregroundColor: WidgetStatePropertyAll(foreground),
          ),
          icon: Icon(
            enabled
                ? Icons.check_circle_rounded
                : Icons.do_not_disturb_on_outlined,
            size: PromptFooterStyle.iconSize,
          ),
          label: Text(
            enabled ? l10n.prompt_groupIncluded : l10n.prompt_groupOff,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
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
