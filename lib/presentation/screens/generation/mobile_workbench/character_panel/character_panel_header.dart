import 'package:flutter/material.dart';

/// Top bar of a character panel page: an optional back button, the title and
/// trailing actions on one centred row, and an optional second line under
/// the title.
class CharacterPanelHeader extends StatelessWidget {
  const CharacterPanelHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.trailing = const [],
  });

  static const double _backWidth = 48;

  final Widget title;
  final String? subtitle;
  final VoidCallback? onBack;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final back = onBack;
    final line = subtitle;
    return Padding(
      padding: EdgeInsetsDirectional.only(
        start: back == null ? 20 : 4,
        end: 8,
        top: 4,
        bottom: line == null ? 0 : 4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Row(
              children: [
                if (back != null)
                  SizedBox(
                    width: _backWidth,
                    child: IconButton(
                      key: const ValueKey('character-panel-back'),
                      onPressed: back,
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).backButtonTooltip,
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                  ),
                Expanded(
                  child: DefaultTextStyle.merge(
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    child: title,
                  ),
                ),
                ...trailing,
              ],
            ),
          ),
          if (line != null)
            Padding(
              // Starts under the title, not under the back button.
              padding: EdgeInsetsDirectional.only(
                start: back == null ? 0 : _backWidth,
              ),
              child: Text(
                line,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
