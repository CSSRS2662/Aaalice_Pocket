import '../../core/storage/local_storage_service.dart';
import '../../data/models/character/character_prompt.dart' as char;
import '../../data/models/fixed_tag/fixed_tag_entry.dart';
import '../../data/models/fixed_tag/fixed_tag_prompt_type.dart';
import '../../data/models/fixed_tag/fixed_tag_usage_snapshot.dart';
import '../../data/models/gallery/nai_image_metadata.dart';
import '../../data/models/gallery/character_panel_snapshot.dart';
import '../../data/models/metadata/metadata_import_options.dart';
import '../../data/services/prompt_group/character_section_store.dart';
import '../../l10n/app_localizations.dart';
import '../providers/character_prompt_provider.dart';
import '../providers/character_workspace_provider.dart';
import '../providers/fixed_tags_provider.dart';
import '../providers/image_generation_provider.dart';
import '../providers/quality_preset_provider.dart';
import '../providers/prompt_group_state_provider.dart';
import 'metadata_import_applier.dart';
import 'fixed_tag_import_resolution.dart';
import 'prompt_preset_import_utils.dart';

class MetadataImportCoordinator {
  const MetadataImportCoordinator._();

  static Future<int> apply({
    required ProviderReader read,
    required NaiImageMetadata metadata,
    required MetadataImportOptions options,
    required AppLocalizations l10n,
    FixedTagImportResolution? fixedTagResolution,
  }) async {
    final resolution =
        fixedTagResolution ??
        resolveFixedTagImport(
          metadata: metadata,
          entries: read(fixedTagsNotifierProvider).entries,
        );
    final resolvedMetadata = resolution.metadata;
    final notifier = read(generationParamsNotifierProvider.notifier);
    final characterPrompts = resolvedMetadata.characterPrompts;
    final previousCharacters = read(characterPromptNotifierProvider).characters;

    if (options.importCharacterPrompts && characterPrompts.isNotEmpty) {
      read(characterPromptNotifierProvider.notifier).clearAllCharacters();
    }

    final currentModel = read(generationParamsNotifierProvider).model;
    var appliedCount = MetadataImportApplier.applyPromptAndGenerationParams(
      metadata: resolvedMetadata,
      options: options,
      currentModel: currentModel,
      target: MetadataImportTarget(
        updatePrompt: notifier.updatePrompt,
        updateNegativePrompt: notifier.updateNegativePrompt,
        updateSeed: notifier.updateSeed,
        updateSteps: notifier.updateSteps,
        updateScale: notifier.updateScale,
        updateSize: notifier.updateSize,
        updateSampler: notifier.updateSampler,
        updateModel: (value) =>
            notifier.updateModel(value, followDefaults: false),
        updateSmea: notifier.updateSmea,
        updateSmeaDyn: notifier.updateSmeaDyn,
        updateVarietyPlus: notifier.updateVarietyPlus,
        updateNoiseSchedule: notifier.updateNoiseSchedule,
        updateCfgRescale: notifier.updateCfgRescale,
        updateQualityToggle: (value) {
          notifier.updateQualityToggle(value);
          applyImportedQualityToggle(read, value);
        },
        updateQualityTier: (value) {
          read(qualityPresetNotifierProvider.notifier).setNaiTier(value);
        },
        updateUcPreset: (value) {
          notifier.updateUcPreset(value);
          applyImportedUcPreset(read, value);
        },
        updateTransparentBackground: notifier.updateTransparentBackground,
        updateModelMode: notifier.updateModelMode,
      ),
    );

    if (options.importCharacterPrompts && characterPrompts.isNotEmpty) {
      _applyCharacterPrompts(read, resolvedMetadata, previousCharacters);
      appliedCount++;
    }

    appliedCount += _applyReferenceParams(read, resolvedMetadata, options);
    appliedCount += await _applyFixedTags(
      read,
      resolvedMetadata,
      options,
      l10n,
      resolution,
    );

    final promptGroupSnapshot = resolvedMetadata.promptGroupSnapshot;
    if (promptGroupSnapshot != null &&
        promptGroupSnapshot.hasPromptSections &&
        (options.importPrompt || options.importNegativePrompt)) {
      read(
        promptGroupRestoreRequestProvider.notifier,
      ).state = PromptGroupRestoreRequest(
        snapshot: promptGroupSnapshot,
        restorePositive: options.importPrompt,
        restoreNegative: options.importNegativePrompt,
      );
    }

    return appliedCount;
  }

  static Future<int> _applyFixedTags(
    ProviderReader read,
    NaiImageMetadata metadata,
    MetadataImportOptions options,
    AppLocalizations l10n,
    FixedTagImportResolution resolution,
  ) async {
    if (!options.importFixedTags) {
      return 0;
    }

    final scopes = <FixedTagScope>{};
    void addSelectedScopes(FixedTagPromptType promptType) {
      final isPositive = promptType == FixedTagPromptType.positive;
      if (isPositive
          ? options.importFixedPrefix
          : options.importFixedNegativePrefix) {
        scopes.add(FixedTagScope(promptType, FixedTagPosition.prefix));
      }
      if (isPositive
          ? options.importFixedSuffix
          : options.importFixedNegativeSuffix) {
        scopes.add(FixedTagScope(promptType, FixedTagPosition.suffix));
      }
    }

    FixedTagUsageSnapshot snapshot;
    if (resolution.isUnknown) {
      if (options.unknownFixedTagPolicy == UnknownFixedTagPolicy.keepCurrent) {
        return 0;
      }
      if (options.importPrompt && metadata.prompt.isNotEmpty) {
        addSelectedScopes(FixedTagPromptType.positive);
      }
      if (options.importNegativePrompt && metadata.negativePrompt.isNotEmpty) {
        addSelectedScopes(FixedTagPromptType.negative);
      }
      snapshot = const FixedTagUsageSnapshot();
    } else {
      addSelectedScopes(FixedTagPromptType.positive);
      addSelectedScopes(FixedTagPromptType.negative);
      snapshot = resolution.snapshot ?? const FixedTagUsageSnapshot();
    }
    if (scopes.isEmpty) return 0;

    await read(fixedTagsNotifierProvider.notifier).restoreUsageSnapshot(
      snapshot: snapshot,
      scopes: scopes,
      buildImageVersionName: l10n.metadataImport_imageVersionName,
    );
    return 1;
  }

  /// The image's characters onto the panel.
  ///
  /// The image only carries the prompts and places of the characters it was
  /// generated with. When this device recorded the whole panel for it, the
  /// panel comes back as it was: names, sections and the characters left out
  /// of that generation. Otherwise characters still on the panel with the same
  /// prompt keep their name and sections, and left-out ones stay.
  static void _applyCharacterPrompts(
    ProviderReader read,
    NaiImageMetadata metadata,
    List<char.CharacterPrompt> previous,
  ) {
    final notifier = read(characterPromptNotifierProvider.notifier);
    // An open character keeps its sections in memory; closing it makes the
    // next opening read the restored ones.
    read(characterWorkspaceExpandedProvider.notifier).state = null;
    final panel = metadata.promptGroupSnapshot?.characters;
    if (panel != null && _panelSent(panel, metadata.characterPrompts)) {
      CharacterSectionStore.restore(
        read(localStorageServiceProvider),
        panel.sections,
      );
      notifier.restoreConfig(panel.config);
      return;
    }

    final characters = <char.CharacterPrompt>[];
    final negativePrompts = metadata.characterNegativePrompts;
    final characterInfos = metadata.characterInfos;
    var hasImportedCenters = false;

    for (var i = 0; i < metadata.characterPrompts.length; i++) {
      final prompt = metadata.characterPrompts[i];
      final info = i < characterInfos.length ? characterInfos[i] : null;
      final negativePrompt =
          info?.negativePrompt ??
          (i < negativePrompts.length ? negativePrompts[i] : '');
      final centerX = info?.centerX;
      final centerY = info?.centerY;
      final hasCenter =
          centerX != null &&
          centerY != null &&
          centerX.isFinite &&
          centerY.isFinite;
      hasImportedCenters = hasImportedCenters || hasCenter;

      characters.add(
        char.CharacterPrompt.create(
          name: 'Character ${i + 1}',
          gender: _inferGenderFromPrompt(prompt),
          prompt: prompt,
          negativePrompt: negativePrompt,
          positionMode: hasCenter
              ? char.CharacterPositionMode.custom
              : char.CharacterPositionMode.aiChoice,
          customPosition: hasCenter
              ? char.CharacterPosition(
                  mode: char.CharacterPositionMode.custom,
                  row: centerY.clamp(0.0, 1.0),
                  column: centerX.clamp(0.0, 1.0),
                )
              : null,
        ),
      );
    }

    notifier.replaceAll(keepPanelCharacters(characters, previous));
    final useCoords = metadata.characterUseCoords ?? hasImportedCenters;
    notifier.setGlobalAiChoice(!useCoords);
  }

  /// Whether [panel] was recorded for a request that sent [prompts]; random
  /// batches change the characters after the panel is recorded.
  static bool _panelSent(CharacterPanelSnapshot panel, List<String> prompts) {
    final sent = panel.sentPrompts;
    if (sent.length != prompts.length) return false;
    for (var index = 0; index < sent.length; index++) {
      if (!PromptGroupRestoreRequest.samePromptTags(
        prompts[index],
        sent[index],
      )) {
        return false;
      }
    }
    return true;
  }

  /// [imported] characters, reusing the panel's [current] ones that have the
  /// same prompt (their id, name and sections stay), with the current
  /// characters that were left out of generation kept where they were.
  static List<char.CharacterPrompt> keepPanelCharacters(
    List<char.CharacterPrompt> imported,
    List<char.CharacterPrompt> current,
  ) {
    final unused = [...current];
    final merged = <char.CharacterPrompt>[];
    for (final character in imported) {
      final index = unused.indexWhere(
        (item) => PromptGroupRestoreRequest.samePromptTags(
          item.prompt,
          character.prompt,
        ),
      );
      if (index < 0) {
        merged.add(character);
        continue;
      }
      final match = unused.removeAt(index);
      merged.add(
        match.copyWith(
          negativePrompt:
              PromptGroupRestoreRequest.samePromptTags(
                match.negativePrompt,
                character.negativePrompt,
              )
              ? match.negativePrompt
              : character.negativePrompt,
          positionMode: character.positionMode,
          customPosition: character.customPosition,
          enabled: true,
        ),
      );
    }
    for (final (index, character) in current.indexed) {
      if (character.enabled || !unused.contains(character)) continue;
      merged.insert(index.clamp(0, merged.length), character);
    }
    return merged;
  }

  static char.CharacterGender _inferGenderFromPrompt(String prompt) {
    final lowerPrompt = prompt.toLowerCase();
    if (lowerPrompt.contains('1girl') ||
        lowerPrompt.contains('girl,') ||
        lowerPrompt.startsWith('girl')) {
      return char.CharacterGender.female;
    }
    if (lowerPrompt.contains('1boy') ||
        lowerPrompt.contains('boy,') ||
        lowerPrompt.startsWith('boy')) {
      return char.CharacterGender.male;
    }
    return char.CharacterGender.other;
  }

  static int _applyReferenceParams(
    ProviderReader read,
    NaiImageMetadata metadata,
    MetadataImportOptions options,
  ) {
    final notifier = read(generationParamsNotifierProvider.notifier);
    var count = 0;

    if (options.importVibeReferences && metadata.vibeReferences.isNotEmpty) {
      final selectedVibes = metadata.vibeReferences
          .asMap()
          .entries
          .where((entry) => options.selectedVibeIndices.contains(entry.key))
          .map((entry) => entry.value)
          .toList();
      if (selectedVibes.isNotEmpty) {
        notifier.clearVibeReferences();
        notifier.addVibeReferences(selectedVibes, recordUsage: false);
        count++;
      }
    }

    final preciseReferences = metadata.preciseReferences;
    if (options.importPreciseReferences && preciseReferences.isNotEmpty) {
      final selectedReferences = preciseReferences
          .asMap()
          .entries
          .where(
            (entry) =>
                options.selectedPreciseReferenceIndices.contains(entry.key),
          )
          .map((entry) => entry.value)
          .toList();
      if (selectedReferences.isNotEmpty) {
        notifier.clearPreciseReferences();
        for (final reference in selectedReferences) {
          notifier.addPreciseReference(
            reference.image,
            type: reference.type,
            strength: reference.strength,
            fidelity: reference.fidelity,
          );
        }
        count++;
      }
    }

    return count;
  }
}
