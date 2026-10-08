import 'package:flutter/widgets.dart';

/// Tags written elsewhere in the same prompt (other sections, fixed tags)
/// that related suggestions in the fields below should not offer again.
///
/// Read when a suggestion query starts, so it never rebuilds its fields.
class CompletionExclusionScope extends InheritedWidget {
  const CompletionExclusionScope({
    super.key,
    required this.tags,
    required super.child,
  });

  /// Normalized tags (lower case, underscores) to leave out.
  final Set<String> Function() tags;

  static Set<String> tagsOf(BuildContext context) =>
      context
          .getInheritedWidgetOfExactType<CompletionExclusionScope>()
          ?.tags() ??
      const {};

  @override
  bool updateShouldNotify(CompletionExclusionScope oldWidget) => false;
}
