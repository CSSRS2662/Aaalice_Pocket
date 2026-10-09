import 'package:flutter/widgets.dart';

/// Tags written elsewhere in the same prompt (other sections, fixed tags),
/// for the fields below.
///
/// Related suggestions leave [tags] out. In a grouped prompt, completion
/// also marks tags of the other sections as already written and says which
/// sections hold them. Read when a query starts, so it never rebuilds its
/// fields.
class CompletionExclusionScope extends InheritedWidget {
  const CompletionExclusionScope({
    super.key,
    required this.tags,
    this.otherSections,
    this.sectionNumber,
    required super.child,
  });

  /// Normalized tags (lower case, underscores) to leave out.
  final Set<String> Function() tags;

  /// Normalized tags of the other sections, with the 1-based numbers of the
  /// sections holding each, counted like the cards.
  final Map<String, List<int>> Function()? otherSections;

  /// The 1-based number of the section being edited.
  final int? sectionNumber;

  static CompletionExclusionScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<CompletionExclusionScope>();

  static Set<String> tagsOf(BuildContext context) =>
      maybeOf(context)?.tags() ?? const {};

  @override
  bool updateShouldNotify(CompletionExclusionScope oldWidget) => false;
}
