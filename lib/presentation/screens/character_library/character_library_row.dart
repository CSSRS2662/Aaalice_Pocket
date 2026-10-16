import 'package:flutter/material.dart';

import '../../../core/utils/localization_extension.dart';
import '../../../data/models/character/character_library_entry.dart';
import '../../../data/models/fixed_tag/fixed_tag_entry.dart';
import '../../../data/models/gallery/prompt_group_snapshot.dart';
import '../../themes/core/layered_surface_style.dart';
import '../../themes/theme_extension.dart';
import '../../widgets/character/character_marker.dart';
import '../generation/widgets/prompt_group_fixed_tags.dart';

/// One character of the library list.
///
/// Closed it is one line: marker, name, fixed-tag count and the first tags.
/// Open, every section shows as a pill whose dot includes or leaves it out,
/// with the actions below.
class CharacterLibraryRow extends StatelessWidget {
  const CharacterLibraryRow({
    super.key,
    required this.entry,
    required this.fixedTags,
    required this.expanded,
    required this.selecting,
    required this.picked,
    required this.onTap,
    required this.onToggleSection,
    required this.onAdd,
    required this.onEdit,
    required this.onToggleFavorite,
    required this.onDuplicate,
    required this.onDelete,
  });

  /// With fixed-tag sections already resolved.
  final CharacterLibraryEntry entry;
  final Map<String, FixedTagEntry> fixedTags;
  final bool expanded;
  final bool selecting;
  final bool picked;
  final VoidCallback onTap;
  final void Function(bool negative, String sectionId) onToggleSection;
  final VoidCallback onAdd;
  final VoidCallback onEdit;
  final VoidCallback onToggleFavorite;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  bool _claimed(PromptGroupSectionSnapshot section) {
    final tag = section.fixedTagId == null
        ? null
        : fixedTags[section.fixedTagId];
    return tag != null && tag.enabled && section.enabled && !section.keepInMain;
  }

  @override
  Widget build(BuildContext context) {
    final open = expanded && !selecting;
    final claimed = [
      ...entry.positiveSections,
      ...entry.negativeSections,
    ].any(_claimed);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Head(
          entry: entry,
          open: open,
          selecting: selecting,
          picked: picked,
          onTap: onTap,
        ),
        AnimatedSize(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 180),
          alignment: Alignment.topCenter,
          child: open
              ? _Body(
                  entry: entry,
                  fixedTags: fixedTags,
                  claimedOf: _claimed,
                  showClaimNote: claimed,
                  onToggleSection: onToggleSection,
                  onAdd: onAdd,
                  onEdit: onEdit,
                  onToggleFavorite: onToggleFavorite,
                  onDuplicate: onDuplicate,
                  onDelete: onDelete,
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class _Head extends StatelessWidget {
  const _Head({
    required this.entry,
    required this.open,
    required this.selecting,
    required this.picked,
    required this.onTap,
  });

  final CharacterLibraryEntry entry;
  final bool open;
  final bool selecting;
  final bool picked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = context.l10n;
    final summary = entry.prompt;
    return InkWell(
      key: ValueKey('character_library_row_${entry.id}'),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              if (selecting) ...[
                Icon(
                  picked
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: picked ? colors.primary : colors.outline,
                ),
                const SizedBox(width: 12),
              ],
              CharacterMarkerDisc(
                colors: CharacterMarkerPalette.forGender(entry.gender),
                diameter: 32,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            entry.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (entry.fixedTagCount > 0) ...[
                          const SizedBox(width: 6),
                          _Badge(
                            l10n.characterLibrary_fixedTagCount(
                              entry.fixedTagCount,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      summary.isEmpty ? l10n.prompt_emptyGroup : summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                entry.useCount > 0
                    ? l10n.characterLibrary_useCount(entry.useCount)
                    : l10n.characterLibrary_unused,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (!selecting)
                AnimatedRotation(
                  turns: open ? 0.25 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: colors.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: colors.onPrimaryContainer,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.entry,
    required this.fixedTags,
    required this.claimedOf,
    required this.showClaimNote,
    required this.onToggleSection,
    required this.onAdd,
    required this.onEdit,
    required this.onToggleFavorite,
    required this.onDuplicate,
    required this.onDelete,
  });

  final CharacterLibraryEntry entry;
  final Map<String, FixedTagEntry> fixedTags;
  final bool Function(PromptGroupSectionSnapshot section) claimedOf;
  final bool showClaimNote;
  final void Function(bool negative, String sectionId) onToggleSection;
  final VoidCallback onAdd;
  final VoidCallback onEdit;
  final VoidCallback onToggleFavorite;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = context.l10n;
    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 6),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: colors.onSurfaceVariant,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
    Widget pills(bool negative) => Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final section in entry.sectionsFor(negative))
          _SectionPill(
            section: section,
            fixedTagName: section.fixedTagId == null
                ? null
                : fixedTags[section.fixedTagId]?.displayName ??
                      l10n.characterLibrary_fixedTagMissing,
            claimed: claimedOf(section),
            onToggle: () => onToggleSection(negative, section.id),
            onTap: onEdit,
          ),
      ],
    );
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(60, 0, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          label(
            l10n.characterLibrary_positiveSections(
              entry.positiveSections.length,
            ),
          ),
          pills(false),
          if (entry.negativeSections.isNotEmpty) ...[
            const SizedBox(height: 6),
            label(
              l10n.characterLibrary_negativeSections(
                entry.negativeSections.length,
              ),
            ),
            pills(true),
          ],
          if (showClaimNote) ...[
            const SizedBox(height: 8),
            Text(
              l10n.characterLibrary_claimHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton(
                key: ValueKey('character_library_add_${entry.id}'),
                onPressed: onAdd,
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                child: Text(l10n.characterLibrary_addToPanel),
              ),
              FilledButton.tonal(
                key: ValueKey('character_library_edit_${entry.id}'),
                onPressed: onEdit,
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                child: Text(l10n.common_edit),
              ),
              IconButton(
                onPressed: onToggleFavorite,
                tooltip: entry.favorite
                    ? l10n.common_unfavorite
                    : l10n.common_favorite,
                icon: Icon(
                  entry.favorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: entry.favorite ? colors.error : null,
                ),
              ),
              PopupMenuButton<VoidCallback>(
                tooltip: l10n.common_moreActions,
                onSelected: (action) => action(),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: onDuplicate,
                    child: Text(l10n.characterLibrary_duplicate),
                  ),
                  PopupMenuItem(
                    value: onDelete,
                    child: Text(
                      l10n.common_delete,
                      style: TextStyle(color: colors.error),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionPill extends StatelessWidget {
  const _SectionPill({
    required this.section,
    required this.fixedTagName,
    required this.claimed,
    required this.onToggle,
    required this.onTap,
  });

  final PromptGroupSectionSnapshot section;
  final String? fixedTagName;
  final bool claimed;
  final VoidCallback onToggle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = context.l10n;
    final fixed = fixedTagName != null;
    final text = section.text.trim().isEmpty
        ? l10n.prompt_emptyGroup
        : section.text;
    return Material(
      color: fixed
          ? Color.alphaBlend(
              colors.primaryContainer.withValues(alpha: 0.42),
              controlSurfaceColor(colors),
            )
          : controlSurfaceColor(colors),
      borderRadius: BorderRadius.circular(theme.appTheme.controlRadius),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44, maxWidth: 280),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              button: true,
              toggled: section.enabled,
              label: section.enabled
                  ? l10n.prompt_groupDisable
                  : l10n.prompt_groupEnable,
              child: InkWell(
                key: ValueKey('character_library_section_dot_${section.id}'),
                onTap: onToggle,
                child: SizedBox(
                  width: 36,
                  height: 44,
                  child: Center(
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: section.enabled
                            ? colors.primary
                            : Colors.transparent,
                        border: Border.all(
                          color: section.enabled
                              ? colors.primary
                              : colors.outline,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Flexible(
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(end: 10),
                  child: SizedBox(
                    height: 44,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                if (fixed)
                                  TextSpan(
                                    text: '$fixedTagName · ',
                                    style: TextStyle(
                                      color: colors.primary,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                TextSpan(text: text),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: section.enabled
                                  ? colors.onSurface
                                  : colors.onSurface.withValues(alpha: 0.45),
                            ),
                          ),
                        ),
                        if (claimed) ...[
                          const SizedBox(width: 6),
                          const PromptGroupClaimDot(),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
