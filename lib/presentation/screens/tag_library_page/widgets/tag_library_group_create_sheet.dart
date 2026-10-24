import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../../data/models/tag_library/tag_library_category.dart';
import '../../../adaptive/adaptive_presenter.dart';
import '../../../adaptive/content_sized_adaptive_form.dart';
import '../../../providers/tag_library_page_provider.dart';
import '../../../themes/core/layered_surface_style.dart';
import '../../../widgets/common/app_toast.dart';
import '../../../widgets/tag_library/library_group_style.dart';

/// Creates groups: tap presets, which come with designed icons, or type a
/// custom name, which gets the generic icon. Presets already in the library
/// are checked off. New groups go under [parentId], or to the top level.
Future<void> showTagLibraryGroupCreateSheet({
  required BuildContext context,
  String? parentId,
}) {
  return AdaptivePresenter.showForm<void>(
    context: context,
    title: context.l10n.tagLibrary_newCategory,
    dialogWidth: 480,
    builder: (_, scrollController) => _GroupCreateBody(
      scrollController: scrollController,
      parentId: parentId,
    ),
  );
}

class _GroupCreateBody extends ConsumerStatefulWidget {
  const _GroupCreateBody({
    required this.scrollController,
    required this.parentId,
  });

  final ScrollController scrollController;
  final String? parentId;

  @override
  ConsumerState<_GroupCreateBody> createState() => _GroupCreateBodyState();
}

class _GroupCreateBodyState extends ConsumerState<_GroupCreateBody> {
  final TextEditingController _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<bool> _create(String name) async {
    final created = await ref
        .read(tagLibraryPageNotifierProvider.notifier)
        .addCategory(name: name, parentId: widget.parentId);
    if (!mounted) return created != null;
    if (created == null) {
      AppToast.error(context, context.l10n.tagLibrary_categoryNameExists);
      return false;
    }
    AppToast.success(context, context.l10n.tagLibrary_groupCreated(name));
    return true;
  }

  Future<void> _createCustom() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    if (await _create(name)) _name.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final categories = ref.watch(
      tagLibraryPageNotifierProvider.select((state) => state.categories),
    );
    final taken = takenGroupPresets(categories);
    return ContentSizedAdaptiveForm(
      key: const ValueKey('tag-library-group-create'),
      scrollController: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      content: [
        Text(
          l10n.tagLibrary_newGroupHint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        _SectionLabel(l10n.tagLibrary_presetGroups),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
            final columns =
                (constraints.maxWidth / (76 * textScale.clamp(1.0, 2.0)))
                    .floor()
                    .clamp(2, 6);
            final width = constraints.maxWidth / columns;
            return Wrap(
              children: [
                for (final preset in LibraryGroupPreset.values)
                  SizedBox(
                    width: width,
                    child: _PresetTile(
                      preset: preset,
                      label: preset.label(l10n),
                      taken: taken.contains(preset),
                      onTap: () => _create(preset.label(l10n)),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        _SectionLabel(l10n.tagLibrary_customGroup),
        const SizedBox(height: 8),
        Row(
          children: [
            const LibraryGroupIcon(style: LibraryGroupStyle.generic, size: 48),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                key: const ValueKey('tag-library-custom-group-name'),
                controller: _name,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _createCustom(),
                decoration: InputDecoration(
                  hintText: l10n.tagLibrary_customGroupHint,
                  filled: true,
                  fillColor: controlSurfaceColor(theme.colorScheme),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _name,
              builder: (context, value, _) => IconButton.filled(
                key: const ValueKey('tag-library-custom-group-create'),
                tooltip: l10n.common_create,
                onPressed: value.text.trim().isEmpty ? null : _createCustom,
                style: IconButton.styleFrom(minimumSize: const Size.square(48)),
                icon: const Icon(Icons.check_rounded),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.labelLarge?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _PresetTile extends StatelessWidget {
  const _PresetTile({
    required this.preset,
    required this.label,
    required this.taken,
    required this.onTap,
  });

  final LibraryGroupPreset preset;
  final String label;

  /// Already a group, so it shows a check and cannot be added twice.
  final bool taken;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Semantics(
      button: !taken,
      selected: taken,
      child: InkWell(
        key: ValueKey('tag-library-preset-${preset.name}'),
        borderRadius: BorderRadius.circular(14),
        onTap: taken ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Opacity(
                    opacity: taken ? 0.5 : 1,
                    child: LibraryGroupIcon(
                      style: LibraryGroupStyle.ofPreset(preset),
                      size: 48,
                    ),
                  ),
                  if (taken)
                    PositionedDirectional(
                      top: -4,
                      end: -4,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: colors.surface, width: 2),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: Icon(
                            Icons.check_rounded,
                            size: 12,
                            color: colors.onPrimary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: taken ? colors.onSurfaceVariant : colors.onSurface,
                  fontWeight: taken ? FontWeight.w500 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The presets the library already has a group for, under any name that
/// matches them.
Set<LibraryGroupPreset> takenGroupPresets(
  List<TagLibraryCategory> categories,
) => {
  for (final category in categories)
    if (LibraryGroupPreset.match(category.name) case final preset?) preset,
};
