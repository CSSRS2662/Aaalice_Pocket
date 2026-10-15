import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/character_prompt_block_parser.dart';
import '../../../data/models/character/character_prompt.dart';
import '../../providers/character_prompt_provider.dart';
import '../../providers/tag_library_page_provider.dart';
import '../tag_library/tag_library_picker_dialog.dart';

/// Picks a tag library entry and adds it as a character.
///
/// A negative block in the entry becomes the character's own undesired
/// content. Returns the new character's id, or null when nothing was added.
Future<String?> addCharacterFromLibrary(
  BuildContext context,
  WidgetRef ref,
) async {
  final entry = await TagLibraryPickerDialog.show(context);
  if (entry == null || !context.mounted) return null;
  final parsed = CharacterPromptBlockParser.parse(entry.content);
  ref.read(tagLibraryPageNotifierProvider.notifier).recordUsage(entry.id);
  final before = ref.read(characterPromptNotifierProvider).characters.length;
  ref
      .read(characterPromptNotifierProvider.notifier)
      .addCharacter(
        CharacterGender.female,
        name: entry.displayName,
        prompt: parsed.positivePrompt,
        negativePrompt: parsed.hasNegativeBlock ? parsed.negativePrompt : null,
        thumbnailPath: entry.thumbnail,
      );
  final characters = ref.read(characterPromptNotifierProvider).characters;
  return characters.length > before ? characters.last.id : null;
}
