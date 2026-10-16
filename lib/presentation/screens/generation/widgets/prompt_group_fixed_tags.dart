import 'package:flutter/material.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../adaptive/adaptive_presenter.dart';
import '../../../adaptive/content_sized_adaptive_form.dart';

/// What a fixed-tag section tile shows about its tag.
class PromptGroupFixedTagInfo {
  const PromptGroupFixedTagInfo({required this.name, required this.claimed});

  /// The tag's name, or null when the tag is gone and the section keeps the
  /// content it last had.
  final String? name;

  /// The tag is also on in the main prompt, and this included section takes
  /// it from there for the generation.
  final bool claimed;
}

/// The amber mark of [PromptGroupFixedTagInfo.claimed].
class PromptGroupClaimDot extends StatelessWidget {
  const PromptGroupClaimDot({super.key});

  static const Color color = Color(0xFFC77700);

  @override
  Widget build(BuildContext context) => Semantics(
    label: context.l10n.characterLibrary_claimedLabel,
    child: Container(
      width: 8,
      height: 8,
      decoration: const BoxDecoration(color: color, shape: BoxShape.circle),
    ),
  );
}

/// The text part of a fixed-tag tile: the tag's name with a link mark, then
/// its content on one line.
class PromptGroupFixedTagTileBody extends StatelessWidget {
  const PromptGroupFixedTagTileBody({
    super.key,
    required this.info,
    required this.content,
    required this.keepInMain,
    required this.textStyle,
  });

  final PromptGroupFixedTagInfo info;
  final String content;
  final bool keepInMain;
  final TextStyle textStyle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final name = info.name;
    final label = [
      name == null
          ? l10n.characterLibrary_fixedTagMissing
          : l10n.characterLibrary_fixedTagLabel(name),
      if (keepInMain) l10n.characterLibrary_keepInMain,
    ].join(' · ');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.link_rounded, size: 14, color: colors.primary),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textStyle.copyWith(
                  fontSize: 11.5,
                  height: 1.3,
                  fontWeight: FontWeight.w800,
                  color: name == null ? colors.error : colors.primary,
                ),
              ),
            ),
            if (info.claimed) ...[
              const SizedBox(width: 6),
              const PromptGroupClaimDot(),
            ],
          ],
        ),
        Text(
          content.trim().isEmpty ? '—' : content,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textStyle.copyWith(color: colors.onSurface),
        ),
      ],
    );
  }
}

enum FixedTagSectionAction { toggleKeepInMain, detach, remove }

/// Menu of a fixed-tag section: keep the tag in the main prompt too, turn
/// the section into ordinary text, or take it out.
Future<FixedTagSectionAction?> showFixedTagSectionMenu(
  BuildContext context, {
  required String? name,
  required bool keepInMain,
}) {
  final l10n = context.l10n;
  return AdaptivePresenter.showForm<FixedTagSectionAction>(
    context: context,
    title: name == null
        ? l10n.characterLibrary_fixedTagMissing
        : l10n.characterLibrary_fixedTagLabel(name),
    builder: (context, scrollController) {
      final colors = Theme.of(context).colorScheme;
      return ContentSizedAdaptiveForm(
        scrollController: scrollController,
        padding: const EdgeInsets.symmetric(vertical: 8),
        content: [
          SwitchListTile(
            key: const ValueKey('fixed_tag_section_keep_in_main'),
            value: keepInMain,
            title: Text(l10n.characterLibrary_keepInMain),
            subtitle: Text(l10n.characterLibrary_keepInMainHint),
            onChanged: (_) => Navigator.of(
              context,
            ).pop(FixedTagSectionAction.toggleKeepInMain),
          ),
          ListTile(
            key: const ValueKey('fixed_tag_section_detach'),
            leading: const Icon(Icons.link_off_rounded),
            title: Text(l10n.characterLibrary_detach),
            subtitle: Text(l10n.characterLibrary_detachHint),
            onTap: () =>
                Navigator.of(context).pop(FixedTagSectionAction.detach),
          ),
          ListTile(
            key: const ValueKey('fixed_tag_section_remove'),
            leading: Icon(Icons.remove_circle_outline, color: colors.error),
            title: Text(
              l10n.characterLibrary_removeFixedTag,
              style: TextStyle(color: colors.error),
            ),
            onTap: () =>
                Navigator.of(context).pop(FixedTagSectionAction.remove),
          ),
        ],
      );
    },
  );
}

/// Below a character's sections: the button that brings in a fixed tag, and
/// a note naming the tags taken from the main prompt.
class PromptGroupFixedTagBar extends StatelessWidget {
  const PromptGroupFixedTagBar({
    super.key,
    required this.claimedNames,
    required this.onAdd,
  });

  final List<String> claimedNames;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          key: const ValueKey('prompt_group_add_fixed_tag'),
          onPressed: onAdd,
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          icon: const Icon(Icons.link_rounded, size: 18),
          label: Text(l10n.characterLibrary_importFixedTag),
        ),
        if (claimedNames.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            key: const ValueKey('prompt_group_claim_note'),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: PromptGroupClaimDot.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 5),
                  child: PromptGroupClaimDot(),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.characterLibrary_claimNote(
                      claimedNames.map((name) => '「$name」').join(''),
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurface,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
