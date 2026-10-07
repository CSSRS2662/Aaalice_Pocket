import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../themes/core/layered_surface_style.dart';
import '../../../themes/theme_extension.dart';
import 'prompt_group_controller.dart';
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
  });

  final PromptGroupCollection groups;
  final ValueChanged<String> onOpen;
  final ValueChanged<String> onShowActions;
  final ValueChanged<String> onToggleEnabled;
  final ValueChanged<String> onDelete;
  final VoidCallback onReordered;

  static const double gap = 10;
  static const int maxColumns = 4;

  /// Narrowest tile at normal text size; large text widens it. The dot and
  /// cross take 88 of it, leaving room for the first tags.
  static const double minTileWidth = 160;

  @override
  State<PromptGroupGrid> createState() => _PromptGroupGridState();
}

class _GridGeometry {
  const _GridGeometry(this.columns, this.tileWidth, this.tileHeight);

  final int columns;
  final double tileWidth;
  final double tileHeight;

  Offset origin(int index) => Offset(
    (index % columns) * (tileWidth + PromptGroupGrid.gap),
    (index ~/ columns) * (tileHeight + PromptGroupGrid.gap),
  );

  double heightFor(int count) {
    final rows = (count / columns).ceil();
    return rows * tileHeight + math.max(0, rows - 1) * PromptGroupGrid.gap;
  }

  int indexAt(Offset position, int count) {
    final column = (position.dx / (tileWidth + PromptGroupGrid.gap))
        .floor()
        .clamp(0, columns - 1);
    final row = math.max(
      0,
      (position.dy / (tileHeight + PromptGroupGrid.gap)).floor(),
    );
    return (row * columns + column).clamp(0, count - 1);
  }
}

class _DragState {
  _DragState({
    required this.id,
    required this.order,
    required this.grabOffset,
    required this.startGlobal,
    required this.topLeft,
  });

  final String id;
  final List<String> order;
  final Offset grabOffset;
  final Offset startGlobal;
  Offset topLeft;
  Offset lastGlobal = Offset.zero;
  bool moved = false;
}

class _PromptGroupGridState extends State<PromptGroupGrid> {
  static const Duration _armDuration = Duration(seconds: 3);
  static const double _autoScrollEdge = 56;
  static const double _autoScrollStep = 8;

  final GlobalKey _stackKey = GlobalKey();
  _GridGeometry? _geometry;
  _DragState? _drag;
  Timer? _autoScroll;
  String? _armedId;
  Timer? _armTimer;

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
      _cancelDrag();
      _disarm();
    }
  }

  @override
  void dispose() {
    widget.groups.removeListener(_onGroupsChanged);
    _autoScroll?.cancel();
    _armTimer?.cancel();
    super.dispose();
  }

  void _onGroupsChanged() {
    if (!mounted) return;
    final drag = _drag;
    if (drag != null && widget.groups.sectionById(drag.id) == null) {
      _cancelDrag();
    }
    if (_armedId != null && widget.groups.sectionById(_armedId!) == null) {
      _disarm();
    }
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

  // ---- Two-tap delete ----

  void _onDeleteTap(String id) {
    if (_armedId == id) {
      _disarm();
      widget.onDelete(id);
      return;
    }
    _armTimer?.cancel();
    _armTimer = Timer(_armDuration, _disarm);
    setState(() => _armedId = id);
  }

  void _disarm() {
    _armTimer?.cancel();
    _armTimer = null;
    if (_armedId == null || !mounted) return;
    setState(() => _armedId = null);
  }

  // ---- Long-press drag ----

  Offset? _toLocal(Offset global) {
    final box = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    return box?.globalToLocal(global);
  }

  void _startDrag(String id, LongPressStartDetails details) {
    final geometry = _geometry;
    final local = _toLocal(details.globalPosition);
    final order = [for (final section in widget.groups.sections) section.id];
    final index = order.indexOf(id);
    if (geometry == null || local == null || index < 0) return;
    _disarm();
    HapticFeedback.mediumImpact();
    final origin = geometry.origin(index);
    setState(() {
      _drag = _DragState(
        id: id,
        order: order,
        grabOffset: local - origin,
        startGlobal: details.globalPosition,
        topLeft: origin,
      )..lastGlobal = details.globalPosition;
    });
  }

  void _updateDrag(Offset global) {
    final drag = _drag;
    final geometry = _geometry;
    if (drag == null || geometry == null) return;
    drag.lastGlobal = global;
    if ((global - drag.startGlobal).distance > kTouchSlop) drag.moved = true;
    final local = _toLocal(global);
    if (local == null) return;
    final target = geometry.indexAt(local, drag.order.length);
    setState(() {
      drag.topLeft = local - drag.grabOffset;
      final current = drag.order.indexOf(drag.id);
      if (target != current) {
        drag.order
          ..removeAt(current)
          ..insert(target, drag.id);
      }
    });
    _updateAutoScroll(global);
  }

  void _endDrag() {
    final drag = _drag;
    if (drag == null) return;
    _stopAutoScroll();
    setState(() => _drag = null);
    if (!drag.moved) {
      widget.onShowActions(drag.id);
      return;
    }
    final target = drag.order.indexOf(drag.id);
    if (target != widget.groups.indexOf(drag.id)) {
      widget.groups.move(drag.id, target);
      widget.onReordered();
    }
  }

  void _cancelDrag() {
    _stopAutoScroll();
    _drag = null;
  }

  void _updateAutoScroll(Offset global) {
    final scrollable = Scrollable.maybeOf(context);
    final box = scrollable?.context.findRenderObject() as RenderBox?;
    if (scrollable == null || box == null || !box.hasSize) return;
    final top = box.localToGlobal(Offset.zero).dy;
    final bottom = top + box.size.height;
    final direction = global.dy < top + _autoScrollEdge
        ? -1
        : global.dy > bottom - _autoScrollEdge
        ? 1
        : 0;
    if (direction == 0) return _stopAutoScroll();
    _autoScroll ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
      final drag = _drag;
      if (drag == null || !mounted) return _stopAutoScroll();
      final position = scrollable.position;
      final next = (position.pixels + direction * _autoScrollStep).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if (next == position.pixels) return;
      position.jumpTo(next);
      _updateDrag(drag.lastGlobal);
    });
  }

  void _stopAutoScroll() {
    _autoScroll?.cancel();
    _autoScroll = null;
  }

  // ---- Layout ----

  _GridGeometry _layout(BuildContext context, double width) {
    final metrics = PromptGroupTileMetrics.of(context);
    final textScale = MediaQuery.textScalerOf(context).scale(13) / 13;
    final minTile =
        PromptGroupGrid.minTileWidth * textScale.clamp(1.0, 2.0).toDouble();
    final columns =
        ((width + PromptGroupGrid.gap) / (minTile + PromptGroupGrid.gap))
            .floor()
            .clamp(1, PromptGroupGrid.maxColumns);
    final tileWidth = (width - PromptGroupGrid.gap * (columns - 1)) / columns;
    return _GridGeometry(columns, tileWidth, metrics.height);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final geometry = _layout(context, constraints.maxWidth);
        _geometry = geometry;
        final metrics = PromptGroupTileMetrics.of(context);
        final drag = _drag;
        final sections = widget.groups.sections;
        final order = drag?.order ?? [for (final s in sections) s.id];
        final duration = MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 180);
        final curve = Theme.of(context).appTheme.standardCurve;

        Widget positioned(Key key, int index, Widget child) {
          final origin = geometry.origin(index);
          return AnimatedPositioned(
            key: key,
            duration: duration,
            curve: curve,
            left: origin.dx,
            top: origin.dy,
            width: geometry.tileWidth,
            height: geometry.tileHeight,
            child: child,
          );
        }

        final children = <Widget>[
          for (final (index, id) in order.indexed)
            if (widget.groups.sectionById(id) case final section?)
              positioned(
                ValueKey('prompt_group_slot_$id'),
                index,
                _buildTile(section, widget.groups.indexOf(id), metrics),
              ),
          positioned(
            const ValueKey('prompt_group_slot_add'),
            order.length,
            _AddGroupTile(onTap: widget.groups.add),
          ),
        ];
        if (drag != null) {
          final section = widget.groups.sectionById(drag.id);
          if (section != null) {
            children.add(
              Positioned(
                left: drag.topLeft.dx,
                top: drag.topLeft.dy,
                width: geometry.tileWidth,
                height: geometry.tileHeight,
                child: IgnorePointer(
                  child: Transform.scale(
                    scale: 1.04,
                    child: Material(
                      elevation: 8,
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(
                        Theme.of(context).appTheme.cardRadius,
                      ),
                      child: _tileVisual(section, metrics),
                    ),
                  ),
                ),
              ),
            );
          }
        }

        return SizedBox(
          height: geometry.heightFor(order.length + 1),
          child: Stack(
            key: _stackKey,
            clipBehavior: Clip.none,
            children: children,
          ),
        );
      },
    );
  }

  Widget _buildTile(
    PromptGroupSection section,
    int index,
    PromptGroupTileMetrics metrics,
  ) {
    final id = section.id;
    return GestureDetector(
      onLongPressStart: (details) => _startDrag(id, details),
      onLongPressMoveUpdate: (details) => _updateDrag(details.globalPosition),
      onLongPressEnd: (_) => _endDrag(),
      onSecondaryTapUp: (_) => widget.onShowActions(id),
      child: _drag?.id == id
          ? const PromptGroupTilePlaceholder()
          : _tileVisual(section, metrics, index: index),
    );
  }

  Widget _tileVisual(
    PromptGroupSection section,
    PromptGroupTileMetrics metrics, {
    int? index,
  }) {
    final id = section.id;
    return PromptGroupTile(
      section: section,
      index: index ?? widget.groups.indexOf(id),
      metrics: metrics,
      deleteArmed: _armedId == id,
      onOpen: () => widget.onOpen(id),
      onToggleEnabled: () => widget.onToggleEnabled(id),
      onDeleteTap: () => _onDeleteTap(id),
      onDisarmDelete: _disarm,
      onShowActions: () => widget.onShowActions(id),
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
