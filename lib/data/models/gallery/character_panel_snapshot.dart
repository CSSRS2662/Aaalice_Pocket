import 'dart:convert';

import '../character/character_prompt.dart';

/// 生成一张图时的整个角色面板，只记在本机，供复用参数时原样恢复。
///
/// 图片元数据只带请求里启用的角色提示词与位置；角色名、未启用的角色和
/// 分区都只在这里。[sentPrompts] 是这次请求实际发送的角色提示词，恢复前
/// 先与图片元数据核对，随机批次等换过角色的结果图不会被套上错的面板。
class CharacterPanelSnapshot {
  const CharacterPanelSnapshot({
    required this.config,
    required this.sections,
    required this.sentPrompts,
  });

  static const version = 1;

  final CharacterPromptConfig config;

  /// 角色 ID → 当时保存的分区，格式与角色分区存储相同。
  final Map<String, Object?> sections;
  final List<String> sentPrompts;

  /// 纯 JSON：生成的 toJson 不展开嵌套对象，而元数据会进 Hive。
  Map<String, Object?> toJson() => {
    'version': version,
    'config': jsonDecode(jsonEncode(config)),
    'sections': sections,
    'sentPrompts': sentPrompts,
  };

  static CharacterPanelSnapshot? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final config = raw['config'];
    final sent = raw['sentPrompts'];
    if (config is! Map || sent is! List) return null;
    try {
      final parsed = CharacterPromptConfig.fromJson(
        _plainJson(config) as Map<String, dynamic>,
      );
      if (parsed.characters.isEmpty) return null;
      final sections = raw['sections'];
      return CharacterPanelSnapshot(
        config: parsed,
        sections: sections is Map ? Map<String, Object?>.from(sections) : {},
        sentPrompts: [for (final prompt in sent) prompt.toString()],
      );
    } on Object {
      // 损坏或来自未来版本的记录不影响复用其他参数。
      return null;
    }
  }

  /// Hive 与 jsonDecode 给出的嵌套 Map 类型不一，生成的 fromJson 需要
  /// `Map<String, dynamic>`。
  static Object? _plainJson(Object? value) => switch (value) {
    final Map<Object?, Object?> map => <String, dynamic>{
      for (final entry in map.entries)
        entry.key.toString(): _plainJson(entry.value),
    },
    final List<Object?> list => [for (final item in list) _plainJson(item)],
    _ => value,
  };
}
