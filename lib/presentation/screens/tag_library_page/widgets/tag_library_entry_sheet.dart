import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../../data/models/tag_library/tag_library_entry.dart';
import '../../../adaptive/adaptive_presenter.dart';
import '../../../adaptive/content_sized_adaptive_form.dart';
import '../../../providers/fixed_tags_provider.dart';
import '../../../providers/tag_library_page_provider.dart';
import '../../../themes/core/layered_surface_style.dart';
import '../../../utils/last_used_label.dart';
import '../../../widgets/common/translated_tag_text.dart';
import '../../../widgets/tag_library/library_group_style.dart';
import '../tag_library_sections.dart';
import 'entry_avatar.dart';

/// What the entry details can do; the page supplies them.
@immutable
class TagLibraryEntryCommands {
  const TagLibraryEntryCommands({
    required this.sendToPrompt,
    required this.showSendTargets,
    required this.toggleFavorite,
    required this.edit,
    required this.copy,
    required this.moveToGroup,
    required this.pickPreview,
    required this.removePreview,
    required this.delete,
  });

  /// Adds the entry after the current positive prompt.
  final ValueChanged<TagLibraryEntry> sendToPrompt;

  /// The other targets: characters, smart split, fixed tags.
  final ValueChanged<TagLibraryEntry> showSendTargets;
  final ValueChanged<TagLibraryEntry> toggleFavorite;
  final ValueChanged<TagLibraryEntry> edit;
  final ValueChanged<TagLibraryEntry> copy;
  final ValueChanged<TagLibraryEntry> moveToGroup;
  final ValueChanged<TagLibraryEntry> pickPreview;
  final ValueChanged<TagLibraryEntry> removePreview;
  final ValueChanged<TagLibraryEntry> delete;
}

enum _MoreAction { copy, move, pickPreview, removePreview, delete }

/// Shows one entry: its preview or group icon, group path, content, how it
/// has been used, and the ways to use and change it.
Future<void> showTagLibraryEntrySheet({
  required BuildContext context,
  required TagLibraryEntry entry,
  required TagLibraryEntryCommands commands,
}) {
  return AdaptivePresenter.showForm<void>(
    context: context,
    titleBuilder: (context) => _EntryTitle(entryId: entry.id),
    dialogWidth: 460,
    builder: (_, scrollController) => TagLibraryEntryBody(
      entryId: entry.id,
      commands: commands,
      scrollController: scrollController,
    ),
  );
}

class _EntryTitle extends ConsumerWidget {
  const _EntryTitle({required this.entryId});

  final String entryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(tagLibraryPageNotifierProvider);
    final entry = state.entries.where((e) => e.id == entryId).firstOrNull;
    if (entry == null) return const SizedBox.shrink();
    final tree = TagLibraryGroupTree(state.categories);
    final path = tree.pathOf(entry.categoryId);
    final style = LibraryGroupStyle.of(entry.categoryId, state.categories);
    return Row(
      children: [
        EntryAvatar(entry: entry, style: style, size: 56),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                entry.displayName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(
                    style.icon,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      path.isEmpty
                          ? context.l10n.tagLibrary_uncategorized
                          : path.join(' › '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class TagLibraryEntryBody extends ConsumerWidget {
  const TagLibraryEntryBody({
    super.key,
    required this.entryId,
    required this.commands,
    this.scrollController,
  });

  final String entryId;
  final TagLibraryEntryCommands commands;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(tagLibraryPageNotifierProvider);
    final entry = state.entries.where((e) => e.id == entryId).firstOrNull;
    if (entry == null) return const SizedBox.shrink();
    final isFixed = ref.watch(
      fixedTagsNotifierProvider.select(
        (fixed) => fixed.entries.any((tag) => tag.sourceEntryId == entryId),
      ),
    );

    // Actions that open another surface close the details first, so sheets
    // never stack on a phone.
    void closeThen(ValueChanged<TagLibraryEntry> action) {
      Navigator.of(context).pop();
      action(entry);
    }

    return ContentSizedAdaptiveForm(
      key: const ValueKey('tag-library-entry-sheet'),
      scrollController: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      content: [
        _ContentBox(entry: entry),
        const SizedBox(height: 12),
        _UsageLine(entry: entry, isFixed: isFixed),
      ],
      footer: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 8, 12, 16),
        child: Row(
          children: [
            Expanded(
              child: _SendSplitButton(
                onSend: () => closeThen(commands.sendToPrompt),
                onMore: () => closeThen(commands.showSendTargets),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              key: const ValueKey('tag-library-entry-favorite'),
              tooltip: entry.isFavorite
                  ? context.l10n.common_unfavorite
                  : context.l10n.common_favorite,
              isSelected: entry.isFavorite,
              onPressed: () => commands.toggleFavorite(entry),
              icon: const Icon(Icons.favorite_border_rounded),
              selectedIcon: Icon(
                Icons.favorite_rounded,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
            IconButton(
              key: const ValueKey('tag-library-entry-edit'),
              tooltip: context.l10n.common_edit,
              onPressed: () => closeThen(commands.edit),
              icon: const Icon(Icons.edit_outlined),
            ),
            _MoreButton(
              entry: entry,
              onSelected: (action) => switch (action) {
                _MoreAction.copy => commands.copy(entry),
                _MoreAction.move => closeThen(commands.moveToGroup),
                _MoreAction.pickPreview => closeThen(commands.pickPreview),
                _MoreAction.removePreview => commands.removePreview(entry),
                _MoreAction.delete => closeThen(commands.delete),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ContentBox extends StatelessWidget {
  const _ContentBox({required this.entry});

  final TagLibraryEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      key: const ValueKey('tag-library-entry-content'),
      decoration: BoxDecoration(
        color: sectionSurfaceColor(theme.colorScheme),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          width: double.infinity,
          child: entry.content.trim().isEmpty
              ? Text(
                  context.l10n.common_emptyValue,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                )
              : TranslatedPromptText(
                  entry.content,
                  originalText: entry.content.replaceAll('\n', ' '),
                  selectable: false,
                  maxLines: 12,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
                ),
        ),
      ),
    );
  }
}

class _UsageLine extends StatelessWidget {
  const _UsageLine({required this.entry, required this.isFixed});

  final TagLibraryEntry entry;
  final bool isFixed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    final style = theme.textTheme.bodySmall?.copyWith(color: color);
    final lastUsed = entry.lastUsedAt;
    Widget item(IconData icon, String text, {Key? key, Color? tint}) => Row(
      key: key,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: tint ?? color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            style: tint == null ? style : style?.copyWith(color: tint),
          ),
        ),
      ],
    );
    return Wrap(
      key: const ValueKey('tag-library-entry-usage'),
      spacing: 14,
      runSpacing: 6,
      children: [
        item(
          Icons.bar_chart_rounded,
          entry.useCount > 0
              ? context.l10n.tagLibrary_usedTimes(entry.useCount)
              : context.l10n.tagLibrary_neverUsed,
        ),
        if (lastUsed != null)
          item(Icons.schedule_rounded, lastUsedLabel(context, lastUsed)),
        if (isFixed)
          item(
            Icons.push_pin_rounded,
            context.l10n.tagLibrary_isFixedTag,
            key: const ValueKey('tag-library-entry-is-fixed'),
            tint: theme.colorScheme.primary,
          ),
      ],
    );
  }
}

/// 发送到提示词, with a chevron on the end for the other targets.
class _SendSplitButton extends StatelessWidget {
  const _SendSplitButton({required this.onSend, required this.onMore});

  final VoidCallback onSend;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final radius = BorderRadius.circular(14);
    return Material(
      color: colors.primary,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  key: const ValueKey('tag-library-entry-send'),
                  onTap: onSend,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.send_rounded,
                          size: 18,
                          color: colors.onPrimary,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            context.l10n.tagLibrary_sendToPrompt,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: colors.onPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              VerticalDivider(
                width: 1,
                thickness: 1,
                indent: 10,
                endIndent: 10,
                color: colors.onPrimary.withValues(alpha: 0.3),
              ),
              Tooltip(
                message: context.l10n.tagLibrary_moreTargets,
                child: InkWell(
                  key: const ValueKey('tag-library-entry-send-more'),
                  onTap: onMore,
                  child: SizedBox(
                    width: 48,
                    child: Icon(
                      Icons.expand_more_rounded,
                      color: colors.onPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoreButton extends StatelessWidget {
  const _MoreButton({required this.entry, required this.onSelected});

  final TagLibraryEntry entry;
  final ValueChanged<_MoreAction> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final error = Theme.of(context).colorScheme.error;
    PopupMenuItem<_MoreAction> item(
      _MoreAction value,
      IconData icon,
      String label, {
      Color? color,
    }) => PopupMenuItem(
      key: ValueKey('tag-library-entry-more-${value.name}'),
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: TextStyle(color: color)),
          ),
        ],
      ),
    );
    return PopupMenuButton<_MoreAction>(
      key: const ValueKey('tag-library-entry-more'),
      tooltip: MaterialLocalizations.of(context).moreButtonTooltip,
      onSelected: onSelected,
      itemBuilder: (_) => [
        item(
          _MoreAction.copy,
          Icons.content_copy_rounded,
          l10n.tagLibrary_copyContent,
        ),
        item(
          _MoreAction.move,
          Icons.drive_file_move_outline,
          l10n.tagLibrary_moveToCategoryTitle,
        ),
        item(
          _MoreAction.pickPreview,
          Icons.image_outlined,
          entry.hasThumbnail
              ? l10n.tagLibrary_replacePreview
              : l10n.tagLibrary_setPreview,
        ),
        if (entry.hasThumbnail)
          item(
            _MoreAction.removePreview,
            Icons.hide_image_outlined,
            l10n.tagLibrary_removePreview,
          ),
        const PopupMenuDivider(),
        item(
          _MoreAction.delete,
          Icons.delete_outline_rounded,
          l10n.common_delete,
          color: error,
        ),
      ],
    );
  }
}
