import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../adaptive/interaction_policy.dart';
import '../../themes/core/input_surface_style.dart';
import 'one_line_field_width.dart';

/// A compact field for typing a number, sized to its values so the number
/// never scrolls sideways under the finger.
class EditableDoubleField extends StatefulWidget {
  const EditableDoubleField({
    super.key,
    required this.value,
    required this.onChanged,
    this.min,
    this.max,
    this.decimals = 2,
    this.width = 64,
    this.textStyle,
    this.enabled = true,
  }) : assert(min == null || max == null || min <= max);

  final double value;
  final double? min;
  final double? max;
  final ValueChanged<double> onChanged;
  final int decimals;
  final double width;
  final TextStyle? textStyle;
  final bool enabled;

  /// Horizontal content padding of the field, both sides together.
  static const double _horizontalPadding = 16;

  /// What the outlined decoration takes beside the padding.
  static const double _decorationRoom = 8;

  /// The width the field takes for [value] and its bounds: at least
  /// [width], and wide enough for the widest of the three when formatted.
  /// Callers that share a row with the field use it to decide whether the
  /// field still fits beside the rest.
  static double widthFor(
    BuildContext context, {
    required double value,
    double? min,
    double? max,
    int decimals = 2,
    double width = 64,
    TextStyle? textStyle,
  }) {
    String format(double number) => number.toStringAsFixed(decimals);
    return oneLineFieldWidth(
      context,
      samples: [
        format(value),
        if (min != null && min.isFinite) format(min),
        if (max != null && max.isFinite) format(max),
      ],
      style: textStyle,
      horizontalPadding: _horizontalPadding + _decorationRoom,
      minWidth: width,
    );
  }

  @override
  State<EditableDoubleField> createState() => _EditableDoubleFieldState();
}

class _EditableDoubleFieldState extends State<EditableDoubleField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _format(widget.value));
    _focusNode = FocusNode()..addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant EditableDoubleField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled ||
        (!_focusNode.hasFocus && oldWidget.value != widget.value)) {
      _controller.text = _format(widget.value);
    }
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (!_focusNode.hasFocus) {
      _commit();
    }
  }

  void _commit() {
    if (!widget.enabled) {
      _controller.text = _format(widget.value);
      return;
    }
    final parsed = double.tryParse(_controller.text.trim());
    if (parsed == null || !parsed.isFinite) {
      _controller.text = _format(widget.value);
      return;
    }

    var normalized = parsed;
    final min = widget.min;
    final max = widget.max;
    if (min != null && normalized < min) {
      normalized = min;
    }
    if (max != null && normalized > max) {
      normalized = max;
    }
    if (normalized != widget.value) {
      widget.onChanged(normalized);
    }
    _controller.text = _format(normalized);
  }

  String _format(double value) => value.toStringAsFixed(widget.decimals);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The estimate keeps the width steady while the value moves; the field's
    // own intrinsic width covers what the estimate cannot see (the
    // decoration, the caret, a longer number being typed).
    final minWidth = EditableDoubleField.widthFor(
      context,
      value: widget.value,
      min: widget.min,
      max: widget.max,
      decimals: widget.decimals,
      width: widget.width,
      textStyle: widget.textStyle,
    );

    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: minWidth,
        minHeight: context.interactionPolicy.minimumControlExtent,
      ),
      child: IntrinsicWidth(
        child: TextField(
          controller: _controller,
          focusNode: _focusNode,
          enabled: widget.enabled,
          textAlign: TextAlign.right,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[-0-9.]')),
          ],
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 6,
            ),
            filled: true,
            fillColor: inputSurfaceFillColor(theme.colorScheme),
            border: inputSurfaceBorder(
              theme.colorScheme,
              BorderRadius.circular(8),
            ),
            enabledBorder: inputSurfaceBorder(
              theme.colorScheme,
              BorderRadius.circular(8),
            ),
            focusedBorder: inputSurfaceBorder(
              theme.colorScheme,
              BorderRadius.circular(8),
              focused: true,
            ),
          ),
          style: widget.textStyle,
          onSubmitted: (_) => _commit(),
        ),
      ),
    );
  }
}
