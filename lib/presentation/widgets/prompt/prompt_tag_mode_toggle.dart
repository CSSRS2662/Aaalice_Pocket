import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/localization_extension.dart';
import '../../providers/prompt_editor_preferences_provider.dart';
import 'prompt_footer_style.dart';

/// Text/tag editing mode as one button, like the positive/negative switch:
/// it shows the current mode with a swap mark, and a tap switches it.
class PromptTagModeToggle extends ConsumerWidget {
  const PromptTagModeToggle({
    super.key,
    required this.sessionId,
    this.enabled = true,
  });

  /// Width at normal text size, for layouts that plan around it.
  static const double width = 62;

  final Object sessionId;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tagMode = ref.watch(promptTagModeProvider(sessionId));
    final colors = Theme.of(context).colorScheme;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 160);
    final tooltip = tagMode
        ? context.l10n.tagMode_exit
        : context.l10n.tagMode_enter;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        toggled: tagMode,
        label: context.l10n.tagMode_label,
        child: TextButton(
          key: const ValueKey('tag-mode-button'),
          onPressed: enabled || tagMode
              ? () => ref
                    .read(promptTagModeProvider(sessionId).notifier)
                    .setEnabled(!tagMode)
              : null,
          style: PromptFooterStyle.button(context, width: width).copyWith(
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 12),
            ),
            backgroundColor: WidgetStatePropertyAll(
              tagMode ? colors.tertiaryContainer : colors.primaryContainer,
            ),
            foregroundColor: WidgetStatePropertyAll(
              tagMode ? colors.onTertiaryContainer : colors.onPrimaryContainer,
            ),
          ),
          child: ExcludeSemantics(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSwitcher(
                  duration: duration,
                  transitionBuilder: (child, animation) =>
                      FadeTransition(opacity: animation, child: child),
                  child: Icon(
                    tagMode ? Icons.sell_outlined : Icons.text_fields,
                    key: ValueKey(tagMode),
                    size: PromptFooterStyle.iconSize,
                  ),
                ),
                const SizedBox(width: 3),
                const Icon(Icons.swap_horiz_rounded, size: 17),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
