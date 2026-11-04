import 'package:flutter/material.dart';

import '../../../../../core/utils/localization_extension.dart';
import '../../../../utils/detail_prompt_groups.dart';
import 'detail_tag_picks.dart';
import 'prompt_section.dart';

class DetailPromptGroups extends StatelessWidget {
  const DetailPromptGroups({
    super.key,
    required this.groups,
    required this.negative,
    required this.tagPicks,
    required this.onReuse,
  });

  final List<DetailPromptGroup> groups;
  final bool negative;
  final DetailTagPicks? tagPicks;
  final ValueChanged<DetailPromptGroup>? onReuse;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var index = 0; index < groups.length; index += 2) ...[
        if (index > 0) const SizedBox(height: 8),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _card(context, groups[index])),
              const SizedBox(width: 8),
              Expanded(
                child: index + 1 < groups.length
                    ? _card(context, groups[index + 1])
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ],
    ],
  );

  Widget _card(BuildContext context, DetailPromptGroup group) => PromptSection(
    key: ValueKey(
      'detail-group-${negative ? 'negative' : 'positive'}-${group.offset}',
    ),
    title: _title(context, group),
    icon: switch (group.kind) {
      DetailPromptGroupKind.fixed => Icons.push_pin_outlined,
      DetailPromptGroupKind.quality => Icons.auto_awesome_outlined,
      DetailPromptGroupKind.character => Icons.person_outline,
      _ => Icons.view_module_outlined,
    },
    content: group.text,
    tags: group.tags,
    cardStyle: true,
    isNegative: negative,
    allTagsAreFixed: group.kind == DetailPromptGroupKind.fixed,
    characterTags: group.kind == DetailPromptGroupKind.character
        ? group.tags
        : const [],
    tagPicks: tagPicks,
    pickSide: negative ? DetailTagSide.negative : DetailTagSide.positive,
    tagIndexOffset: group.offset,
    onReuse: onReuse == null ? null : () => onReuse!(group),
  );

  String _title(BuildContext context, DetailPromptGroup group) {
    final l10n = context.l10n;
    return switch (group.kind) {
      DetailPromptGroupKind.fixed =>
        group.name?.trim().isNotEmpty == true &&
                group.name!.trim() != group.text.trim()
            ? group.name!
            : l10n.fixedTags_label,
      DetailPromptGroupKind.section => l10n.prompt_groupLabel(group.number!),
      DetailPromptGroupKind.quality => l10n.qualityTags_label,
      DetailPromptGroupKind.character => l10n.character_number(group.number!),
      DetailPromptGroupKind.remaining => l10n.detail_otherPromptTags,
    };
  }
}
