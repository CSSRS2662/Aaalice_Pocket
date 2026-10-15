import 'package:flutter/material.dart';

/// Top bar of a character panel page: an optional back button, the title
/// with an optional second line, and trailing actions.
class CharacterPanelHeader extends StatelessWidget {
  const CharacterPanelHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.trailing = const [],
  });

  final Widget title;
  final String? subtitle;
  final VoidCallback? onBack;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final back = onBack;
    final line = subtitle;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 60),
      child: Padding(
        padding: EdgeInsetsDirectional.only(
          start: back == null ? 20 : 4,
          end: 8,
          top: 4,
        ),
        child: Row(
          children: [
            if (back != null)
              IconButton(
                key: const ValueKey('character-panel-back'),
                onPressed: back,
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  DefaultTextStyle.merge(
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    child: title,
                  ),
                  if (line != null)
                    Text(
                      line,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            ...trailing,
          ],
        ),
      ),
    );
  }
}
