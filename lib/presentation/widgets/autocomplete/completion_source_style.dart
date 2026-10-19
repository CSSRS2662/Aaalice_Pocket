import 'package:flutter/material.dart';

import '../../../core/autocomplete/completion_models.dart';
import '../../../core/utils/localization_extension.dart';

/// The colour, short code and name of each completion source. Candidate
/// tiles mark their sources with these colours as dots; the popup footer
/// repeats the colours on the source status items, which is the legend.
abstract final class CompletionSourceStyle {
  /// Sources in their fixed dot order.
  static List<CompletionSourceKind> ordered(
    Set<CompletionSourceKind> sources,
  ) =>
      sources.toList()
        ..sort((left, right) => left.index.compareTo(right.index));

  static Color color(ThemeData theme, CompletionSourceKind source) {
    final dark = theme.brightness == Brightness.dark;
    return switch (source) {
      CompletionSourceKind.base => theme.colorScheme.outline,
      CompletionSourceKind.zhDictionary =>
        dark ? const Color(0xff72ca7b) : const Color(0xff2e7d32),
      CompletionSourceKind.danbooruApi =>
        dark ? const Color(0xff64b5f6) : const Color(0xff1565c0),
      CompletionSourceKind.cooccurrence =>
        dark ? const Color(0xffffb75f) : const Color(0xff9a5900),
      CompletionSourceKind.ai =>
        dark ? const Color(0xffce82dc) : const Color(0xff7b1fa2),
      CompletionSourceKind.library =>
        dark ? const Color(0xff64d4c5) : const Color(0xff167568),
    };
  }

  static String code(CompletionSourceKind source) => switch (source) {
    CompletionSourceKind.base => 'BASE',
    CompletionSourceKind.zhDictionary => 'ZH',
    CompletionSourceKind.danbooruApi => 'API',
    CompletionSourceKind.cooccurrence => 'REL',
    CompletionSourceKind.ai => 'AI',
    CompletionSourceKind.library => 'LIB',
  };

  static String name(BuildContext context, CompletionSourceKind source) {
    final l10n = context.l10n;
    return switch (source) {
      CompletionSourceKind.base => l10n.autocomplete_statusBase,
      CompletionSourceKind.zhDictionary => l10n.autocomplete_statusDictionary,
      CompletionSourceKind.danbooruApi => l10n.autocomplete_statusOnline,
      CompletionSourceKind.cooccurrence => l10n.autocomplete_statusRelated,
      CompletionSourceKind.ai => l10n.autocomplete_statusAi,
      CompletionSourceKind.library => l10n.autocomplete_categoryLibrary,
    };
  }
}

/// One coloured dot per source, in the fixed order. The names are read out
/// and shown in the tooltip.
class CompletionSourceDots extends StatelessWidget {
  const CompletionSourceDots({super.key, required this.sources});

  static const double dotSize = 5;
  static const double gap = 2;

  /// Width of the dots for [count] sources, without outer spacing.
  static double widthFor(int count) =>
      count <= 0 ? 0 : count * dotSize + (count - 1) * gap;

  final Set<CompletionSourceKind> sources;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ordered = CompletionSourceStyle.ordered(sources);
    final names = ordered
        .map((source) => CompletionSourceStyle.name(context, source))
        .join(' · ');
    return Tooltip(
      message: names,
      child: Semantics(
        label: names,
        excludeSemantics: true,
        child: Row(
          key: const ValueKey('autocomplete-candidate-sources'),
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < ordered.length; index++) ...[
              if (index > 0) const SizedBox(width: gap),
              Container(
                key: ValueKey('autocomplete-source-dot-${ordered[index].name}'),
                width: dotSize,
                height: dotSize,
                decoration: BoxDecoration(
                  color: CompletionSourceStyle.color(theme, ordered[index]),
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
