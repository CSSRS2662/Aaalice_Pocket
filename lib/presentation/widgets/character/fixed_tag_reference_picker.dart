import 'package:flutter/material.dart';

import '../../../core/utils/localization_extension.dart';
import '../../../data/models/fixed_tag/fixed_tag_entry.dart';
import '../../../data/models/fixed_tag/fixed_tag_prompt_type.dart';
import '../../adaptive/adaptive_presenter.dart';
import '../../adaptive/content_sized_adaptive_form.dart';

/// Picks a fixed tag to place among a character's sections.
///
/// Lists the tags of the prompt side, saying which ones the main prompt has
/// on (the character will take those) and which the character already shows.
Future<FixedTagEntry?> showFixedTagReferencePicker(
  BuildContext context, {
  required List<FixedTagEntry> entries,
  required bool negative,
  required Set<String> placedIds,
}) {
  final l10n = context.l10n;
  final type = negative
      ? FixedTagPromptType.negative
      : FixedTagPromptType.positive;
  final candidates = entries.where((entry) => entry.promptType == type).toList()
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  return AdaptivePresenter.showForm<FixedTagEntry>(
    context: context,
    title: negative
        ? l10n.characterLibrary_pickNegativeFixedTag
        : l10n.characterLibrary_pickPositiveFixedTag,
    builder: (context, scrollController) {
      final theme = Theme.of(context);
      final colors = theme.colorScheme;
      if (candidates.isEmpty) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l10n.characterLibrary_noFixedTags,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        );
      }
      return ContentSizedAdaptiveForm(
        scrollController: scrollController,
        padding: const EdgeInsets.symmetric(vertical: 8),
        content: [
          for (final entry in candidates)
            _Row(
              entry: entry,
              placed: placedIds.contains(entry.id),
              onTap: () => Navigator.of(context).pop(entry),
            ),
        ],
      );
    },
  );
}

class _Row extends StatelessWidget {
  const _Row({required this.entry, required this.placed, required this.onTap});

  final FixedTagEntry entry;
  final bool placed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = context.l10n;
    final badges = [
      if (entry.enabled) l10n.characterLibrary_onInMain,
      if (placed) l10n.characterLibrary_alreadyPlaced,
    ];
    return ListTile(
      key: ValueKey('fixed_tag_reference_${entry.id}'),
      enabled: !placed,
      onTap: placed ? null : onTap,
      leading: Icon(
        placed ? Icons.check_circle_rounded : Icons.link_rounded,
        color: colors.primary,
      ),
      title: Text(
        [entry.displayName, ...badges].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w800,
        ),
      ),
      subtitle: Text(
        entry.weightedContent,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
