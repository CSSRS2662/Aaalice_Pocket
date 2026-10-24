import 'package:flutter/material.dart';

import '../../../core/utils/localization_extension.dart';
import '../../adaptive/interaction_policy.dart';
import '../../../data/models/fixed_tag/fixed_tag_prompt_type.dart';
import '../common/themed_switch.dart';
import 'fixed_tags_dialog_models.dart';
import 'fixed_tags_dialog_controller.dart';

enum FixedTagHeaderAction {
  toggleAll,
  enabledOnly,
  reorder,
  openLibrary,
  clearAll,
}

enum _AddAction { create, library }

class FixedTagsDialogHeader extends StatelessWidget {
  const FixedTagsDialogHeader({
    required this.controller,
    super.key,
    required this.data,
    required this.commands,
    required this.isCompact,
    this.showClose = true,
  });

  final FixedTagsDialogViewData data;
  final FixedTagsDialogCommands commands;
  final bool isCompact;
  final FixedTagsDialogController controller;

  /// Off in a bottom sheet, which closes by swipe or back.
  final bool showClose;

  @override
  Widget build(BuildContext context) {
    final enabledCount = data.state.entries
        .where((entry) => entry.enabled)
        .length;
    final totalCount = data.state.entries.length;
    if (isCompact) {
      return _CompactHeader(
        controller: controller,
        data: data,
        commands: commands,
        showClose: showClose,
      );
    }
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('fixed-tags-dialog-header'),
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.24),
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer.withValues(
                alpha: 0.5,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.push_pin_rounded,
              color: theme.colorScheme.onSecondaryContainer,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.l10n.fixedTags_manage,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (totalCount > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${context.l10n.fixedTags_enabledCount(enabledCount.toString(), totalCount.toString())} · ${context.l10n.fixedTags_linkCount(data.state.links.length)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          TextButton.icon(
            onPressed: commands.toggleNegativePanel,
            icon: Icon(
              data.state.negativePanelExpanded
                  ? Icons.keyboard_tab_rounded
                  : Icons.view_sidebar_rounded,
              size: 18,
            ),
            label: Text(
              data.state.negativePanelExpanded
                  ? context.l10n.fixedTags_collapseNegative
                  : context.l10n.fixedTags_expandNegative,
            ),
          ),
          IconButton(
            tooltip: context.l10n.fixedTags_undoTooltip,
            onPressed: data.state.canUndo ? commands.undo : null,
            icon: const Icon(Icons.undo_rounded, size: 18),
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            tooltip: context.l10n.fixedTags_redoTooltip,
            onPressed: data.state.canRedo ? commands.redo : null,
            icon: const Icon(Icons.redo_rounded, size: 18),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 8),
          if (totalCount > 0) ...[
            Row(
              key: const ValueKey('fixed-tags-global-toggle'),
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  enabledCount == totalCount
                      ? context.l10n.fixedTags_disableAll
                      : context.l10n.fixedTags_enableAll,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 6),
                Tooltip(
                  message: enabledCount == totalCount
                      ? context.l10n.fixedTags_disableAll
                      : context.l10n.fixedTags_enableAll,
                  child: ThemedSwitch(
                    value: enabledCount == totalCount,
                    onChanged: commands.setAllEnabled,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 8),
          ],
          IconButton(
            key: const ValueKey('fixed-tags-reorder-toggle'),
            tooltip: controller.reordering
                ? context.l10n.fixedTags_reorderDone
                : context.l10n.fixedTags_reorder,
            isSelected: controller.reordering,
            onPressed: () => controller.setReordering(!controller.reordering),
            icon: const Icon(Icons.swap_vert_rounded),
          ),
          _EnabledOnlyToggle(controller: controller),
          IconButton(
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            constraints: BoxConstraints.tightFor(
              width: context.interactionPolicy.minimumControlExtent,
              height: context.interactionPolicy.minimumControlExtent,
            ),
            onPressed: commands.close,
            icon: Icon(
              Icons.close_rounded,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactHeader extends StatelessWidget {
  const _CompactHeader({
    required this.controller,
    required this.data,
    required this.commands,
    required this.showClose,
  });
  final FixedTagsDialogViewData data;
  final FixedTagsDialogCommands commands;
  final FixedTagsDialogController controller;
  final bool showClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The phone shows one tab at a time, so "enable all" follows that tab.
    final promptType = controller.mobilePromptType;
    final tabTitle = promptType == FixedTagPromptType.positive
        ? context.l10n.fixedTags_positiveTitle
        : context.l10n.fixedTags_negativeTitle;
    final tabEntries = promptType == FixedTagPromptType.positive
        ? data.state.positiveEntries
        : data.state.negativeEntries;
    final tabAllEnabled =
        tabEntries.isNotEmpty && tabEntries.every((entry) => entry.enabled);
    return Padding(
      key: const ValueKey('fixed-tags-dialog-header'),
      padding: const EdgeInsets.fromLTRB(20, 8, 8, 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.l10n.fixedTags_label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  context.l10n.fixedTags_subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: const ValueKey('fixed-tags-undo'),
            tooltip: context.l10n.fixedTags_undoTooltip,
            onPressed: data.state.canUndo ? commands.undo : null,
            icon: const Icon(Icons.undo_rounded),
          ),
          IconButton(
            key: const ValueKey('fixed-tags-redo'),
            tooltip: context.l10n.fixedTags_redoTooltip,
            onPressed: data.state.canRedo ? commands.redo : null,
            icon: const Icon(Icons.redo_rounded),
          ),
          PopupMenuButton<_AddAction>(
            key: const ValueKey('fixed-tags-add-menu'),
            tooltip: context.l10n.fixedTags_addMenu,
            icon: const Icon(Icons.add_rounded),
            onSelected: (action) => switch (action) {
              _AddAction.create => commands.editEntry(null, promptType),
              _AddAction.library => commands.pickFromLibrary(promptType),
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                key: const ValueKey('fixed-tags-add-new'),
                value: _AddAction.create,
                child: _MenuRow(
                  icon: Icons.add_rounded,
                  label: context.l10n.fixedTags_newTarget(tabTitle),
                ),
              ),
              PopupMenuItem(
                key: const ValueKey('fixed-tags-add-library'),
                value: _AddAction.library,
                child: _MenuRow(
                  icon: Icons.playlist_add_rounded,
                  label: context.l10n.fixedTags_addFromLibrary,
                ),
              ),
            ],
          ),
          PopupMenuButton<FixedTagHeaderAction>(
            key: const ValueKey('fixed-tags-header-menu'),
            tooltip: MaterialLocalizations.of(context).moreButtonTooltip,
            onSelected: (action) {
              switch (action) {
                case FixedTagHeaderAction.toggleAll:
                  commands.setPromptTypeEnabled(promptType, !tabAllEnabled);
                case FixedTagHeaderAction.enabledOnly:
                  controller.toggleEnabledOnly();
                case FixedTagHeaderAction.reorder:
                  controller.setReordering(!controller.reordering);
                case FixedTagHeaderAction.openLibrary:
                  commands.openLibraryPage();
                case FixedTagHeaderAction.clearAll:
                  commands.clearAll();
              }
            },
            itemBuilder: (_) => [
              if (tabEntries.isNotEmpty)
                PopupMenuItem(
                  key: const ValueKey('fixed-tags-menu-toggle-all'),
                  value: FixedTagHeaderAction.toggleAll,
                  child: _MenuRow(
                    icon: tabAllEnabled
                        ? Icons.remove_done_rounded
                        : Icons.done_all_rounded,
                    label: tabAllEnabled
                        ? context.l10n.fixedTags_disableAll
                        : context.l10n.fixedTags_enableAll,
                  ),
                ),
              PopupMenuItem(
                key: const ValueKey('fixed-tags-menu-enabled-only'),
                value: FixedTagHeaderAction.enabledOnly,
                child: _MenuRow(
                  icon: controller.enabledOnly
                      ? Icons.filter_alt_rounded
                      : Icons.filter_alt_outlined,
                  label: context.l10n.fixedTags_enabledOnly,
                  checked: controller.enabledOnly,
                ),
              ),
              if (tabEntries.length > 1)
                PopupMenuItem(
                  key: const ValueKey('fixed-tags-menu-reorder'),
                  value: FixedTagHeaderAction.reorder,
                  child: _MenuRow(
                    icon: Icons.swap_vert_rounded,
                    label: controller.reordering
                        ? context.l10n.fixedTags_reorderDone
                        : context.l10n.fixedTags_reorder,
                  ),
                ),
              PopupMenuItem(
                key: const ValueKey('fixed-tags-menu-open-library'),
                value: FixedTagHeaderAction.openLibrary,
                child: _MenuRow(
                  icon: Icons.library_books_outlined,
                  label: context.l10n.fixedTags_openLibrary,
                ),
              ),
              if (data.state.entries.isNotEmpty)
                PopupMenuItem(
                  value: FixedTagHeaderAction.clearAll,
                  child: _MenuRow(
                    icon: Icons.delete_sweep_outlined,
                    label: context.l10n.fixedTags_clearAll,
                    color: theme.colorScheme.error,
                  ),
                ),
            ],
          ),
          if (showClose)
            IconButton(
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onPressed: commands.close,
              icon: const Icon(Icons.close_rounded),
            ),
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    this.color,
    this.checked = false,
  });

  final IconData icon;
  final String label;
  final Color? color;
  final bool checked;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 20, color: color),
      const SizedBox(width: 12),
      Expanded(
        child: Text(label, style: TextStyle(color: color)),
      ),
      if (checked) ...[
        const SizedBox(width: 12),
        Icon(
          Icons.check_rounded,
          size: 18,
          color: Theme.of(context).colorScheme.primary,
        ),
      ],
    ],
  );
}

class _EnabledOnlyToggle extends StatelessWidget {
  const _EnabledOnlyToggle({required this.controller});

  final FixedTagsDialogController controller;

  @override
  Widget build(BuildContext context) => IconButton(
    key: const ValueKey('fixed-tags-enabled-only'),
    tooltip: context.l10n.fixedTags_enabledOnly,
    isSelected: controller.enabledOnly,
    icon: const Icon(Icons.filter_alt_outlined),
    selectedIcon: const Icon(Icons.filter_alt),
    onPressed: controller.toggleEnabledOnly,
  );
}

class FixedTagsDialogFooter extends StatelessWidget {
  const FixedTagsDialogFooter({
    super.key,
    required this.data,
    required this.commands,
  });
  final FixedTagsDialogViewData data;
  final FixedTagsDialogCommands commands;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('fixed-tags-dialog-footer'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.24),
          ),
        ),
      ),
      child: Row(
        children: [
          OutlinedButton.icon(
            onPressed: commands.openLibraryPage,
            icon: const Icon(Icons.library_books_outlined, size: 17),
            label: Text(context.l10n.fixedTags_openLibrary),
          ),
          const SizedBox(width: 8),
          if (data.state.entries.isNotEmpty)
            OutlinedButton.icon(
              onPressed: commands.clearAll,
              icon: Icon(
                Icons.delete_sweep_outlined,
                size: 17,
                color: theme.colorScheme.error,
              ),
              label: Text(
                context.l10n.fixedTags_clearAll,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          const Spacer(),
          if (data.state.negativePanelExpanded)
            Text(
              context.l10n.fixedTags_footerExpandedHint,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            )
          else ...[
            FilledButton.tonalIcon(
              onPressed: () =>
                  commands.editEntry(null, FixedTagPromptType.positive),
              icon: const Icon(Icons.add_rounded, size: 17),
              label: Text(context.l10n.fixedTags_newPositive),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: () =>
                  commands.pickFromLibrary(FixedTagPromptType.positive),
              icon: const Icon(Icons.playlist_add_rounded, size: 17),
              label: Text(context.l10n.fixedTags_addPositiveFromLibraryShort),
            ),
          ],
        ],
      ),
    );
  }
}
