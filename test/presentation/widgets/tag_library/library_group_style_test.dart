import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/models/tag_library/tag_library_category.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';
import 'package:nai_launcher/presentation/widgets/tag_library/library_group_style.dart';

TagLibraryCategory _category(String id, String name, [String? parent]) =>
    TagLibraryCategory(
      id: id,
      name: name,
      parentId: parent,
      createdAt: DateTime(2026),
    );

void main() {
  test('every preset matches its own name in all app languages', () async {
    for (final locale in AppLocalizations.supportedLocales) {
      final l10n = await AppLocalizations.delegate.load(locale);
      for (final preset in LibraryGroupPreset.values) {
        expect(
          LibraryGroupPreset.match(preset.label(l10n)),
          preset,
          reason: '${preset.name} in $locale',
        );
      }
    }
  });

  test('common synonyms and spacing still match; custom names do not', () {
    expect(LibraryGroupPreset.match('  Hair  '), LibraryGroupPreset.hair);
    expect(LibraryGroupPreset.match('衣服'), LibraryGroupPreset.outfit);
    expect(LibraryGroupPreset.match('画风'), LibraryGroupPreset.style);
    expect(LibraryGroupPreset.match('Art_Style'), LibraryGroupPreset.style);
    expect(LibraryGroupPreset.match('我的 OC'), isNull);
  });

  test('a custom subgroup takes the nearest preset parent', () {
    final categories = [
      _category('outfit', '服装'),
      _category('top', '上衣', 'outfit'),
      _category('accessory', '饰品', 'outfit'),
      _category('oc', '我的 OC'),
    ];

    expect(
      LibraryGroupStyle.of('top', categories),
      LibraryGroupStyle.ofPreset(LibraryGroupPreset.outfit),
    );
    expect(
      LibraryGroupStyle.of('accessory', categories),
      LibraryGroupStyle.ofPreset(LibraryGroupPreset.accessory),
    );
    expect(LibraryGroupStyle.of('oc', categories), LibraryGroupStyle.generic);
    expect(LibraryGroupStyle.of(null, categories), LibraryGroupStyle.generic);
  });

  test('a cycle in the hierarchy does not loop', () {
    final categories = [_category('a', 'A', 'b'), _category('b', 'B', 'a')];
    expect(LibraryGroupStyle.of('a', categories), LibraryGroupStyle.generic);
  });

  test('tones resolve to distinct tile colors with readable icons', () {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.teal);
    final rose = LibraryGroupStyle.ofPreset(
      LibraryGroupPreset.character,
    ).colorsIn(scheme);
    final sky = LibraryGroupStyle.ofPreset(
      LibraryGroupPreset.eyes,
    ).colorsIn(scheme);

    expect(rose.background, isNot(sky.background));
    for (final colors in [rose, sky]) {
      final contrast =
          (colors.foreground.computeLuminance() + 0.05) /
          (colors.background.computeLuminance() + 0.05);
      expect(contrast.abs() > 3 || 1 / contrast > 3, isTrue);
    }
  });
}
