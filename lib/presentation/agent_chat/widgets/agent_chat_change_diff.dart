import 'package:flutter/material.dart';

import '../../../core/utils/localization_extension.dart';
import '../../../core/utils/text_diff.dart';
import '../../../l10n/app_localizations.dart';
import '../../themes/core/layered_surface_style.dart';
import '../models/agent_approval_change.dart';

/// What an approval would rewrite: each changed field with its additions in
/// green and its deletions in red, struck through. Short values (switches,
/// numbers, choices) read as the old value struck through, then the new one.
class AgentChatChangeDiff extends StatelessWidget {
  const AgentChatChangeDiff({super.key, required this.changes});

  final List<AgentApprovalChange> changes;

  static const Set<String> _wholeValueFields = {
    'favorite',
    'enabled',
    'weight',
    'position',
    'prompt_type',
    'type',
    'strength',
    'fidelity',
    'information_extracted',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Container(
      key: const ValueKey('agent-chat-approval-changes'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: sectionSurfaceColor(theme.colorScheme),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (index, change) in changes.indexed) ...[
            if (index > 0) const SizedBox(height: 10),
            Text(
              _fieldLabel(l10n, change.field),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 3),
            Text.rich(
              key: ValueKey('agent-chat-approval-change-${change.field}'),
              TextSpan(children: _spans(context, change)),
              style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
            ),
          ],
        ],
      ),
    );
  }

  List<InlineSpan> _spans(BuildContext context, AgentApprovalChange change) {
    final l10n = context.l10n;
    final styles = AgentChatDiffStyles.of(Theme.of(context));
    String value(String raw) => _valueLabel(l10n, change.field, raw);
    if (_wholeValueFields.contains(change.field) ||
        change.before.isEmpty ||
        change.after.isEmpty) {
      return [
        if (change.before.isEmpty)
          TextSpan(text: l10n.agentChat_changeEmpty, style: styles.muted)
        else
          TextSpan(text: value(change.before), style: styles.removed),
        TextSpan(text: '  →  ', style: styles.muted),
        if (change.after.isEmpty)
          TextSpan(text: l10n.agentChat_changeEmpty, style: styles.muted)
        else
          TextSpan(text: value(change.after), style: styles.added),
      ];
    }
    return [
      for (final segment in diffText(change.before, change.after))
        TextSpan(
          text: segment.text,
          style: switch (segment.kind) {
            TextDiffKind.same => null,
            TextDiffKind.added => styles.added,
            TextDiffKind.removed => styles.removed,
          },
        ),
    ];
  }

  static String _fieldLabel(AppLocalizations l10n, String field) =>
      switch (field) {
        'name' => l10n.fixedTags_name,
        'content' => l10n.fixedTags_content,
        'tags' => l10n.tagLibrary_tags,
        'category' => l10n.common_category,
        'parent' => l10n.agentChat_changeParent,
        'favorite' => l10n.common_favorite,
        'enabled' => l10n.common_enabled,
        'weight' => l10n.fixedTags_weight,
        'position' => l10n.fixedTags_position,
        'prompt_type' => l10n.fixedTags_scope,
        'source' => l10n.agentChat_changeSource,
        'type' => l10n.agentChat_changeType,
        'strength' => l10n.vibe_strength,
        'information_extracted' => l10n.vibe_infoExtracted,
        'fidelity' => l10n.preciseRef_fidelity,
        _ => field,
      };

  static String _valueLabel(
    AppLocalizations l10n,
    String field,
    String value,
  ) => switch ((field, value)) {
    (_, 'true') => l10n.agentChat_changeYes,
    (_, 'false') => l10n.agentChat_changeNo,
    ('position', 'prefix') => l10n.fixedTags_prefix,
    ('position', 'suffix') => l10n.fixedTags_suffix,
    ('prompt_type', 'positive') => l10n.fixedTags_positive,
    ('prompt_type', 'negative') => l10n.fixedTags_negative,
    ('type', 'character') => l10n.preciseRef_typeCharacter,
    ('type', 'style') => l10n.preciseRef_typeStyle,
    ('type', 'characterAndStyle') => l10n.preciseRef_typeCharacterAndStyle,
    _ => value,
  };
}

/// The colours of added and removed text, readable on the neutral surfaces
/// in both brightnesses.
class AgentChatDiffStyles {
  const AgentChatDiffStyles({
    required this.added,
    required this.removed,
    required this.muted,
  });

  factory AgentChatDiffStyles.of(ThemeData theme) {
    final dark = theme.brightness == Brightness.dark;
    final green = dark ? const Color(0xFF7FD591) : const Color(0xFF1E7B34);
    final red = theme.colorScheme.error;
    return AgentChatDiffStyles(
      added: TextStyle(
        color: green,
        backgroundColor: green.withValues(alpha: dark ? 0.16 : 0.12),
      ),
      removed: TextStyle(
        color: red,
        backgroundColor: red.withValues(alpha: dark ? 0.16 : 0.1),
        decoration: TextDecoration.lineThrough,
        decorationColor: red,
      ),
      muted: TextStyle(color: theme.colorScheme.onSurfaceVariant),
    );
  }

  final TextStyle added;
  final TextStyle removed;
  final TextStyle muted;
}
