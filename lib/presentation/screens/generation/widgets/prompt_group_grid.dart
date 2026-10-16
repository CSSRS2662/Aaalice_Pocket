import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../themes/core/layered_surface_style.dart';
import '../../../themes/theme_extension.dart';
import '../../../widgets/common/reorderable_tile_grid.dart';
import 'prompt_group_controller.dart';
import 'prompt_group_fixed_tags.dart';
import 'prompt_group_tile.dart';

/// Prompt sections as a grid of fixed-height tiles.
///
/// Tap opens a section, the corner dot turns it on or off, the cross deletes
/// it after a second tap. Long press and drag reorders with the other tiles
/// making room live; a long press released in place opens the section menu.
class PromptGroupGrid extends StatefulWidget {
  const PromptGroupGrid({
    super.key,
    required this.groups,
    required this.onOpen,
    required this.onShowActions,
    required this.onToggleEnabled,
    required this.onDelete,
    required this.onReordered,
    this.minTileWidth = defaultMinTileWidth,
    this.fixedTagInfoOf,
  });

  final PromptGroupCollection groups;

  /// What fixed-tag tiles say about their tags.
  final PromptGroupFixedTagInfo? Function(PromptGroupSection section)?
  fixedTagInfoOf;

  /// Narrowest tile at normal text size; large text widens it. Hosts with
  /// less width, such as an open character row, pass less to keep two
  /// columns.
  final double minTileWidth;
  final ValueChanged<String> onOpen;
  final ValueChanged<String> onShowActions;
  final ValueChanged<String> onToggleEnabled;
  final ValueChanged<String> onDelete;
  final VoidCallback onReordered;

  static const double gap = 10;
  static const int maxColumns = 4;

  /// The dot and cross take 88 of a tile, leaving room for the first tags.
  static const double defaultMinTileWidth = 160;

  @override
  State<PromptGroupGrid> createState() => _PromptGroupGridState();
}

class _PromptGroupGridState extends State<PromptGroupGrid> {
  @override
  void initState() {
    super.initState();
    widget.groups.addListener(_onGroupsChanged);
    _scheduleEditRequest();
  }

  @override
  void didUpdateWidget(PromptGroupGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.groups, widget.groups)) {
      oldWidget.groups.removeListener(_onGroupsChanged);
      widget.groups.addListener(_onGroupsChanged);
    }
  }

  @override
  void dispose() {
    widget.groups.removeListener(_onGroupsChanged);
    super.dispose();
  }

  void _onGroupsChanged() {
    if (!mounted) return;
    // Sections can be restored while the prompt page itself is building.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
    _scheduleEditRequest();
  }

  void _scheduleEditRequest() {
    final id = widget.groups.takeEditRequest();
    if (id == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.groups.sectionById(id) != null) widget.onOpen(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final metrics = PromptGroupTileMetrics.of(context);
    final groups = widget.groups;
    return ReorderableTileGrid(
      ids: [for (final section in groups.sections) section.id],
      tileHeight: metrics.height,
      minTileWidth: widget.minTileWidth,
      gap: PromptGroupGrid.gap,
      maxColumns: PromptGroupGrid.maxColumns,
      slotKeyPrefix: 'prompt_group_slot_',
      placeholder: const PromptGroupTilePlaceholder(),
      trailing: _AddGroupTile(onTap: groups.add),
      onMove: (id, index) {
        groups.move(id, index);
        widget.onReordered();
      },
      onDelete: widget.onDelete,
      onLongPressInPlace: widget.onShowActions,
      onSecondaryTap: widget.onShowActions,
      tileBuilder: (context, id, controls) {
        final section = groups.sectionById(id);
        if (section == null) return const SizedBox.shrink();
        return PromptGroupTile(
          section: section,
          index: groups.indexOf(id),
          metrics: metrics,
          deleteArmed: controls.deleteArmed,
          onOpen: () => widget.onOpen(id),
          onToggleEnabled: () => widget.onToggleEnabled(id),
          onDeleteTap: controls.onDeleteTap,
          onDisarmDelete: controls.onDisarmDelete,
          onShowActions: () => widget.onShowActions(id),
          fixedTag: widget.fixedTagInfoOf?.call(section),
        );
      },
    );
  }
}

class _AddGroupTile extends StatelessWidget {
  const _AddGroupTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: controlSurfaceColor(colors),
      borderRadius: BorderRadius.circular(
        Theme.of(context).appTheme.cardRadius,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('prompt_group_add_tile'),
        onTap: onTap,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, color: colors.primary),
              const SizedBox(height: 2),
              Text(
                context.l10n.prompt_addGroup,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
