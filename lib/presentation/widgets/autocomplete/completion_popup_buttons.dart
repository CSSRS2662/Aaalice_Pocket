import 'package:flutter/material.dart';

import '../../../core/utils/localization_extension.dart';
import '../../adaptive/interaction_policy.dart';

/// A tonal 分词 pill (scissors) that ends the tag being written with a
/// comma, standing in for the editor's own key while the popup covers it.
/// Like the other popup controls it never takes focus from the field.
class CompletionSplitButton extends StatelessWidget {
  const CompletionSplitButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Focus(
      canRequestFocus: false,
      descendantsAreFocusable: false,
      child: Tooltip(
        message: context.l10n.prompt_insertComma,
        child: TextButton(
          key: const ValueKey('autocomplete-popup-split'),
          onPressed: onPressed,
          style: TextButton.styleFrom(
            minimumSize: const Size(56, 32),
            tapTargetSize: MaterialTapTargetSize.padded,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            backgroundColor: colors.secondaryContainer,
            foregroundColor: colors.onSecondaryContainer,
            shape: const StadiumBorder(),
          ),
          child: const Icon(Icons.content_cut_rounded, size: 20),
        ),
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
