import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nai_launcher/core/utils/localization_extension.dart';
import 'package:nai_launcher/presentation/adaptive/interaction_policy.dart';
import 'package:nai_launcher/presentation/providers/image_generation_provider.dart';
import 'package:nai_launcher/presentation/themes/theme_extension.dart';
import 'package:nai_launcher/presentation/widgets/common/app_toast.dart';

import '../random_prompt_action.dart';

/// 抽卡模式状态按钮。
///
/// With [tapGeneratesPrompt] a tap draws one random prompt and a long press
/// turns random mode on; while it is on, a tap turns it off. Otherwise a tap
/// toggles the mode.
class RandomModeToggle extends ConsumerStatefulWidget {
  const RandomModeToggle({
    super.key,
    required this.enabled,
    this.compact = false,
    this.tapGeneratesPrompt = false,
  });

  final bool enabled;
  final bool compact;
  final bool tapGeneratesPrompt;

  @override
  ConsumerState<RandomModeToggle> createState() => _RandomModeToggleState();
}

class _RandomModeToggleState extends ConsumerState<RandomModeToggle> {
  bool _hovered = false;
  bool _drawing = false;

  void _toggleMode() {
    ref.read(randomPromptModeProvider.notifier).toggle();
    if (!widget.tapGeneratesPrompt) return;
    // The same dice also draws prompts, so say which way the mode went.
    AppToast.info(
      context,
      widget.enabled
          ? context.l10n.randomMode_turnedOff
          : context.l10n.randomMode_turnedOn,
    );
  }

  void _handleTap() {
    if (!widget.tapGeneratesPrompt || widget.enabled) {
      _toggleMode();
      return;
    }
    if (_drawing) return;
    _drawing = true;
    unawaited(
      applyRandomPrompt(context, ref).whenComplete(() => _drawing = false),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reduceMotion ? Duration.zero : theme.appTheme.fastDuration;
    final controlExtent = widget.compact
        ? 36.0
        : context.interactionPolicy.minimumControlExtent;
    final tooltip = switch ((widget.tapGeneratesPrompt, widget.enabled)) {
      (true, true) => context.l10n.randomMode_touchEnabledTip,
      (true, false) => context.l10n.randomMode_touchTip,
      (false, true) => context.l10n.randomMode_enabledTip,
      (false, false) => context.l10n.randomMode_disabledTip,
    };
    final baseColor = widget.enabled
        ? colors.primaryContainer
        : Colors.transparent;
    final backgroundColor = _hovered
        ? Color.alphaBlend(colors.onSurface.withValues(alpha: 0.07), baseColor)
        : baseColor;

    return Semantics(
      button: true,
      toggled: widget.enabled,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        // A long press belongs to the button here, not to the tooltip.
        triggerMode: widget.tapGeneratesPrompt
            ? TooltipTriggerMode.manual
            : null,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: AnimatedContainer(
            key: const ValueKey('random-mode-button-surface'),
            width: controlExtent,
            height: controlExtent,
            duration: duration,
            curve: theme.appTheme.standardCurve,
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(widget.compact ? 10 : 13),
            ),
            child: Material(
              color: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(widget.compact ? 10 : 13),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _handleTap,
                onLongPress: widget.tapGeneratesPrompt && !widget.enabled
                    ? _toggleMode
                    : null,
                child: Center(
                  child: AnimatedRotation(
                    key: const ValueKey('random-mode-dice-rotation'),
                    turns: widget.enabled ? 0.125 : 0,
                    duration: duration,
                    curve: theme.appTheme.enterCurve,
                    child: AnimatedSwitcher(
                      duration: duration,
                      switchInCurve: theme.appTheme.enterCurve,
                      switchOutCurve: theme.appTheme.exitCurve,
                      transitionBuilder: (child, animation) =>
                          FadeTransition(opacity: animation, child: child),
                      child: Icon(
                        widget.enabled
                            ? Icons.casino_rounded
                            : Icons.casino_outlined,
                        key: ValueKey(widget.enabled),
                        size: widget.compact ? 19 : 22,
                        color: widget.enabled
                            ? colors.onPrimaryContainer
                            : colors.onSurfaceVariant,
                      ),
                    ),
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
