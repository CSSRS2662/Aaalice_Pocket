import 'package:flutter/material.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../adaptive/adaptive_presenter.dart';
import '../../../widgets/prompt/tag_editor_session.dart';
import 'prompt_group_controller.dart';

Future<void> movePromptGroupTags(
  BuildContext context, {
  required PromptGroupCollection groups,
  required String sourceId,
  required TagEditorSession session,
  required VoidCallback onChanged,
}) async {
  final destinationId = await AdaptivePresenter.showForm<String>(
    context: context,
    title: context.l10n.prompt_moveTagsToSection,
    builder: (context, scrollController) => ListView(
      controller: scrollController,
      shrinkWrap: true,
      children: [
        for (final (index, section) in groups.sections.indexed)
          if (section.id != sourceId && !section.isFixedTag)
            ListTile(
              key: ValueKey('prompt_tag_move_${section.id}'),
              leading: Icon(
                section.enabled
                    ? Icons.view_module_outlined
                    : Icons.pause_circle_outline,
              ),
              title: Text(context.l10n.prompt_groupLabel(index + 1)),
              subtitle: Text(
                section.controller.text.trim().isEmpty
                    ? context.l10n.prompt_groupEmptyHint
                    : section.controller.text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => Navigator.of(context).pop(section.id),
            ),
      ],
    ),
  );
  if (!context.mounted || destinationId == null) return;
  final destination = groups.sectionById(destinationId);
  if (destination != null && session.moveSelectedTo(destination.controller)) {
    onChanged();
  }
}
