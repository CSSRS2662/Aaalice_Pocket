import 'package:flutter/material.dart';

import '../../../data/models/tag_library/tag_library_category.dart';
import '../../../l10n/app_localizations.dart';
import '../../themes/core/layered_surface_style.dart';

/// The soft color family a group's icon sits on.
enum LibraryGroupTone {
  rose(Color(0xFFD36B84)),
  sky(Color(0xFF4F8AD0)),
  peach(Color(0xFFDB8550)),
  lilac(Color(0xFF9473CC)),
  sage(Color(0xFF5E9A6C)),
  teal(Color(0xFF2F8C88)),
  sand(Color(0xFFBF9638)),

  /// Neutral, for groups without a designed icon.
  slate(null);

  const LibraryGroupTone(this.seed);

  final Color? seed;
}

/// Groups that come with a designed icon. A group gets one when its name
/// matches the preset in any app language or a common synonym, so renamed or
/// imported groups keep working without storing an icon.
enum LibraryGroupPreset {
  character(Icons.person_outline_rounded, LibraryGroupTone.rose, [
    '人物',
    '角色',
    '人设',
    '人設',
    'character',
    'characters',
    'person',
    'people',
    'キャラ',
    'キャラクター',
  ]),
  hair(Icons.content_cut_rounded, LibraryGroupTone.rose, [
    '发型',
    '髮型',
    '头发',
    '頭髮',
    '发色',
    '髮色',
    'hair',
    'hairstyle',
    'hairstyles',
    '髪型',
    '髪',
  ]),
  eyes(Icons.visibility_outlined, LibraryGroupTone.sky, [
    '眼睛',
    '眼',
    '瞳',
    '瞳色',
    'eye',
    'eyes',
    '目',
  ]),
  expression(Icons.sentiment_satisfied_outlined, LibraryGroupTone.peach, [
    '表情',
    '神情',
    'expression',
    'expressions',
    'face',
  ]),
  outfit(Icons.checkroom_rounded, LibraryGroupTone.lilac, [
    '服装',
    '服裝',
    '衣服',
    '服饰',
    '服飾',
    '穿着',
    '穿著',
    'outfit',
    'outfits',
    'clothes',
    'clothing',
    'costume',
    '衣装',
  ]),
  accessory(Icons.diamond_outlined, LibraryGroupTone.lilac, [
    '饰品',
    '飾品',
    '配饰',
    '配飾',
    '首饰',
    '首飾',
    'accessory',
    'accessories',
    'アクセサリー',
    '装飾品',
  ]),
  pose(Icons.directions_walk_rounded, LibraryGroupTone.sage, [
    '动作',
    '動作',
    '姿势',
    '姿勢',
    'pose',
    'poses',
    'action',
    'actions',
    'ポーズ',
  ]),
  composition(Icons.crop_free_rounded, LibraryGroupTone.sky, [
    '构图',
    '構圖',
    '镜头',
    '鏡頭',
    '视角',
    '視角',
    'composition',
    'camera',
    'angle',
    '構図',
    'アングル',
  ]),
  scene(Icons.landscape_outlined, LibraryGroupTone.teal, [
    '场景',
    '場景',
    '场所',
    '場所',
    'scene',
    'scenes',
    'scenery',
    'location',
    'シーン',
    '場面',
  ]),
  background(Icons.wallpaper_rounded, LibraryGroupTone.teal, [
    '背景',
    'background',
    'backgrounds',
  ]),
  lighting(Icons.wb_sunny_outlined, LibraryGroupTone.sand, [
    '光影',
    '光照',
    '灯光',
    '燈光',
    '光线',
    '光線',
    'lighting',
    'light',
    'ライティング',
    '光',
  ]),
  weather(Icons.cloud_outlined, LibraryGroupTone.sky, [
    '天气',
    '天氣',
    'weather',
    '天気',
  ]),
  style(Icons.palette_outlined, LibraryGroupTone.lilac, [
    '风格',
    '風格',
    '画风',
    '畫風',
    'style',
    'styles',
    'art style',
    'スタイル',
    '画風',
  ]),
  artist(Icons.brush_outlined, LibraryGroupTone.rose, [
    '画师',
    '畫師',
    '艺术家',
    '藝術家',
    '画家',
    '畫家',
    'artist',
    'artists',
    '絵師',
  ]),
  color(Icons.invert_colors_rounded, LibraryGroupTone.peach, [
    '色彩',
    '颜色',
    '顏色',
    '配色',
    '色调',
    '色調',
    'color',
    'colors',
    'colour',
    'colours',
    '色',
    'カラー',
  ]),
  quality(Icons.workspace_premium_outlined, LibraryGroupTone.sand, [
    '质量',
    '質量',
    '画质',
    '畫質',
    '品质',
    '品質',
    'quality',
    '画質',
  ]),
  prop(Icons.inventory_2_outlined, LibraryGroupTone.peach, [
    '道具',
    '物品',
    '小物',
    'prop',
    'props',
    'item',
    'items',
    'object',
    'objects',
  ]),
  animal(Icons.pets_rounded, LibraryGroupTone.sage, [
    '动物',
    '動物',
    '宠物',
    '寵物',
    'animal',
    'animals',
    'pet',
    'pets',
  ]),
  effect(Icons.auto_awesome_outlined, LibraryGroupTone.lilac, [
    '特效',
    '效果',
    'effect',
    'effects',
    'fx',
    'エフェクト',
  ]),
  negative(Icons.block_rounded, LibraryGroupTone.slate, [
    '负面',
    '負面',
    '反向',
    '负向',
    '負向',
    'negative',
    'negatives',
    'ネガティブ',
  ]);

  const LibraryGroupPreset(this.icon, this.tone, this.aliases);

  final IconData icon;
  final LibraryGroupTone tone;

  /// Names that pick this preset, compared after [normalizeName].
  final List<String> aliases;

  String label(AppLocalizations l10n) => switch (this) {
    character => l10n.libraryGroup_character,
    hair => l10n.libraryGroup_hair,
    eyes => l10n.libraryGroup_eyes,
    expression => l10n.libraryGroup_expression,
    outfit => l10n.libraryGroup_outfit,
    accessory => l10n.libraryGroup_accessory,
    pose => l10n.libraryGroup_pose,
    composition => l10n.libraryGroup_composition,
    scene => l10n.libraryGroup_scene,
    background => l10n.libraryGroup_background,
    lighting => l10n.libraryGroup_lighting,
    weather => l10n.libraryGroup_weather,
    style => l10n.libraryGroup_style,
    artist => l10n.libraryGroup_artist,
    color => l10n.libraryGroup_color,
    quality => l10n.libraryGroup_quality,
    prop => l10n.libraryGroup_prop,
    animal => l10n.libraryGroup_animal,
    effect => l10n.libraryGroup_effect,
    negative => l10n.libraryGroup_negative,
  };

  static final Map<String, LibraryGroupPreset> _byAlias = {
    for (final preset in values)
      for (final alias in preset.aliases) normalizeName(alias): preset,
  };

  /// The preset a group named [name] gets, or null for a custom name.
  static LibraryGroupPreset? match(String name) =>
      _byAlias[normalizeName(name)];

  static String normalizeName(String name) =>
      name.trim().toLowerCase().replaceAll(RegExp(r'[\s_\-·・]+'), ' ');
}

/// How a group is drawn: its icon and the tone behind it.
@immutable
class LibraryGroupStyle {
  const LibraryGroupStyle({required this.icon, required this.tone});

  /// Custom groups and entries outside any group.
  static const generic = LibraryGroupStyle(
    icon: Icons.sell_outlined,
    tone: LibraryGroupTone.slate,
  );

  factory LibraryGroupStyle.ofPreset(LibraryGroupPreset preset) =>
      LibraryGroupStyle(icon: preset.icon, tone: preset.tone);

  /// The style of group [categoryId]: its own preset, else the nearest
  /// parent's, so a custom subgroup of 服装 still reads as clothing.
  factory LibraryGroupStyle.of(
    String? categoryId,
    List<TagLibraryCategory> categories,
  ) {
    var id = categoryId;
    final seen = <String>{};
    while (id != null && seen.add(id)) {
      final current = id;
      final category = categories
          .where((candidate) => candidate.id == current)
          .firstOrNull;
      if (category == null) break;
      final preset = LibraryGroupPreset.match(category.name);
      if (preset != null) return LibraryGroupStyle.ofPreset(preset);
      id = category.parentId;
    }
    return generic;
  }

  final IconData icon;
  final LibraryGroupTone tone;

  static final Map<(LibraryGroupTone, Brightness), ColorScheme> _schemes = {};

  /// The tile color and the icon color on it.
  ({Color background, Color foreground}) colorsIn(ColorScheme scheme) {
    final seed = tone.seed;
    if (seed == null) {
      return (
        background: controlSurfaceColor(scheme),
        foreground: scheme.onSurfaceVariant,
      );
    }
    final toned = _schemes.putIfAbsent(
      (tone, scheme.brightness),
      () =>
          ColorScheme.fromSeed(seedColor: seed, brightness: scheme.brightness),
    );
    return (
      background: toned.primaryContainer,
      foreground: toned.onPrimaryContainer,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LibraryGroupStyle && other.icon == icon && other.tone == tone;

  @override
  int get hashCode => Object.hash(icon, tone);
}

/// A group's icon on its tinted rounded tile.
class LibraryGroupIcon extends StatelessWidget {
  const LibraryGroupIcon({
    super.key,
    required this.style,
    this.size = 40,
    this.iconSize,
    this.radius,
  });

  final LibraryGroupStyle style;
  final double size;
  final double? iconSize;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final colors = style.colorsIn(Theme.of(context).colorScheme);
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(radius ?? size * 0.3),
        ),
        child: Icon(
          style.icon,
          size: iconSize ?? size * 0.5,
          color: colors.foreground,
        ),
      ),
    );
  }
}
