import 'package:flutter/material.dart';

import '../../../../../core/utils/localization_extension.dart';
import '../../../../adaptive/interaction_policy.dart';

/// Stands in for the detail panel's actions while tags are picked: leave
/// picking, how many are picked, and copy them.
class DetailTagPickBar extends StatelessWidget {
  const DetailTagPickBar({
    super.key,
    required this.count,
    required this.onCopy,
    required this.onLeave,
  });

  final int count;
  final VoidCallback onCopy;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = context.l10n;
    final extent = context.interactionPolicy.minimumControlExtent;
    return Padding(
      key: const ValueKey('detail-tag-pick-bar'),
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                key: const ValueKey('detail-tag-pick-leave'),
                onPressed: onLeave,
                tooltip: l10n.common_cancel,
                icon: const Icon(Icons.close_rounded),
                style: IconButton.styleFrom(minimumSize: Size.square(extent)),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  count == 0
                      ? l10n.detail_pickTagsHint
                      : l10n.detail_pickedTagCount(count),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: count == 0
                        ? colors.onSurfaceVariant
                        : colors.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 8),
            child: FilledButton.icon(
              key: const ValueKey('detail-tag-pick-copy'),
              onPressed: count == 0 ? null : onCopy,
              style: FilledButton.styleFrom(minimumSize: Size(0, extent)),
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: Text(l10n.common_copy),
            ),
          ),
        ],
      ),
    );
  }
}
