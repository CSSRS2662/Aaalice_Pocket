import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/utils/localization_extension.dart';
import '../../../data/models/character/character_library_entry.dart';
import '../../../data/models/character/character_prompt.dart';
import '../../prompt_assistant/widgets/prompt_assistant_quick_settings.dart';
import '../../providers/character_library_provider.dart';
import '../../providers/fixed_tags_provider.dart';
import '../../providers/image_generation_provider.dart';
import '../../themes/core/layered_surface_style.dart';
import '../../themes/theme_extension.dart';
import '../../widgets/character/character_marker.dart';
import '../generation/widgets/prompt_group_controller.dart';
import '../generation/widgets/prompt_group_editor.dart';
import 'character_library_actions.dart';

/// Edits one character of the library: name, gender, shelf and the sections
/// of both prompts, fixed tags among them. Every change is kept at once.
class CharacterLibraryEditorScreen extends ConsumerStatefulWidget {
  const CharacterLibraryEditorScreen({super.key, required this.entryId});

  final String entryId;

  @override
  ConsumerState<CharacterLibraryEditorScreen> createState() =>
      _CharacterLibraryEditorScreenState();
}

class _CharacterLibraryEditorScreenState
    extends ConsumerState<CharacterLibraryEditorScreen> {
  late final CharacterLibraryNotifier _library = ref.read(
    characterLibraryProvider.notifier,
  );
  PromptGroupCollection? _positive;
  PromptGroupCollection? _negative;
  late final TextEditingController _name;
  late final TextEditingController _category;
  bool _negativeSide = false;

  @override
  void initState() {
    super.initState();
    final entry = _library.byId(widget.entryId);
    _name = TextEditingController(text: entry?.name ?? '');
    _category = TextEditingController(text: entry?.category ?? '');
    if (entry == null) return;
    PromptGroupCollection load(bool negative) => PromptGroupCollection.fromJson(
      [for (final section in entry.sectionsFor(negative)) section.toJson()],
      fallbackText: '',
    );
    _positive = load(false);
    _negative = load(true);
    final byId = {
      for (final tag in ref.read(fixedTagsNotifierProvider).entries)
        tag.id: tag,
    };
    final positiveChanged = _positive!.resolveFixedTags(
      (id) => byId[id]?.weightedContent,
    );
    final negativeChanged = _negative!.resolveFixedTags(
      (id) => byId[id]?.weightedContent,
    );
    if (positiveChanged || negativeChanged) {
      // Not while the first frame builds: providers can't change then.
      WidgetsBinding.instance.addPostFrameCallback((_) => _commitSections());
    }
  }

  @override
  void dispose() {
    _positive?.dispose();
    _negative?.dispose();
    _name.dispose();
    _category.dispose();
    super.dispose();
  }

  CharacterLibraryEntry? get _current => _library.byId(widget.entryId);

  void _commitSections() {
    final entry = _current;
    if (entry == null || _positive == null) return;
    _library.update(
      entry.copyWith(
        positiveSections: _positive!.toSnapshot(),
        negativeSections: _negative!.toSnapshot(),
      ),
    );
  }

  /// The first included section starts the prompt, so its first tag is the
  /// one that sets the gender; rewriting it keeps the other sections.
  void _setGender(CharacterGender gender) {
    final entry = _current;
    final positive = _positive;
    if (entry == null || positive == null) return;
    final sections = positive.sections.where((s) => !s.isFixedTag).toList();
    final first =
        sections
            .where((s) => s.enabled && s.controller.text.trim().isNotEmpty)
            .firstOrNull ??
        sections.firstOrNull;
    if (first != null) {
      first.controller.text = CharacterPrompt(
        id: entry.id,
        name: entry.name,
        prompt: first.controller.text,
      ).withGender(gender).prompt;
      positive.setEnabled(first.id, true);
    }
    _library.update(
      entry.copyWith(
        gender: gender,
        positiveSections: positive.toSnapshot(),
        negativeSections: _negative!.toSnapshot(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final entry = ref.watch(
      characterLibraryProvider.select(
        (entries) =>
            entries.where((item) => item.id == widget.entryId).firstOrNull,
      ),
    );
    final positive = _positive;
    final negative = _negative;
    if (entry == null || positive == null || negative == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(l10n.characterLibrary_noMatch)),
      );
    }
    final numericEmphasis = ImageModels.isV4Model(
      ref.watch(
        generationParamsNotifierProvider.select((params) => params.model),
      ),
    );
    final groups = _negativeSide ? negative : positive;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.characterLibrary_editTitle),
        actions: [
          IconButton(
            key: const ValueKey('character_library_editor_favorite'),
            onPressed: () => _library.toggleFavorite(entry.id),
            tooltip: entry.favorite
                ? l10n.common_unfavorite
                : l10n.common_favorite,
            icon: Icon(
              entry.favorite
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              color: entry.favorite
                  ? Theme.of(context).colorScheme.error
                  : null,
            ),
          ),
          PopupMenuButton<VoidCallback>(
            tooltip: l10n.common_moreActions,
            onSelected: (action) => action(),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: () =>
                    CharacterLibraryActions.duplicate(context, ref, entry),
                child: Text(l10n.characterLibrary_duplicate),
              ),
              PopupMenuItem(
                value: () async {
                  final navigator = Navigator.of(context);
                  if (await CharacterLibraryActions.delete(
                    context,
                    ref,
                    entry,
                  )) {
                    navigator.pop();
                  }
                },
                child: Text(
                  l10n.common_delete,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          _Identity(
            entry: entry,
            name: _name,
            onName: (value) => _library.update(entry.copyWith(name: value)),
            onGender: _setGender,
          ),
          const SizedBox(height: 12),
          _Category(
            controller: _category,
            categories: _library.categories,
            onChanged: (value) =>
                _library.update(entry.copyWith(category: value.trim())),
          ),
          const SizedBox(height: 16),
          ListenableBuilder(
            listenable: Listenable.merge([positive, negative]),
            builder: (context, _) => _SideTabs(
              negative: _negativeSide,
              positiveCount: positive.sections.length,
              negativeCount: negative.sections.length,
              onChanged: (value) => setState(() => _negativeSide = value),
            ),
          ),
          const SizedBox(height: 10),
          PromptGroupBoard(
            key: ValueKey(_negativeSide),
            groups: groups,
            negative: _negativeSide,
            gridKey: ValueKey(
              _negativeSide
                  ? 'character_library_negative_grid'
                  : 'character_library_positive_grid',
            ),
            listKey: ValueKey(
              _negativeSide
                  ? 'character_library_negative_list'
                  : 'character_library_positive_list',
            ),
            numericEmphasisEnabled: numericEmphasis,
            onCommit: (_) => _commitSections(),
            onOpenAssistantSettings: () =>
                PromptAssistantQuickSettings.show(context),
            excludeFixedTags: false,
            allowFixedTags: true,
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            key: const ValueKey('character_library_editor_add'),
            onPressed: () {
              final current = _current;
              if (current != null) {
                CharacterLibraryActions.addToPanel(context, ref, [current]);
              }
            },
            style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
            icon: const Icon(Icons.add_rounded),
            label: Text(l10n.characterLibrary_addToPanel),
          ),
        ),
      ),
    );
  }
}

class _Identity extends StatelessWidget {
  const _Identity({
    required this.entry,
    required this.name,
    required this.onName,
    required this.onGender,
  });

  final CharacterLibraryEntry entry;
  final TextEditingController name;
  final ValueChanged<String> onName;
  final ValueChanged<CharacterGender> onGender;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = context.l10n;
    final genders = [
      (CharacterGender.female, l10n.characterEditor_genderFemale),
      (CharacterGender.male, l10n.characterEditor_genderMale),
      (CharacterGender.other, l10n.characterEditor_genderOther),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            CharacterMarkerDisc(
              colors: CharacterMarkerPalette.forGender(entry.gender),
              diameter: 48,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                key: const ValueKey('character_library_editor_name'),
                controller: name,
                onChanged: onName,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
                decoration: InputDecoration(
                  labelText: l10n.characterLibrary_nameLabel,
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      theme.appTheme.controlRadius,
                    ),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final (gender, label) in genders) ...[
              Expanded(
                child: Material(
                  color: entry.gender == gender
                      ? colors.primaryContainer.withValues(alpha: 0.6)
                      : controlSurfaceColor(colors),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      theme.appTheme.controlRadius,
                    ),
                    side: entry.gender == gender
                        ? BorderSide(color: colors.primary, width: 2)
                        : BorderSide.none,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    key: ValueKey('character_library_gender_${gender.name}'),
                    onTap: () => onGender(gender),
                    child: SizedBox(
                      height: 44,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CharacterMarkerDisc(
                            colors: CharacterMarkerPalette.forGender(gender),
                            diameter: 22,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelLarge,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (gender != CharacterGender.other) const SizedBox(width: 6),
            ],
          ],
        ),
      ],
    );
  }
}

class _Category extends StatelessWidget {
  const _Category({
    required this.controller,
    required this.categories,
    required this.onChanged,
  });

  final TextEditingController controller;
  final List<String> categories;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey('character_library_editor_category'),
          controller: controller,
          onChanged: onChanged,
          decoration: InputDecoration(
            labelText: l10n.characterLibrary_categoryLabel,
            hintText: l10n.characterLibrary_categoryHint,
            filled: true,
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(theme.appTheme.controlRadius),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        if (categories.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final category in categories)
                ActionChip(
                  label: Text(category),
                  onPressed: () {
                    controller.text = category;
                    onChanged(category);
                  },
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _SideTabs extends StatelessWidget {
  const _SideTabs({
    required this.negative,
    required this.positiveCount,
    required this.negativeCount,
    required this.onChanged,
  });

  final bool negative;
  final int positiveCount;
  final int negativeCount;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Wrap(
      spacing: 8,
      children: [
        ChoiceChip(
          key: const ValueKey('character_library_editor_positive'),
          label: Text('${l10n.characterEditor_positiveTab} $positiveCount'),
          selected: !negative,
          showCheckmark: false,
          onSelected: (_) => onChanged(false),
        ),
        ChoiceChip(
          key: const ValueKey('character_library_editor_negative'),
          label: Text('${l10n.characterEditor_negativeTab} $negativeCount'),
          selected: negative,
          showCheckmark: false,
          onSelected: (_) => onChanged(true),
        ),
      ],
    );
  }
}
