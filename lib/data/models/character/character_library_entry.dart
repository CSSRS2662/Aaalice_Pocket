import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../services/prompt_group/character_section_store.dart';
import '../gallery/prompt_group_snapshot.dart';
import 'character_prompt.dart';

/// A character kept in the character library.
///
/// Holds what a character brings into the character bar: its name, gender
/// and the sections of both prompts, fixed tags among them. Placement is
/// left to each picture. Fixed-tag sections keep the tag's content as last
/// resolved, so an entry still reads correctly where the tag is gone.
@immutable
class CharacterLibraryEntry {
  const CharacterLibraryEntry({
    required this.id,
    required this.name,
    this.gender = CharacterGender.female,
    this.positiveSections = const [],
    this.negativeSections = const [],
    this.category = '',
    this.favorite = false,
    this.useCount = 0,
    this.lastUsedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CharacterLibraryEntry.create({
    required String name,
    CharacterGender gender = CharacterGender.female,
    List<PromptGroupSectionSnapshot> positiveSections = const [],
    List<PromptGroupSectionSnapshot> negativeSections = const [],
    String category = '',
  }) {
    final now = DateTime.now();
    return CharacterLibraryEntry(
      id: const Uuid().v4(),
      name: name,
      gender: gender,
      positiveSections: positiveSections,
      negativeSections: negativeSections,
      category: category,
      createdAt: now,
      updatedAt: now,
    );
  }

  static const int maxSections = 64;

  final String id;
  final String name;
  final CharacterGender gender;
  final List<PromptGroupSectionSnapshot> positiveSections;
  final List<PromptGroupSectionSnapshot> negativeSections;

  /// Free-form shelf the list groups by; empty files it as uncategorised.
  final String category;
  final bool favorite;
  final int useCount;
  final DateTime? lastUsedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get prompt => joinSections(positiveSections);
  String get negativePrompt => joinSections(negativeSections);

  int get sectionCount => positiveSections.length + negativeSections.length;

  int get fixedTagCount => [
    ...positiveSections,
    ...negativeSections,
  ].where((section) => section.fixedTagId != null).length;

  List<PromptGroupSectionSnapshot> sectionsFor(bool negative) =>
      negative ? negativeSections : positiveSections;

  /// The included section texts joined as the section editor joins them.
  static String joinSections(Iterable<PromptGroupSectionSnapshot> sections) =>
      CharacterSectionStore.join([
        for (final section in sections)
          if (section.enabled) section.text,
      ]);

  /// The entry with fixed-tag sections set to [contentOf]; null keeps a
  /// section's last content.
  CharacterLibraryEntry resolveFixedTags(
    String? Function(String fixedTagId) contentOf,
  ) {
    PromptGroupSectionSnapshot resolveOne(PromptGroupSectionSnapshot section) {
      final id = section.fixedTagId;
      final content = id == null ? null : contentOf(id);
      if (content == null || content == section.text) return section;
      return PromptGroupSectionSnapshot(
        id: section.id,
        text: content,
        enabled: section.enabled,
        collapsed: section.collapsed,
        fixedTagId: id,
        keepInMain: section.keepInMain,
      );
    }

    List<PromptGroupSectionSnapshot> resolve(
      List<PromptGroupSectionSnapshot> sections,
    ) => [for (final section in sections) resolveOne(section)];
    return copyWith(
      positiveSections: resolve(positiveSections),
      negativeSections: resolve(negativeSections),
    );
  }

  CharacterLibraryEntry copyWith({
    String? id,
    String? name,
    CharacterGender? gender,
    List<PromptGroupSectionSnapshot>? positiveSections,
    List<PromptGroupSectionSnapshot>? negativeSections,
    String? category,
    bool? favorite,
    int? useCount,
    DateTime? lastUsedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => CharacterLibraryEntry(
    id: id ?? this.id,
    name: name ?? this.name,
    gender: gender ?? this.gender,
    positiveSections: positiveSections ?? this.positiveSections,
    negativeSections: negativeSections ?? this.negativeSections,
    category: category ?? this.category,
    favorite: favorite ?? this.favorite,
    useCount: useCount ?? this.useCount,
    lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'gender': gender.name,
    'positiveSections': [
      for (final section in positiveSections) section.toJson(),
    ],
    'negativeSections': [
      for (final section in negativeSections) section.toJson(),
    ],
    if (category.isNotEmpty) 'category': category,
    if (favorite) 'favorite': true,
    if (useCount > 0) 'useCount': useCount,
    if (lastUsedAt case final at?) 'lastUsedAt': at.toUtc().toIso8601String(),
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  /// Reads an entry written by [toJson]; null when it is not one.
  static CharacterLibraryEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final name = raw['name'];
    if (id is! String || id.isEmpty || name is! String) return null;
    List<PromptGroupSectionSnapshot> sections(Object? value) => [
      if (value is List)
        for (final item in value.take(maxSections))
          if (PromptGroupSectionSnapshot.fromJson(item) case final section?)
            section.id.isEmpty
                ? PromptGroupSectionSnapshot(
                    id: const Uuid().v4(),
                    text: section.text,
                    enabled: section.enabled,
                    collapsed: section.collapsed,
                    fixedTagId: section.fixedTagId,
                    keepInMain: section.keepInMain,
                  )
                : section,
    ];
    DateTime? time(Object? value) =>
        value is String ? DateTime.tryParse(value)?.toLocal() : null;
    final created = time(raw['createdAt']) ?? DateTime.now();
    return CharacterLibraryEntry(
      id: id,
      name: name,
      gender: CharacterGender.values.firstWhere(
        (gender) => gender.name == raw['gender'],
        orElse: () => CharacterGender.female,
      ),
      positiveSections: sections(raw['positiveSections']),
      negativeSections: sections(raw['negativeSections']),
      category: raw['category'] is String ? raw['category'] as String : '',
      favorite: raw['favorite'] == true,
      useCount: raw['useCount'] is int ? raw['useCount'] as int : 0,
      lastUsedAt: time(raw['lastUsedAt']),
      createdAt: created,
      updatedAt: time(raw['updatedAt']) ?? created,
    );
  }
}
