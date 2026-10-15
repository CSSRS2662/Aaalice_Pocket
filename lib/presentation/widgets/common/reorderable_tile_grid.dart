import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../themes/theme_extension.dart';

/// Controls the grid owns for one tile: the two-tap delete arming.
class ReorderableTileControls {
  const ReorderableTileControls({
    required this.deleteArmed,
    required this.onDeleteTap,
    required this.onDisarmDelete,
  });

  static final ReorderableTileControls idle = ReorderableTileControls(
    deleteArmed: false,
    onDeleteTap: () {},
    onDisarmDelete: () {},
  );

  final bool deleteArmed;
  final VoidCallback onDeleteTap;
  final VoidCallback onDisarmDelete;
}

typedef ReorderableTileBuilder =
    Widget Function(
      BuildContext context,
      String id,
      ReorderableTileControls controls,
    );

/// Fixed-height tiles in equal columns.
///
/// Long press and drag reorders with the other tiles making room live and the
/// enclosing scroll view following the finger near its edges; a long press
/// released in place reports [onLongPressInPlace]. A tile's delete control arms
/// on the first tap and deletes on a second tap within three seconds.
class ReorderableTileGrid extends StatefulWidget {
  const ReorderableTileGrid({
    super.key,
    required this.ids,
    required this.tileHeight,
    required this.minTileWidth,
    required this.tileBuilder,
    required this.placeholder,
    required this.onMove,
    required this.onDelete,
    this.trailing,
    this.onLongPressInPlace,
    this.onSecondaryTap,
    this.slotKeyPrefix = 'reorderable_tile_slot_',
    this.gap = 10,
    this.maxColumns = 4,
  });

  /// Tile ids in their current order.
  final List<String> ids;
  final double tileHeight;

  /// Narrowest tile at normal text size; large text widens it.
  final double minTileWidth;
  final ReorderableTileBuilder tileBuilder;

  /// Empty slot left behind while its tile is being dragged.
  final Widget placeholder;

  /// A tile dropped at a new index.
  final void Function(String id, int index) onMove;

  /// The second tap on an armed delete control.
  final ValueChanged<String> onDelete;

  /// Extra tile after the last one, such as an add button.
  final Widget? trailing;
  final ValueChanged<String>? onLongPressInPlace;
  final ValueChanged<String>? onSecondaryTap;

  /// Slot keys are `$slotKeyPrefix$id`, and `${slotKeyPrefix}add` for
  /// [trailing].
  final String slotKeyPrefix;
  final double gap;
  final int maxColumns;

  @override
  State<ReorderableTileGrid> createState() => _ReorderableTileGridState();
}

class _GridGeometry {
  const _GridGeometry(this.columns, this.tileWidth, this.tileHeight, this.gap);

  final int columns;
  final double tileWidth;
  final double tileHeight;
  final double gap;

  Offset origin(int index) => Offset(
    (index % columns) * (tileWidth + gap),
    (index ~/ columns) * (tileHeight + gap),
  );

  double heightFor(int count) {
    final rows = (count / columns).ceil();
    return rows * tileHeight + math.max(0, rows - 1) * gap;
  }

  int indexAt(Offset position, int count) {
    final column = (position.dx / (tileWidth + gap)).floor().clamp(
      0,
      columns - 1,
    );
    final row = math.max(0, (position.dy / (tileHeight + gap)).floor());
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

class _ReorderableTileGridState extends State<ReorderableTileGrid> {
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
  void didUpdateWidget(ReorderableTileGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    final drag = _drag;
    if (drag != null && !widget.ids.contains(drag.id)) _cancelDrag();
    if (_armedId != null && !widget.ids.contains(_armedId)) {
      _armTimer?.cancel();
      _armTimer = null;
      _armedId = null;
    }
  }

  @override
  void dispose() {
    _autoScroll?.cancel();
    _armTimer?.cancel();
    super.dispose();
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

  ReorderableTileControls _controlsFor(String id) => ReorderableTileControls(
    deleteArmed: _armedId == id,
    onDeleteTap: () => _onDeleteTap(id),
    onDisarmDelete: _disarm,
  );

  // ---- Long-press drag ----

  Offset? _toLocal(Offset global) {
    final box = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    return box?.globalToLocal(global);
  }

  void _startDrag(String id, LongPressStartDetails details) {
    final geometry = _geometry;
    final local = _toLocal(details.globalPosition);
    final order = List<String>.of(widget.ids);
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
      widget.onLongPressInPlace?.call(drag.id);
      return;
    }
    final target = drag.order.indexOf(drag.id);
    if (target != widget.ids.indexOf(drag.id)) widget.onMove(drag.id, target);
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
    final textScale = MediaQuery.textScalerOf(context).scale(13) / 13;
    final minTile = widget.minTileWidth * textScale.clamp(1.0, 2.0).toDouble();
    final columns = ((width + widget.gap) / (minTile + widget.gap))
        .floor()
        .clamp(1, widget.maxColumns);
    final tileWidth = (width - widget.gap * (columns - 1)) / columns;
    return _GridGeometry(columns, tileWidth, widget.tileHeight, widget.gap);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final geometry = _layout(context, constraints.maxWidth);
        _geometry = geometry;
        final drag = _drag;
        final order = drag?.order ?? widget.ids;
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

        final trailing = widget.trailing;
        final children = <Widget>[
          for (final (index, id) in order.indexed)
            if (widget.ids.contains(id))
              positioned(
                ValueKey('${widget.slotKeyPrefix}$id'),
                index,
                _buildTile(context, id),
              ),
          if (trailing != null)
            positioned(
              ValueKey('${widget.slotKeyPrefix}add'),
              order.length,
              trailing,
            ),
        ];
        if (drag != null && widget.ids.contains(drag.id)) {
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
                    child: widget.tileBuilder(
                      context,
                      drag.id,
                      ReorderableTileControls.idle,
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        return SizedBox(
          height: geometry.heightFor(order.length + (trailing == null ? 0 : 1)),
          child: Stack(
            key: _stackKey,
            clipBehavior: Clip.none,
            children: children,
          ),
        );
      },
    );
  }

  Widget _buildTile(BuildContext context, String id) {
    final onSecondaryTap = widget.onSecondaryTap;
    return GestureDetector(
      onLongPressStart: (details) => _startDrag(id, details),
      onLongPressMoveUpdate: (details) => _updateDrag(details.globalPosition),
      onLongPressEnd: (_) => _endDrag(),
      onSecondaryTapUp: onSecondaryTap == null
          ? null
          : (_) => onSecondaryTap(id),
      child: _drag?.id == id
          ? widget.placeholder
          : widget.tileBuilder(context, id, _controlsFor(id)),
    );
  }
}

/// A bare cross; the first tap arms it as a red circle, the second deletes.
class ReorderableTileDeleteButton extends StatelessWidget {
  const ReorderableTileDeleteButton({
    super.key,
    required this.armed,
    required this.tooltip,
    required this.onTap,
    required this.onTapOutside,
    this.width = 44,
  });

  final bool armed;
  final String tooltip;
  final VoidCallback onTap;
  final VoidCallback onTapOutside;

  /// Touch target width; the target fills the height it is given.
  final double width;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return TapRegion(
      onTapOutside: armed ? (_) => onTapOutside() : null,
      child: Tooltip(
        message: tooltip,
        child: Semantics(
          button: true,
          child: InkResponse(
            onTap: onTap,
            radius: 22,
            child: SizedBox(
              width: width,
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: armed ? colors.error : Colors.transparent,
                  ),
                  child: Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: armed ? colors.onError : colors.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
