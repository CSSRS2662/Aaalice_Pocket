import 'package:flutter/material.dart';

import '../../../../../core/utils/localization_extension.dart';
import '../../../../themes/theme_extension.dart';

/// A short message inside the character panel, with undo after a delete.
class CharacterPanelToastData {
  const CharacterPanelToastData({required this.message, this.onUndo});

  final String message;
  final VoidCallback? onUndo;
}

/// Shown over the bottom of the panel: a page-level snack bar would sit
/// behind the modal sheet.
class CharacterPanelToast extends StatelessWidget {
  const CharacterPanelToast({
    super.key,
    required this.toast,
    required this.onDismiss,
  });

  final CharacterPanelToastData? toast;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : theme.appTheme.fastDuration;
    final current = toast;
    return AnimatedSwitcher(
      duration: duration,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.25),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: current == null
          ? const SizedBox.shrink()
          : _ToastBody(
              key: ValueKey(current),
              toast: current,
              onDismiss: onDismiss,
            ),
    );
  }
}

class _ToastBody extends StatelessWidget {
  const _ToastBody({super.key, required this.toast, required this.onDismiss});

  final CharacterPanelToastData toast;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final onUndo = toast.onUndo;
    return Semantics(
      liveRegion: true,
      child: Material(
        key: const ValueKey('character-panel-toast'),
        color: colors.inverseSurface,
        elevation: 4,
        borderRadius: BorderRadius.circular(theme.appTheme.controlRadius + 4),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: 16, end: 4),
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      toast.message,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onInverseSurface,
                      ),
                    ),
                  ),
                ),
                if (onUndo != null)
                  TextButton(
                    key: const ValueKey('character-panel-toast-undo'),
                    onPressed: onUndo,
                    style: TextButton.styleFrom(
                      foregroundColor: colors.inversePrimary,
                      minimumSize: const Size(48, 44),
                    ),
                    child: Text(context.l10n.common_undo),
                  )
                else
                  IconButton(
                    onPressed: onDismiss,
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).closeButtonTooltip,
                    icon: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: colors.onInverseSurface,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
