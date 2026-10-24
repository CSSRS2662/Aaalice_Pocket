import 'package:flutter/material.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../../data/models/tag_library/tag_library_category.dart';
import '../../../../data/models/tag_library/tag_library_entry.dart';
import '../../../widgets/tag_library/library_group_style.dart';
import '../tag_library_sections.dart';
import 'entry_card.dart';
import 'tag_library_grid_layout.dart';

/// The library list: headed sections of compact entry cards.
class TagLibrarySectionsView extends StatelessWidget {
  const TagLibrarySectionsView({
    super.key,
    required this.sections,
    required this.categories,
    required this.entryBuilder,
    this.scrollController,
    this.bottomPadding = 24,
  });

  final List<TagLibrarySection> sections;
  final List<TagLibraryCategory> categories;
  final Widget Function(TagLibraryEntry entry) entryBuilder;
  final ScrollController? scrollController;

  /// Room left under the last card, such as for a floating selection bar.
  final double bottomPadding;

  /// The favorites section's mark, next to the groups' own icons.
  static const favoritesStyle = LibraryGroupStyle(
    icon: Icons.favorite_rounded,
    tone: LibraryGroupTone.rose,
  );

  @override
  Widget build(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);
    final extent = EntryCard.extentFor(context, textScaler: textScaler);
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = computeTagLibraryGridLayout(
          constraints.maxWidth,
          textScaler.scale(14) / 14,
          cardExtent: extent,
        );
        return CustomScrollView(
          key: const ValueKey('tag-library-sections'),
          controller: scrollController,
          slivers: [
            for (final (index, section) in sections.indexed) ...[
              if (section.kind != TagLibrarySectionKind.results)
                SliverToBoxAdapter(
                  child: _SectionHeader(
                    section: section,
                    categories: categories,
                    padding: layout.padding,
                    first: index == 0,
                  ),
                ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  layout.padding,
                  section.kind == TagLibrarySectionKind.results ? 8 : 0,
                  layout.padding,
                  4,
                ),
                sliver: SliverGrid(
                  gridDelegate: layout.delegate,
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => entryBuilder(section.entries[i]),
                    childCount: section.entries.length,
                  ),
                ),
              ),
            ],
            SliverToBoxAdapter(child: SizedBox(height: bottomPadding)),
          ],
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.section,
    required this.categories,
    required this.padding,
    required this.first,
  });

  final TagLibrarySection section;
  final List<TagLibraryCategory> categories;
  final double padding;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (name, style) = switch (section.kind) {
      TagLibrarySectionKind.favorites => (
        context.l10n.tagLibrary_favorites,
        TagLibrarySectionsView.favoritesStyle,
      ),
      TagLibrarySectionKind.group => (
        section.category!.displayName,
        LibraryGroupStyle.of(section.category!.id, categories),
      ),
      _ => (context.l10n.tagLibrary_uncategorized, LibraryGroupStyle.generic),
    };
    return Padding(
      key: ValueKey('tag-library-section-${section.key}'),
      padding: EdgeInsets.fromLTRB(padding + 4, first ? 8 : 16, padding, 8),
      child: Row(
        children: [
          LibraryGroupIcon(style: style, size: 22, iconSize: 14, radius: 7),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${section.entries.length}',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
