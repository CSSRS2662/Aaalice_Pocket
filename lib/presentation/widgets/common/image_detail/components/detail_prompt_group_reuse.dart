import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../data/models/gallery/prompt_group_snapshot.dart';
import '../../../../agent_chat/services/prompt_section_state.dart';

final detailPromptGroupStateProvider = Provider(PromptSectionState.new);

Future<void> appendDetailPromptGroup(
  PromptSectionState state,
  String text, {
  required bool negative,
}) async {
  final current = state.read();
  final sections = negative
      ? current.negativeSections
      : current.positiveSections;
  final onlyBlank =
      sections.length == 1 &&
      sections.single.fixedTagId == null &&
      sections.single.text.trim().isEmpty;
  final next = current.groupedMode && !onlyBlank
      ? PromptSectionEdits.add(
          sections,
          section: PromptGroupSectionSnapshot(
            id: PromptSectionEdits.newId(),
            text: text,
          ),
        )
      : [
          PromptGroupSectionSnapshot(
            id: PromptSectionEdits.newId(),
            text: [
              negative ? current.negativePrompt : current.positivePrompt,
              text,
            ].where((value) => value.trim().isNotEmpty).join(', '),
          ),
        ];
  await state.write(
    PromptGroupSnapshot(
      groupedMode: current.groupedMode,
      positiveSections: negative ? current.positiveSections : next,
      negativeSections: negative ? next : current.negativeSections,
    ),
    positive: !negative,
    negative: negative,
  );
}
