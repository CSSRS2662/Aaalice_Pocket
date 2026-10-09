import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/autocomplete/autocomplete_settings.dart' as completion;
import '../../../../core/autocomplete/prompt_token_parser.dart';
import '../../../../core/utils/localization_extension.dart';
import '../../../adaptive/adaptive_presenter.dart';
import '../../../prompt_assistant/providers/prompt_assistant_history_provider.dart';
import '../../../prompt_assistant/widgets/prompt_assistant_overlay.dart';
import '../../../providers/image_generation_provider.dart';
import '../../../themes/core/input_surface_style.dart';
import '../../../widgets/autocomplete/autocomplete.dart';
import '../../../widgets/autocomplete/autocomplete_overlay_handle.dart';
import '../../../widgets/prompt/prompt_footer_style.dart';
import '../../../widgets/prompt/prompt_tag_mode_toggle.dart';
import '../../../widgets/prompt/unified/unified_prompt_config.dart';
import '../../../widgets/prompt/unified/unified_prompt_input.dart';
import 'prompt_completion_exclusions.dart';
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

  /// Reaches the field's suggestions for the 联想 and 分词 keys.
  final AutocompleteOverlayHandle _suggestions = AutocompleteOverlayHandle();

  @override
  void initState() {
    super.initState();
    // Opening a section is for typing: caret at the end, keyboard up.
    _focusAtEndAfterBuild();
  }

  @override
  void dispose() {
    _suggestions.dispose();
    super.dispose();
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

  /// The 联想 key shows only when related suggestions can come.
  bool get _suggestsRelated => ref.watch(
    completion.autocompleteSettingsProvider.select(
      (settings) => settings.enabled && settings.relatedTagsEnabled,
    ),
  );

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
        final index = widget.groups.indexOf(section.id);
        final total = widget.groups.sections.length;
        return LayoutBuilder(
          builder: (context, constraints) {
            // The mode toggle and menu go next to the title as far as the
            // row has room, leaving the bottom row to typing tools.
            final onTop = _EditorHeader.toolsThatFit(
              context,
              maxWidth: constraints.maxWidth,
              index: index,
              total: total,
            );
            final toggle = PromptTagModeToggle(sessionId: _modeSessionId);
            final menu = _buildMenu(context, section);
            final content = Column(
              children: [
                _EditorHeader(
                  index: index,
                  total: total,
                  onStep: _step,
                  onDone: _close,
                  tools: switch (onTop) {
                    _HeaderTools.toggleAndMenu => [toggle, menu],
                    _HeaderTools.menu => [menu],
                    _HeaderTools.none => const [],
                  },
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
                  child: _buildToolbar(
                    context,
                    section,
                    tools: switch (onTop) {
                      _HeaderTools.toggleAndMenu => const [],
                      _HeaderTools.menu => [toggle],
                      _HeaderTools.none => [toggle, menu],
                    },
                  ),
                ),
              ],
            );
            // Centered dialogs on wide windows give a loose height.
            return constraints.hasBoundedHeight
                ? content
                : SizedBox(height: 560, child: content);
          },
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

  /// Tags the other included sections and the fixed tags already add.
  Set<String> _writtenElsewhere(PromptGroupSection section) =>
      promptCompletionExclusions(
        ref,
        negative: widget.negative,
        otherTexts: [
          for (final other in widget.groups.sections)
            if (other.id != section.id && other.enabled) other.controller.text,
        ],
      );

  /// Ends the tag at the caret with ", " without leaving Chinese input, then
  /// suggests what fits next.
  void _insertComma(PromptGroupSection section) {
    final controller = section.controller;
    final text = controller.text;
    final selection = controller.selection;
    final next = PromptTokenParser.insertSeparator(
      text: text,
      cursorPosition: selection.isValid ? selection.end : text.length,
    );
    controller.value = TextEditingValue(
      text: next.text,
      selection: TextSelection.collapsed(offset: next.cursorPosition),
    );
    if (!section.focusNode.hasFocus) section.focusNode.requestFocus();
    if (next.text != text) widget.callbacks.onChanged();
    _suggestions.continueAfterSeparator();
  }

  /// Suggests what fits with the tags around the caret.
  void _suggestNext(PromptGroupSection section) {
    if (!section.focusNode.hasFocus) section.focusNode.requestFocus();
    _suggestions.suggestNext();
  }

  /// Tags of the other included sections, with the 1-based numbers of the
  /// sections (the cards' order) holding each.
  Map<String, List<int>> _otherSections(PromptGroupSection section) {
    final result = <String, List<int>>{};
    for (final (index, other) in widget.groups.sections.indexed) {
      if (other.id == section.id || !other.enabled) continue;
      final text = other.controller.text;
      for (final tag in PromptTokenParser.contextTags(
        text: text,
        cursorPosition: text.length,
        max: 1 << 16,
      )) {
        (result[tag] ??= []).add(index + 1);
      }
    }
    return result;
  }

  Widget _buildInput(BuildContext context, PromptGroupSection section) {
    return CompletionExclusionScope(
      tags: () => _writtenElsewhere(section),
      otherSections: () => _otherSections(section),
      sectionNumber: widget.groups.indexOf(section.id) + 1,
      child: _buildField(context, section),
    );
  }

  Widget _buildField(BuildContext context, PromptGroupSection section) {
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
      autocompleteHandle: _suggestions,
      onOpenAssistantSettings: callbacks.onOpenAssistantSettings,
      onComfyuiImport: callbacks.onComfyuiImport,
      onChanged: (_) => callbacks.onChanged(),
    );
  }

  /// Include toggle at the start; the assistant, any [tools] that did not
  /// fit the header, and the comma key at the end, right above the keyboard.
  Widget _buildToolbar(
    BuildContext context,
    PromptGroupSection section, {
    required List<Widget> tools,
  }) {
    final callbacks = widget.callbacks;
    final row = Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _IncludeToggle(
          enabled: section.enabled,
          onTap: () => callbacks.onToggleEnabled(section.id),
        ),
        const SizedBox(width: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
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
            for (final tool in tools) ...[const SizedBox(width: 4), tool],
            if (_suggestsRelated)
              TextFieldTapRegion(
                child: IconButton(
                  key: const ValueKey('prompt_group_edit_suggest'),
                  tooltip: context.l10n.prompt_suggestNext,
                  onPressed: () => _suggestNext(section),
                  icon: const Icon(Icons.hub_outlined, size: 22),
                ),
              )
            else
              const SizedBox(width: 8),
            _SplitKey(onPressed: () => _insertComma(section)),
          ],
        ),
      ],
    );
    // Too wide (very large text): the whole row scrolls instead of cutting
    // labels short, starting from the end where the typing tools are.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        key: const ValueKey('prompt_group_edit_toolbar'),
        scrollDirection: Axis.horizontal,
        reverse: true,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth),
          child: IntrinsicWidth(child: row),
        ),
      ),
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

/// Which of the text/tag toggle and the menu the header holds.
enum _HeaderTools { toggleAndMenu, menu, none }

/// Section position with neighbours: arrows around a swipeable title with
/// page dots, then [tools] and Done on the right.
class _EditorHeader extends StatelessWidget {
  const _EditorHeader({
    required this.index,
    required this.total,
    required this.onStep,
    required this.onDone,
    this.tools = const [],
  });

  /// More dots than this stop telling anything at a glance.
  static const int maxDots = 9;

  static const EdgeInsetsDirectional _padding = EdgeInsetsDirectional.fromSTEB(
    4,
    2,
    12,
    6,
  );
  static const double _arrowExtent = 48;
  static const EdgeInsets _donePadding = EdgeInsets.symmetric(horizontal: 18);

  static const double _toggleWidth = PromptTagModeToggle.width;
  static const double _menuWidth = 48;

  final int index;
  final int total;
  final ValueChanged<int> onStep;
  final VoidCallback onDone;
  final List<Widget> tools;

  static TextStyle? _titleStyle(ThemeData theme) =>
      theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700);

  /// Which tools share one [maxWidth] row with the title and Done without
  /// cutting the title short (large text, narrow windows).
  static _HeaderTools toolsThatFit(
    BuildContext context, {
    required double maxWidth,
    required int index,
    required int total,
  }) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    double widthOf(String text, TextStyle? style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    final title = widthOf(
      '${l10n.prompt_groupLabel(index + 1)} / $total',
      _titleStyle(theme),
    );
    final done = math.max(
      64.0,
      widthOf(l10n.common_done, theme.textTheme.labelLarge) +
          _donePadding.horizontal,
    );
    final base = _padding.horizontal + 2 * _arrowExtent + title + 8 + done;
    if (base + _toggleWidth + 4 + _menuWidth + 8 <= maxWidth) {
      return _HeaderTools.toggleAndMenu;
    }
    if (base + _menuWidth + 8 <= maxWidth) return _HeaderTools.menu;
    return _HeaderTools.none;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: _padding,
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
                          style: _titleStyle(theme),
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
          if (tools.isNotEmpty) ...[
            Row(
              key: const ValueKey('prompt_group_edit_header_tools'),
              mainAxisSize: MainAxisSize.min,
              children: [
                tools.first,
                const SizedBox(width: 4),
                ...tools.skip(1),
              ],
            ),
            const SizedBox(width: 8),
          ],
          FilledButton.tonal(
            key: const ValueKey('prompt_group_edit_done'),
            onPressed: onDone,
            style: FilledButton.styleFrom(padding: _donePadding),
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

/// The 分词 key (scissors): ends the tag at the caret with an English
/// comma, so tags can be split without switching the keyboard out of Chinese
/// input. It shares the neutral fill of the editor's other control pills and
/// keeps the field focused.
class _SplitKey extends StatelessWidget {
  const _SplitKey({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return TextFieldTapRegion(
      child: Tooltip(
        message: context.l10n.prompt_insertComma,
        child: TextButton(
          key: const ValueKey('prompt_group_edit_comma'),
          onPressed: onPressed,
          style: PromptFooterStyle.button(context, width: 56).copyWith(
            backgroundColor: WidgetStatePropertyAll(
              colors.surfaceContainerHigh,
            ),
            foregroundColor: WidgetStatePropertyAll(colors.onSurface),
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 16),
            ),
          ),
          child: const Icon(Icons.content_cut_rounded, size: 20),
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
