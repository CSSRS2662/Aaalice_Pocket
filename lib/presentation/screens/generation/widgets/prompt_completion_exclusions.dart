import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/autocomplete/prompt_token_parser.dart';
import '../../../providers/fixed_tags_provider.dart';

/// Tags already in the prompt outside the field being edited: [otherTexts]
/// (the other sections) and the enabled fixed tags of the same side.
Set<String> promptCompletionExclusions(
  WidgetRef ref, {
  required bool negative,
  Iterable<String> otherTexts = const [],
}) {
  final fixed = ref.read(fixedTagsNotifierProvider);
  final entries = negative
      ? fixed.negativeEnabledEntries
      : fixed.enabledEntries;
  return {
    for (final text in [
      ...otherTexts,
      ...entries.map((entry) => entry.content),
    ])
      ...PromptTokenParser.contextTags(
        text: text,
        cursorPosition: text.length,
        max: 1 << 16,
      ),
  };
}
