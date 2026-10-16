import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/autocomplete/autocomplete_settings.dart'
    as completion_settings;
import '../../../../core/platform/platform_capabilities.dart';
import '../../../../core/utils/localization_extension.dart';
import '../../../adaptive/interaction_policy.dart';
import '../../../../core/utils/nai_prompt_parser.dart';
import '../../../../data/models/character/character_prompt.dart';
import '../../../providers/character_prompt_provider.dart';
import '../../../providers/character_workspace_provider.dart';
import '../../../providers/image_generation_provider.dart';
import '../../../themes/theme_extension.dart';
import '../../../providers/prompt_regex_rules_provider.dart';
import '../../../widgets/character/character_prompt_button.dart';
import '../../../widgets/prompt/fixed_tags_button.dart';
import '../../../widgets/prompt/prompt_control_button.dart';
import '../../../widgets/prompt/quality_tags_selector.dart';
import '../../../widgets/prompt/regex_rules_dialog.dart';
import '../../../widgets/prompt/toolbar/toolbar.dart';
import '../../../widgets/prompt/uc_preset_selector.dart';
import 'prompt_clear_all_button.dart';
import 'prompt_group_controller.dart';
import 'prompt_input_controller.dart';
import 'prompt_editor_mode_switch.dart';
import 'prompt_input_models.dart';
import '../../../widgets/prompt/prompt_footer_style.dart';
import 'prompt_type_switch.dart';

class PromptInputToolbar extends ConsumerWidget {
  const PromptInputToolbar({
    super.key,
    required this.controller,
    required this.commands,
    required this.viewData,
    this.mobileFullscreen = false,
    this.mobileEditor,
    this.mobileFooter,
  });

  final PromptInputController controller;
  final PromptInputCommands commands;
  final PromptInputViewData viewData;
  final bool mobileFullscreen;
  final Widget? mobileEditor;
  final Widget? mobileFooter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final model = ref.watch(
      generationParamsNotifierProvider.select((params) => params.model),
    );
    if (mobileFullscreen) {
      return _MobileFullscreenToolbar(
        controller: controller,
        commands: commands,
        model: model,
        editor: mobileEditor!,
        footer: mobileFooter!,
      );
    }

    final typeSwitch = PromptTypeSwitch(
      controller: controller,
      commands: commands,
    );
    final toolbar = _fullscreenToolbar();

    return LayoutBuilder(
      builder: (context, constraints) {
        final usesLargeText = MediaQuery.textScalerOf(context).scale(14) > 21;
        final usesCompactSingleRow =
            viewData.autoGrow && constraints.maxWidth >= 360 && !usesLargeText;
        if (usesCompactSingleRow) {
          final showUtilityLabels =
              constraints.maxWidth >= (viewData.showMaximizeButton ? 520 : 450);
          return SizedBox(
            key: const ValueKey('generation_prompt_compact_single_row'),
            height: 48,
            child: Row(
              children: [
                Expanded(
                  child: PromptTypeSwitch(
                    controller: controller,
                    commands: commands,
                    expand: true,
                    compact: true,
                  ),
                ),
                const SizedBox(width: 4),
                Row(
                  key: const ValueKey(
                    'generation_prompt_compact_single_row_actions',
                  ),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FixedTagsButton(
                      compact: true,
                      iconOnly: !showUtilityLabels,
                      maxLabelWidth: showUtilityLabels ? 48 : null,
                    ),
                    const SizedBox(width: 4),
                    QualityTagsSelector(
                      model: model,
                      compact: true,
                      iconOnly: !showUtilityLabels,
                      maxLabelWidth: showUtilityLabels ? 48 : null,
                    ),
                    const SizedBox(width: 4),
                    UcPresetSelector(
                      model: model,
                      compact: true,
                      iconOnly: !showUtilityLabels,
                      maxLabelWidth: showUtilityLabels ? 48 : null,
                    ),
                    const SizedBox(width: 4),
                    toolbar,
                  ],
                ),
              ],
            ),
          );
        }
        if (constraints.maxWidth < 600) {
          final primary = _fullscreenToolbar();
          final showTouchCharacter =
              context.interactionPolicy.shouldExposeTouchAlternatives;
          final typeSwitch = PromptTypeSwitch(
            controller: controller,
            commands: commands,
            expand: true,
            compact: true,
          );
          final stackPrimary = constraints.maxWidth < 360 || usesLargeText;
          return Column(
            key: const ValueKey('generation_prompt_mobile_toolbar'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PromptEditorModeControls(
                controller: controller,
                commands: commands,
              ),
              const SizedBox(height: 4),
              if (stackPrimary) ...[
                typeSwitch,
                const SizedBox(height: 4),
                Align(alignment: Alignment.centerRight, child: primary),
              ] else
                Row(
                  key: const ValueKey('generation_prompt_mobile_primary_row'),
                  children: [
                    Expanded(child: typeSwitch),
                    const SizedBox(width: 6),
                    primary,
                  ],
                ),
              const SizedBox(height: 4),
              Wrap(
                key: const ValueKey('generation_prompt_mobile_secondary_row'),
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const _MobilePromptToolbarAction(
                    actionKey: ValueKey(
                      'generation_prompt_mobile_fixed_tags_action',
                    ),
                    child: FixedTagsButton(),
                  ),
                  _MobilePromptToolbarAction(
                    actionKey: const ValueKey(
                      'generation_prompt_mobile_quality_action',
                    ),
                    child: QualityTagsSelector(model: model),
                  ),
                  _MobilePromptToolbarAction(
                    actionKey: const ValueKey(
                      'generation_prompt_mobile_uc_action',
                    ),
                    child: UcPresetSelector(model: model),
                  ),
                  if (showTouchCharacter)
                    const _MobilePromptToolbarAction(
                      actionKey: ValueKey(
                        'generation_prompt_mobile_character_action',
                      ),
                      child: CharacterPromptButton(),
                    ),
                ],
              ),
            ],
          );
        }

        return Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: controller.isGroupedMode ? 360 : 240,
                  child: PromptEditorModeControls(
                    controller: controller,
                    commands: commands,
                  ),
                ),
                typeSwitch,
              ],
            ),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const FixedTagsButton(compact: true),
                QualityTagsSelector(model: model),
                UcPresetSelector(model: model),
                toolbar,
              ],
            ),
          ],
        );
      },
    );
  }

  PromptEditorToolbar _fullscreenToolbar() => PromptEditorToolbar(
    config: PromptEditorToolbarConfig.mainEditor.copyWith(
      showRandomButton: false,
      showFullscreenButton: viewData.showMaximizeButton,
      showClearButton: false,
      showSettingsButton: false,
    ),
    onFullscreenPressed: commands.toggleMaximize,
    isFullscreen: viewData.isMaximized,
  );

  static Future<void> _showSettingsMenu(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final position = PromptEditorToolbar.getSettingsButtonPosition(context);
    if (position == null) return;
    final theme = Theme.of(context);
    final autocomplete = ref.read(autocompleteSettingsProvider);
    final autoFormat = ref.read(autoFormatPromptSettingsProvider);
    final highlight = ref.read(highlightEmphasisSettingsProvider);
    final sdConvert = ref.read(sdSyntaxAutoConvertSettingsProvider);
    final resolveAlias = ref.read(resolveAliasOnCopySettingsProvider);
    final cooccurrence = ref
        .read(completion_settings.autocompleteSettingsProvider)
        .relatedTagsEnabled;
    final regexCount = ref.read(promptRegexRulesProvider).length;
    final value = await showMenu<String>(
      context: context,
      position: position,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      items: [
        _toggleItem(
          context,
          theme,
          'autocomplete',
          autocomplete,
          context.l10n.prompt_smartAutocomplete,
          context.l10n.prompt_smartAutocompleteSubtitle,
        ),
        _toggleItem(
          context,
          theme,
          'auto_format',
          autoFormat,
          context.l10n.prompt_autoFormat,
          context.l10n.prompt_autoFormatSubtitle,
        ),
        _toggleItem(
          context,
          theme,
          'highlight',
          highlight,
          context.l10n.prompt_highlightEmphasis,
          context.l10n.prompt_highlightEmphasisSubtitle,
        ),
        _toggleItem(
          context,
          theme,
          'sd_syntax_convert',
          sdConvert,
          context.l10n.prompt_sdSyntaxAutoConvert,
          context.l10n.prompt_sdSyntaxAutoConvertSubtitle,
        ),
        _actionItem(
          theme,
          'regex_rules',
          Icons.find_replace,
          context.l10n.prompt_regexRulesManage,
          context.l10n.prompt_regexRulesCount(regexCount),
        ),
        _toggleItem(
          context,
          theme,
          'resolve_alias_on_copy',
          resolveAlias,
          context.l10n.prompt_resolveAliasOnCopy,
          context.l10n.prompt_resolveAliasOnCopySubtitle,
        ),
        _toggleItem(
          context,
          theme,
          'cooccurrence',
          cooccurrence,
          context.l10n.prompt_cooccurrenceRecommendation,
          PlatformCapabilities.current.supportsKeyboardShortcutConfiguration
              ? context.l10n.prompt_cooccurrenceRecommendationSubtitle
              : context.l10n.autocomplete_relatedTagsSubtitleTouch,
        ),
      ],
    );
    if (!context.mounted) return;
    switch (value) {
      case 'autocomplete':
        ref.read(autocompleteSettingsProvider.notifier).toggle();
      case 'auto_format':
        ref.read(autoFormatPromptSettingsProvider.notifier).toggle();
      case 'highlight':
        ref.read(highlightEmphasisSettingsProvider.notifier).toggle();
      case 'sd_syntax_convert':
        ref.read(sdSyntaxAutoConvertSettingsProvider.notifier).toggle();
      case 'regex_rules':
        RegexRulesDialog.show(context);
      case 'resolve_alias_on_copy':
        ref.read(resolveAliasOnCopySettingsProvider.notifier).toggle();
      case 'cooccurrence':
        final provider = completion_settings.autocompleteSettingsProvider;
        final current = ref.read(provider).relatedTagsEnabled;
        ref.read(provider.notifier).setRelatedTagsEnabled(!current);
      case null:
        return;
    }
  }

  static PopupMenuItem<String> _toggleItem(
    BuildContext context,
    ThemeData theme,
    String value,
    bool enabled,
    String title,
    String subtitle,
  ) => PopupMenuItem<String>(
    value: value,
    child: Row(
      children: [
        Icon(
          enabled ? Icons.check_box : Icons.check_box_outline_blank,
          size: 20,
          color: enabled ? theme.colorScheme.primary : null,
        ),
        const SizedBox(width: 12),
        Expanded(child: _menuLabels(theme, title, subtitle)),
      ],
    ),
  );

  static PopupMenuItem<String> _actionItem(
    ThemeData theme,
    String value,
    IconData icon,
    String title,
    String subtitle,
  ) => PopupMenuItem<String>(
    value: value,
    child: Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(child: _menuLabels(theme, title, subtitle)),
        Icon(Icons.chevron_right, size: 18, color: theme.colorScheme.outline),
      ],
    ),
  );

  static Widget _menuLabels(ThemeData theme, String title, String subtitle) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      );
}

class PromptInputBottomActions extends ConsumerWidget {
  const PromptInputBottomActions({
    super.key,
    required this.controller,
    required this.commands,
    this.showClearButton = true,
    this.showEditorModeButton = true,
    this.clearAllInsteadOfRandom = false,
  });

  final PromptInputController controller;
  final PromptInputCommands commands;
  final bool showClearButton;
  final bool showEditorModeButton;

  /// Puts the confirmed clear-all action where the random prompt button sits;
  /// the phone workbench draws random prompts from the dice in its bottom bar.
  final bool clearAllInsteadOfRandom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showRandomTools =
        !clearAllInsteadOfRandom &&
        ref.watch(randomPromptToolsVisibilityProvider);
    final buttonStyle = PromptFooterStyle.button(context).copyWith(
      padding: const WidgetStatePropertyAll(EdgeInsets.zero),
      fixedSize: WidgetStatePropertyAll(
        Size.square(PromptFooterStyle.height(context)),
      ),
    );
    final nextMode = controller.isGroupedMode
        ? PromptEditorMode.single
        : PromptEditorMode.grouped;
    return Row(
      key: const ValueKey('generation_prompt_bottom_actions'),
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showEditorModeButton)
          IconButton(
            key: const ValueKey('generation_prompt_editor_mode_compact_action'),
            style: PromptFooterStyle.button(context).copyWith(
              padding: const WidgetStatePropertyAll(EdgeInsets.zero),
              fixedSize: WidgetStatePropertyAll(
                Size.square(PromptFooterStyle.height(context)),
              ),
            ),
            tooltip: nextMode == PromptEditorMode.grouped
                ? context.l10n.prompt_groupedEditorMode
                : context.l10n.prompt_singleEditorMode,
            onPressed: () => commands.setEditorMode(nextMode),
            icon: Icon(
              controller.isGroupedMode
                  ? Icons.notes_rounded
                  : Icons.view_agenda_outlined,
              size: PromptFooterStyle.iconSize,
            ),
          ),
        if (showEditorModeButton && controller.isGroupedMode)
          IconButton(
            key: ValueKey(
              controller.isNegativeMode
                  ? 'add_negative_prompt_group'
                  : 'add_positive_prompt_group',
            ),
            style: PromptFooterStyle.button(context).copyWith(
              padding: const WidgetStatePropertyAll(EdgeInsets.zero),
              fixedSize: WidgetStatePropertyAll(
                Size.square(PromptFooterStyle.height(context)),
              ),
            ),
            tooltip: context.l10n.prompt_addGroup,
            // The grid opens the new section in its editor.
            onPressed: () =>
                controller.groupsFor(controller.isNegativeMode).add(),
            icon: const Icon(
              Icons.add_circle_outline_rounded,
              size: PromptFooterStyle.iconSize,
            ),
          ),
        PromptEditorToolbar(
          buttonStyle: buttonStyle,
          actionIconSize: PromptFooterStyle.iconSize,
          leadingActions: [
            if (clearAllInsteadOfRandom)
              PromptClearAllButton(
                controller: controller,
                commands: commands,
                style: buttonStyle,
                iconSize: PromptFooterStyle.iconSize,
              ),
          ],
          config: PromptEditorToolbarConfig.mainEditor.copyWith(
            showRandomButton: showRandomTools,
            showFullscreenButton: false,
            showClearButton: showClearButton,
          ),
          onRandomPressed: showRandomTools
              ? commands.generateRandomPrompt
              : null,
          onClearPressed: controller.isNegativeMode
              ? commands.clearNegativePrompt
              : commands.clearPrompt,
          onSettingsPressed: () =>
              PromptInputToolbar._showSettingsMenu(context, ref),
        ),
      ],
    );
  }
}

class _MobileFullscreenToolbar extends ConsumerWidget {
  const _MobileFullscreenToolbar({
    required this.controller,
    required this.commands,
    required this.model,
    required this.editor,
    required this.footer,
  });

  final PromptInputController controller;
  final PromptInputCommands commands;
  final String model;
  final Widget editor;
  final Widget footer;

  /// Tags of the characters taking part, per side, for the count badge.
  static ({int positive, int negative}) _characterCounts(
    List<CharacterPrompt> characters,
  ) {
    var positive = 0;
    var negative = 0;
    for (final character in characters) {
      if (!character.enabled) continue;
      positive += NaiPromptParser.splitSegments(character.prompt).length;
      negative += NaiPromptParser.splitSegments(
        character.negativePrompt,
      ).length;
    }
    return (positive: positive, negative: negative);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final characterMode = ref.watch(characterWorkspaceActiveProvider);
    final characters = ref.watch(
      characterPromptNotifierProvider.select((config) => config.characters),
    );
    final charactersGrouped = ref.watch(characterPromptsGroupedProvider);
    return LayoutBuilder(
      key: const ValueKey('generation_prompt_mobile_workbench'),
      builder: (context, constraints) {
        // One 44 dp row of icon controls; the transparent-background switch
        // lives on the image tab (and the parameter page) instead.
        final scaledLabelHeight = MediaQuery.textScalerOf(context).scale(14);
        final controlRowHeight = (scaledLabelHeight * 1.25 + 24).clamp(
          44.0,
          88.0,
        );
        final textGrowth = (scaledLabelHeight / 14).clamp(1.0, 3.0) - 1;
        final actionExtent = 48 + textGrowth * 16;
        final typeSwitchWidth = 84 + textGrowth * 24;
        const gap = 4.0;
        // The switch, the add button and the editing mode act on what the
        // page shows: the main prompt or the characters.
        final typeSwitch = PromptTypeSwitch(
          controller: controller,
          commands: commands,
          compact: true,
          toggleOnly: true,
          iconOnly: true,
          counts: characterMode ? _characterCounts(characters) : null,
        );
        final Widget? addButton = characterMode
            ? _AddCharacterButton(
                onPressed: () {
                  final adding = ref.read(
                    characterWorkspaceAddingProvider.notifier,
                  );
                  adding.state = !adding.state;
                },
              )
            : controller.isGroupedMode
            ? PromptAddGroupButton(controller: controller, iconOnly: true)
            : null;
        final modeSwitch = characterMode
            ? PromptEditorModeButton(
                buttonKey: const ValueKey(
                  'generation_prompt_editor_mode_switch',
                ),
                grouped: charactersGrouped,
                iconOnly: true,
                onSelected: (mode) => ref
                    .read(characterPromptsGroupedProvider.notifier)
                    .set(mode == PromptEditorMode.grouped),
              )
            : PromptEditorModeSwitch(
                controller: controller,
                commands: commands,
                iconOnly: true,
              );

        final roleActions = PromptRoleSegmentGroup(
          height: controlRowHeight,
          children: [
            _MobilePromptToolbarAction(
              actionKey: const ValueKey(
                'generation_prompt_mobile_character_action',
              ),
              height: controlRowHeight,
              child: CharacterPromptButton(
                onManage: commands.toggleCharacterWorkspace,
                segment: true,
                selected: characterMode,
              ),
            ),
            _MobilePromptToolbarAction(
              actionKey: const ValueKey(
                'generation_prompt_mobile_fixed_tags_action',
              ),
              height: controlRowHeight,
              child: const FixedTagsButton(segment: true),
            ),
            _MobilePromptToolbarAction(
              actionKey: const ValueKey(
                'generation_prompt_mobile_quality_action',
              ),
              height: controlRowHeight,
              child: controller.isNegativeMode
                  ? UcPresetSelector(model: model, segment: true)
                  : QualityTagsSelector(model: model, segment: true),
            ),
          ],
        );

        Widget buildControls() {
          final minimumRoleWidth = actionExtent * 3 + 2;
          final fixedWidth =
              typeSwitchWidth +
              (addButton == null ? 0 : gap + controlRowHeight) +
              gap * 2 +
              controlRowHeight;
          // The role segments take the room left over, so the row has no
          // gaps; only very large text makes it scroll sideways instead.
          final fits = constraints.maxWidth - fixedWidth >= minimumRoleWidth;
          final row = Row(
            children: [
              SizedBox(width: typeSwitchWidth, child: typeSwitch),
              if (addButton != null) ...[
                const SizedBox(width: gap),
                SizedBox.square(dimension: controlRowHeight, child: addButton),
              ],
              const SizedBox(width: gap),
              if (fits)
                Expanded(child: roleActions)
              else
                SizedBox(width: minimumRoleWidth, child: roleActions),
              const SizedBox(width: gap),
              SizedBox.square(dimension: controlRowHeight, child: modeSwitch),
            ],
          );
          return SizedBox(
            key: const ValueKey('generation_prompt_mobile_controls'),
            height: controlRowHeight,
            child: fits
                ? row
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: fixedWidth + minimumRoleWidth,
                      height: controlRowHeight,
                      child: row,
                    ),
                  ),
          );
        }

        Widget buildWorkbench() => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            buildControls(),
            const SizedBox(height: 8),
            Expanded(child: editor),
            footer,
          ],
        );

        if (constraints.maxHeight >= 240) return buildWorkbench();
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final scrollableHeight = 140 * textScale.clamp(1, 3).toDouble();
        return SingleChildScrollView(
          child: SizedBox(height: scrollableHeight, child: buildWorkbench()),
        );
      },
    );
  }
}

/// Adds a character in the character view, where the main prompt's add
/// section button sits otherwise.
class _AddCharacterButton extends StatelessWidget {
  const _AddCharacterButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: context.l10n.character_addCharacter,
      child: Material(
        color: colors.surfaceContainerHigh.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(
          Theme.of(context).appTheme.controlRadius,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const ValueKey('generation_prompt_mobile_add_character'),
          onTap: onPressed,
          child: Center(
            child: Icon(
              Icons.person_add_alt_1_rounded,
              size: 22,
              color: colors.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

class _MobilePromptToolbarAction extends StatelessWidget {
  const _MobilePromptToolbarAction({
    required this.actionKey,
    required this.child,
    this.height = 48,
  });

  final Key actionKey;
  final Widget child;
  final double height;

  @override
  Widget build(BuildContext context) =>
      SizedBox(key: actionKey, height: height, child: child);
}
