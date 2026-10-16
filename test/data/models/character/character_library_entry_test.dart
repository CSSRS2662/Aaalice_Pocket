import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/models/character/character_library_entry.dart';
import 'package:nai_launcher/data/models/character/character_prompt.dart';
import 'package:nai_launcher/data/models/gallery/prompt_group_snapshot.dart';

void main() {
  final entry = CharacterLibraryEntry(
    id: 'c1',
    name: 'Alice',
    gender: CharacterGender.female,
    positiveSections: const [
      PromptGroupSectionSnapshot(
        id: 's1',
        text: 'red eyes',
        fixedTagId: 'eyes',
        keepInMain: true,
      ),
      PromptGroupSectionSnapshot(id: 's2', text: 'girl, silver hair'),
      PromptGroupSectionSnapshot(id: 's3', text: 'smile', enabled: false),
    ],
    negativeSections: const [
      PromptGroupSectionSnapshot(id: 'n1', text: 'bad hands'),
    ],
    category: '原创',
    favorite: true,
    useCount: 3,
    lastUsedAt: DateTime.utc(2026, 10, 16, 8),
    createdAt: DateTime.utc(2026, 10, 1),
    updatedAt: DateTime.utc(2026, 10, 2),
  );

  test('joins the included sections into prompts', () {
    expect(entry.prompt, 'red eyes, girl, silver hair');
    expect(entry.negativePrompt, 'bad hands');
    expect(entry.fixedTagCount, 1);
    expect(entry.sectionCount, 4);
  });

  test('comes back whole from JSON, fixed tags included', () {
    final restored = CharacterLibraryEntry.fromJson(
      jsonDecode(jsonEncode(entry.toJson())),
    )!;
    expect(restored.name, 'Alice');
    expect(restored.category, '原创');
    expect(restored.favorite, isTrue);
    expect(restored.useCount, 3);
    expect(restored.lastUsedAt, entry.lastUsedAt!.toLocal());
    final fixed = restored.positiveSections.first;
    expect(fixed.fixedTagId, 'eyes');
    expect(fixed.keepInMain, isTrue);
    expect(restored.positiveSections.last.enabled, isFalse);
    expect(restored.prompt, entry.prompt);
  });

  test('anything else is not an entry', () {
    expect(CharacterLibraryEntry.fromJson('Alice'), isNull);
    expect(CharacterLibraryEntry.fromJson({'name': 'Alice'}), isNull);
  });

  test('fixed tags follow their current content', () {
    final resolved = entry.resolveFixedTags(
      (id) => id == 'eyes' ? 'red eyes, glowing eyes' : null,
    );
    expect(resolved.prompt, 'red eyes, glowing eyes, girl, silver hair');
    expect(resolved.positiveSections.first.keepInMain, isTrue);
    expect(entry.resolveFixedTags((_) => null).prompt, entry.prompt);
  });
}
