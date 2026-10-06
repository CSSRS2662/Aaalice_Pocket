import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../providers/character_prompt_provider.dart';
import '../../../providers/image_generation_provider.dart';
import '../../../providers/prompt_config_provider.dart';
import '../../../widgets/common/app_toast.dart';

/// Replaces the prompt with a random one, then reports the characters it
/// generated or why it failed.
Future<void> applyRandomPrompt(BuildContext context, WidgetRef ref) async {
  try {
    await ref
        .read(imageGenerationNotifierProvider.notifier)
        .generateAndApplyRandomPrompt();
  } catch (error) {
    if (!context.mounted) return;
    AppToast.error(
      context,
      error is UnsupportedRandomPromptModelException
          ? context.l10n.randomPrompt_unsupportedModelHint
          : context.l10n.tagLibrary_generateFailed(error.toString()),
    );
    return;
  }
  if (!context.mounted) return;
  final characters = ref
      .read(characterPromptNotifierProvider)
      .characters
      .where((character) => character.enabled && character.prompt.isNotEmpty)
      .length;
  if (characters > 0) {
    AppToast.success(
      context,
      context.l10n.tagLibrary_generatedCharacters(characters.toString()),
    );
  }
}
