import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/utils/localization_extension.dart';
import '../../../data/services/dlss/dlss_options.dart';
import '../../widgets/common/one_line_field_width.dart';
import 'dlss_parameter_row.dart';

class DlssParameterSlider extends StatefulWidget {
  const DlssParameterSlider({
    super.key,
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
    this.minimum = 0,
    this.maximum,
    this.valueLabel,
  });

  final String label;
  final String description;
  final double value;
  final ValueChanged<double>? onChanged;
  final double minimum;
  final double? maximum;
  final String? valueLabel;

  @override
  State<DlssParameterSlider> createState() => _DlssParameterSliderState();
}

class _DlssParameterSliderState extends State<DlssParameterSlider> {
  late final TextEditingController _text;
  final _focus = FocusNode();
  bool _invalid = false;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: _formattedValue);
    _focus.addListener(_onFocusChanged);
  }

  String get _formattedValue => _format(widget.value);

  /// Two decimals at most, without trailing zeros: slider steps of 0.05
  /// come back as 0.6500000000000001 and would not fit the field.
  static String _format(double value) {
    final fixed = value.toStringAsFixed(2);
    if (!fixed.contains('.')) return fixed;
    final trimmed = fixed.replaceFirst(RegExp(r'0+$'), '');
    return trimmed.endsWith('.') ? '${trimmed}0' : trimmed;
  }

  @override
  void didUpdateWidget(covariant DlssParameterSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _text.text = _formattedValue;
      _invalid = false;
    }
  }

  void _onFocusChanged() {
    if (!_focus.hasFocus) _submit();
  }

  void _submit() {
    if (!mounted || widget.onChanged == null) return;
    final value = double.tryParse(_text.text.trim());
    final valid =
        value != null &&
        value.isFinite &&
        value >= widget.minimum &&
        value <= (widget.maximum ?? DlssOptions.maximumStrength);
    setState(() => _invalid = !valid);
    if (valid && value != widget.value) widget.onChanged!(value);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChanged);
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maximum = math.max(
      math.min(widget.maximum ?? 2.0, 4.0),
      widget.value,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DlssParameterRow(
            label: widget.label,
            description: widget.description,
            valueLabel: widget.valueLabel,
            error: _invalid ? context.l10n.dlss_invalidNumber : null,
            trailingWidth: oneLineFieldWidth(
              context,
              samples: [
                _formattedValue,
                _format(widget.minimum),
                _format(maximum),
              ],
              // Content padding on both sides and what the outlined
              // decoration keeps beside it.
              horizontalPadding: 32,
              minWidth: 96,
            ),
            trailing: Semantics(
              label: widget.label,
              child: TextField(
                key: ValueKey('dlss-value-${widget.label}'),
                controller: _text,
                focusNode: _focus,
                enabled: widget.onChanged != null,
                keyboardType: TextInputType.numberWithOptions(
                  decimal: true,
                  signed: widget.minimum < 0,
                ),
                textInputAction: TextInputAction.done,
                textAlign: TextAlign.center,
                textAlignVertical: TextAlignVertical.center,
                decoration: dlssNumberDecoration(context),
                onSubmitted: (_) => _submit(),
                onTapOutside: (_) => _focus.unfocus(),
              ),
            ),
          ),
          Slider(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            value: widget.value,
            min: widget.minimum,
            max: maximum,
            divisions: maximum <= 2
                ? ((maximum - widget.minimum) / 0.05).round()
                : null,
            label: widget.valueLabel ?? _formattedValue,
            semanticFormatterCallback: (value) => '${widget.label}: $value',
            onChanged: widget.onChanged,
          ),
        ],
      ),
    );
  }
}
