import 'package:flutter/material.dart';

/// Dark floating capsule with a message and one action, such as undoing a
/// deletion or saving anyway. With large text the action moves below the
/// message instead of squeezing it.
class InverseActionBar extends StatelessWidget {
  const InverseActionBar({
    super.key,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    this.actionKey,
  });

  final String message;
  final String actionLabel;
  final VoidCallback onAction;
  final Key? actionKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final stacked = MediaQuery.textScalerOf(context).scale(1) >= 2;
    final text = Text(
      message,
      maxLines: stacked ? 4 : 2,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: colors.onInverseSurface,
      ),
    );
    final action = TextButton(
      key: actionKey,
      onPressed: onAction,
      style: TextButton.styleFrom(
        foregroundColor: colors.inversePrimary,
        shape: const StadiumBorder(),
      ),
      child: Text(actionLabel),
    );
    return Material(
      color: colors.inverseSurface,
      elevation: 6,
      shape: stacked
          ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))
          : const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: stacked
            ? Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 6, 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 14),
                      child: text,
                    ),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: action,
                    ),
                  ],
                ),
              )
            : Padding(
                padding: const EdgeInsetsDirectional.only(start: 20, end: 6),
                child: Row(
                  children: [
                    Expanded(child: text),
                    action,
                  ],
                ),
              ),
      ),
    );
  }
}
