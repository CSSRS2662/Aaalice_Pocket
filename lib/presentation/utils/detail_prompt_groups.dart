import '../../core/utils/nai_prompt_parser.dart';
import '../../core/utils/prompt_edit_document.dart';
import '../../data/models/fixed_tag/fixed_tag_entry.dart' show FixedTagPosition;
import '../../data/models/fixed_tag/fixed_tag_prompt_type.dart';
import '../../data/models/gallery/nai_image_metadata.dart';
import '../../data/models/gallery/nai_metadata_prompt_projection.dart';

enum DetailPromptGroupKind { section, fixed, quality, character, remaining }

class DetailPromptGroup {
  const DetailPromptGroup({
    required this.kind,
    required this.tags,
    required this.offset,
    this.number,
    this.name,
  });

  final DetailPromptGroupKind kind;
  final List<String> tags;
  final int offset;
  final int? number;
  final String? name;
  String get text => tags.join(', ');
}

List<DetailPromptGroup>? detailPromptGroups(
  NaiImageMetadata metadata, {
  required bool negative,
}) {
  final snapshot = metadata.promptGroupSnapshot;
  if (snapshot == null ||
      !snapshot.groupedMode ||
      !snapshot.hasPromptSections) {
    return null;
  }
  final source = NaiPromptParser.splitSegments(
    negative ? metadata.displayNegativePrompt : metadata.prompt,
  );
  final assigned = <int>{};
  final groups = <DetailPromptGroup>[];
  void place(
    String text,
    DetailPromptGroupKind kind, {
    int? number,
    String? name,
  }) {
    final tags = NaiPromptParser.splitSegments(
      PromptEditDocument.effectiveText(text),
    );
    if (tags.isEmpty) return;
    for (var start = 0; start <= source.length - tags.length; start++) {
      final indexes = List.generate(tags.length, (i) => start + i);
      if (indexes.any(assigned.contains) ||
          !promptSegmentsMatchAt(source, tags, start)) {
        continue;
      }
      assigned.addAll(indexes);
      groups.add(
        DetailPromptGroup(
          kind: kind,
          tags: source.sublist(start, start + tags.length),
          offset: start,
          number: number,
          name: name,
        ),
      );
      return;
    }
  }

  final fixed = [
    for (final text
        in negative
            ? metadata.fixedNegativePrefixTags
            : metadata.fixedPrefixTags)
      (text: text, position: FixedTagPosition.prefix),
    for (final text
        in negative
            ? metadata.fixedNegativeSuffixTags
            : metadata.fixedSuffixTags)
      (text: text, position: FixedTagPosition.suffix),
  ];
  final usage = metadata.fixedTagUsageSnapshot;
  for (final item in fixed) {
    final names = usage?.entries.where(
      (entry) =>
          !entry.claimed &&
          entry.promptType ==
              (negative
                  ? FixedTagPromptType.negative
                  : FixedTagPromptType.positive) &&
          entry.position == item.position &&
          entry.renderedContent.trim() == item.text.trim(),
    );
    place(
      item.text,
      DetailPromptGroupKind.fixed,
      name: names?.firstOrNull?.name,
    );
  }
  final sections = negative
      ? snapshot.negativeSections
      : snapshot.positiveSections;
  for (final (index, section) in sections.indexed) {
    if (!section.enabled) continue;
    final fixedId = section.fixedTagId;
    final names = usage?.entries.where((entry) => entry.fixedTagId == fixedId);
    place(
      section.text,
      fixedId == null
          ? DetailPromptGroupKind.section
          : DetailPromptGroupKind.fixed,
      number: index + 1,
      name: fixedId == null ? null : names?.firstOrNull?.name,
    );
  }
  if (!negative) {
    place(metadata.qualityTags.join(', '), DetailPromptGroupKind.quality);
  }
  // Keep actual image tags whose original partition cannot be reconstructed.
  for (var start = 0; start < source.length;) {
    if (assigned.contains(start)) {
      start++;
      continue;
    }
    var end = start + 1;
    while (end < source.length && !assigned.contains(end)) {
      end++;
    }
    groups.add(
      DetailPromptGroup(
        kind: DetailPromptGroupKind.remaining,
        tags: source.sublist(start, end),
        offset: start,
      ),
    );
    start = end;
  }
  groups.sort((a, b) => a.offset.compareTo(b.offset));
  var offset = source.length;
  for (final (index, character) in metadata.characterInfos.indexed) {
    final tags = NaiPromptParser.splitSegments(
      negative ? character.negativePrompt ?? '' : character.prompt,
    );
    if (tags.isEmpty) continue;
    groups.add(
      DetailPromptGroup(
        kind: DetailPromptGroupKind.character,
        tags: tags,
        offset: offset,
        number: index + 1,
      ),
    );
    offset += tags.length;
  }
  return groups;
}
