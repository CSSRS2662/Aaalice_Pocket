import 'package:flutter/material.dart';

import '../../../core/autocomplete/completion_models.dart';
import '../../../core/utils/localization_extension.dart';

/// Icon, name and colour of each tag category in the completion popup:
/// the tag text, the small icon before uncommon categories and the header
/// filter buttons all read them from here.
abstract final class CompletionCategoryStyle {
  /// General tags are most of every list, so only the other categories
  /// carry an icon in front of the tag.
  static bool marksTile(TagCategory category) =>
      category != TagCategory.general;

  static IconData icon(TagCategory category) => switch (category) {
    TagCategory.general => Icons.sell_rounded,
    TagCategory.artist => Icons.brush_rounded,
    TagCategory.copyright => Icons.copyright_rounded,
    TagCategory.character => Icons.person_rounded,
    TagCategory.meta => Icons.tune_rounded,
    TagCategory.contributor => Icons.badge_rounded,
    TagCategory.species => Icons.pets_rounded,
    TagCategory.lore => Icons.auto_stories_rounded,
    TagCategory.library => Icons.collections_bookmark_rounded,
  };

  static String label(BuildContext context, TagCategory category) {
    final l10n = context.l10n;
    return switch (category) {
      TagCategory.general => l10n.autocomplete_categoryGeneral,
      TagCategory.artist => l10n.autocomplete_categoryArtist,
      TagCategory.copyright => l10n.autocomplete_categoryCopyright,
      TagCategory.character => l10n.autocomplete_categoryCharacter,
      TagCategory.meta => l10n.autocomplete_categoryMeta,
      TagCategory.contributor => l10n.autocomplete_categoryContributor,
      TagCategory.species => l10n.autocomplete_categorySpecies,
      TagCategory.lore => l10n.autocomplete_categoryLore,
      TagCategory.library => l10n.autocomplete_categoryLibrary,
    };
  }

  static Color color(BuildContext context, TagCategory category) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return switch ((category, dark)) {
      (TagCategory.general, true) => const Color(0xff62b9f0),
      (TagCategory.general, false) => const Color(0xff176d9f),
      (TagCategory.artist, true) => const Color(0xffff7b78),
      (TagCategory.artist, false) => const Color(0xffb52c2a),
      (TagCategory.copyright, true) => const Color(0xffd083e0),
      (TagCategory.copyright, false) => const Color(0xff7b4389),
      (TagCategory.character, true) => const Color(0xff7bd27e),
      (TagCategory.character, false) => const Color(0xff2b7834),
      (TagCategory.meta, true) => const Color(0xffffb85c),
      (TagCategory.meta, false) => const Color(0xff925b08),
      (TagCategory.contributor, true) => const Color(0xffff9d66),
      (TagCategory.contributor, false) => const Color(0xffa84f1d),
      (TagCategory.species, true) => const Color(0xff5ed6c4),
      (TagCategory.species, false) => const Color(0xff167568),
      (TagCategory.lore, true) => const Color(0xff9fa8ff),
      (TagCategory.lore, false) => const Color(0xff4d56a8),
      (TagCategory.library, true) => const Color(0xff64d4c5),
      (TagCategory.library, false) => const Color(0xff167568),
    };
  }
}
