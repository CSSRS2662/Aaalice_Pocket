import 'package:flutter/material.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../../core/utils/prompt_edit_document.dart';
import '../../../adaptive/adaptive_presenter.dart';
import '../../../adaptive/content_sized_adaptive_form.dart';
import 'prompt_group_controller.dart';

enum PromptGroupAction { toggleEnabled, edit, duplicate, moveToFront, delete }

/// Section menu opened by a long press (or right click) on a grid tile.
/// Returns the chosen action; the caller performs it after the menu closes.
Future<PromptGroupAction?> showPromptGroupActions(
  BuildContext context, {
  required PromptGroupCollection groups,
  required String sectionId,
}) {
  final section = groups.sectionById(sectionId);
  if (section == null) return Future.value();
  final l10n = context.l10n;
  final first = PromptEditDocument.parse(section.controller.text).firstOrNull;
  final title = [
    l10n.prompt_groupLabel(groups.indexOf(sectionId) + 1),
    first?.text ?? l10n.prompt_emptyGroup,
  ].join(' · ');

  return AdaptivePresenter.showForm<PromptGroupAction>(
    context: context,
    title: title,
    builder: (context, scrollController) {
      final colors = Theme.of(context).colorScheme;
      Widget item(PromptGroupAction action, IconData icon, String label) {
        final danger = action == PromptGroupAction.delete;
        return ListTile(
          key: ValueKey('prompt_group_action_${action.name}'),
          leading: Icon(icon, color: danger ? colors.error : null),
          title: Text(
            label,
            style: danger ? TextStyle(color: colors.error) : null,
          ),
          onTap: () => Navigator.of(context).pop(action),
        );
      }

      return ContentSizedAdaptiveForm(
        scrollController: scrollController,
        padding: const EdgeInsets.symmetric(vertical: 8),
        content: [
          item(
            PromptGroupAction.toggleEnabled,
            section.enabled
                ? Icons.radio_button_unchecked_rounded
                : Icons.radio_button_checked_rounded,
            section.enabled
                ? l10n.prompt_groupDisable
                : l10n.prompt_groupEnable,
          ),
          item(PromptGroupAction.edit, Icons.edit_outlined, l10n.common_edit),
          item(
            PromptGroupAction.duplicate,
            Icons.copy_all_rounded,
            l10n.prompt_groupDuplicate,
          ),
          item(
            PromptGroupAction.moveToFront,
            Icons.vertical_align_top_rounded,
            l10n.prompt_groupMoveToFront,
          ),
          item(
            PromptGroupAction.delete,
            Icons.delete_outline_rounded,
            l10n.prompt_deleteGroup,
          ),
        ],
      );
    },
  );
}
