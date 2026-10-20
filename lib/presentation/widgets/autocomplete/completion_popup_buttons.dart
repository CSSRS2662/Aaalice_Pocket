import 'package:flutter/material.dart';

import '../../../core/utils/localization_extension.dart';
import '../../adaptive/interaction_policy.dart';

/// The 分词 key (scissors) that ends the tag being written with a comma,
/// standing in for the editor's own key while the popup covers it. It sits
/// on the bar's own colour like the other popup buttons.
class CompletionSplitButton extends StatelessWidget {
  const CompletionSplitButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => CompletionPopupIconButton(
    key: const ValueKey('autocomplete-popup-split'),
    tooltip: context.l10n.prompt_insertComma,
    icon: Icons.content_cut_rounded,
    onPressed: onPressed,
  );
}

/// The multi-select actions: leave the mode, or write the [count] picks.
/// Like the other popup controls they never take focus from the field.
class CompletionPickActions extends StatelessWidget {
  const CompletionPickActions({
    super.key,
    required this.count,
    required this.onCancel,
    required this.onInsert,
  });

  final int count;
  final VoidCallback onCancel;
  final VoidCallback onInsert;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final touch = context.interactionPolicy.touchAvailable;
    final style = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(
        Size(touch ? 48 : 0, touch ? 36 : 24),
      ),
      padding: WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: touch ? 12 : 10),
      ),
      tapTargetSize: touch
          ? MaterialTapTargetSize.padded
          : MaterialTapTargetSize.shrinkWrap,
      visualDensity: touch ? VisualDensity.standard : VisualDensity.compact,
    );
    return Focus(
      canRequestFocus: false,
      descendantsAreFocusable: false,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: l10n.autocomplete_leaveMultiSelect,
            child: TextButton(
              key: const ValueKey('autocomplete-pick-cancel'),
              style: style,
              onPressed: onCancel,
              child: Text(l10n.common_cancel, maxLines: 1),
            ),
          ),
          const SizedBox(width: 4),
          Tooltip(
            message: l10n.autocomplete_insertPickedTooltip(count),
            child: FilledButton.tonal(
              key: const ValueKey('autocomplete-pick-insert'),
              style: style,
              onPressed: onInsert,
              child: Text(l10n.autocomplete_insertPicked(count), maxLines: 1),
            ),
          ),
        ],
      ),
    );
  }
}

/// An icon button of the popup chrome that never takes focus from the field.
class CompletionPopupIconButton extends StatefulWidget {
  const CompletionPopupIconButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.active = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool active;

  /// Side of the button for the current input.
  static double extentOf(BuildContext context) {
    final policy = context.interactionPolicy;
    return policy.touchAvailable ? policy.minimumControlExtent : 28;
  }

  @override
  State<CompletionPopupIconButton> createState() =>
      _CompletionPopupIconButtonState();
}

class _CompletionPopupIconButtonState extends State<CompletionPopupIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final policy = context.interactionPolicy;
    final extent = CompletionPopupIconButton.extentOf(context);
    return Focus(
      canRequestFocus: false,
      descendantsAreFocusable: false,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: policy.precisePointerAvailable
            ? (_) => setState(() => _hovered = true)
            : null,
        onExit: policy.precisePointerAvailable
            ? (_) => setState(() => _hovered = false)
            : null,
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: _hovered || widget.active
                ? colors.primary.withValues(alpha: widget.active ? 0.2 : 0.16)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: IconButton(
            tooltip: widget.tooltip,
            visualDensity: policy.touchAvailable
                ? VisualDensity.standard
                : VisualDensity.compact,
            constraints: BoxConstraints.tightFor(width: extent, height: extent),
            padding: EdgeInsets.zero,
            iconSize: policy.touchAvailable ? 20 : 16,
            color: _hovered || widget.active
                ? colors.primary
                : colors.onSurfaceVariant,
            onPressed: widget.onPressed,
            icon: Icon(widget.icon),
          ),
        ),
      ),
    );
  }
}
