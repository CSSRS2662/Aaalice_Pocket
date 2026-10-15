import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/autocomplete/prompt_token_parser.dart';
import '../../../providers/fixed_tags_provider.dart';

/// Tags already in the prompt outside the field being edited: [otherTexts]
/// (the other sections) and, with [includeFixedTags], the enabled fixed tags
/// of the same side. Fixed tags only join the main prompt.
Set<String> promptCompletionExclusions(
  WidgetRef ref, {
  required bool negative,
  Iterable<String> otherTexts = const [],
  bool includeFixedTags = true,
}) {
  final fixed = includeFixedTags ? ref.read(fixedTagsNotifierProvider) : null;
  final entries = fixed == null
      ? const <String>[]
      : [
          for (final entry
              in negative ? fixed.negativeEnabledEntries : fixed.enabledEntries)
            entry.content,
        ];
  return {
    for (final text in [...otherTexts, ...entries])
      ...PromptTokenParser.contextTags(
        text: text,
        cursorPosition: text.length,
        max: 1 << 16,
      ),
  };
}
