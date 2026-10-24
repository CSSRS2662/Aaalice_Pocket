import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/localization_extension.dart';
import '../../../data/models/fixed_tag/fixed_tag_entry.dart';
import '../../../data/models/fixed_tag/fixed_tag_prompt_type.dart';
import '../../../data/models/tag_library/tag_library_category.dart';
import '../../adaptive/adaptive_presenter.dart';
import '../../adaptive/content_sized_adaptive_form.dart';
import '../../adaptive/interaction_policy.dart';
import '../../providers/fixed_tag_usage_provider.dart';
import '../../providers/fixed_tags_provider.dart';
import '../../providers/tag_library_page_provider.dart';
import '../../themes/core/layered_surface_style.dart';
import '../../utils/last_used_label.dart';
import '../common/app_toast.dart';
import '../common/horizontal_segmented_control.dart';
import '../common/translated_tag_text.dart';
import '../tag_library/library_group_style.dart';
import 'fixed_tags_dialog_models.dart';

/// Weight limits and step, matching the edit dialog's slider.
const _minWeight = 0.5;
const _maxWeight = 2.0;
const _weightStep = 0.05;

/// Shows everything about one fixed tag except the on/off state, which the
/// grid toggles directly.
Future<void> showFixedTagDetails({
  required BuildContext context,
  required FixedTagEntry entry,
  required FixedTagsDialogCommands commands,
}) {
  return AdaptivePresenter.showForm<void>(
    context: context,
    titleBuilder: (context) => _DetailsTitle(entry: entry),
    dialogWidth: 440,
    builder: (_, scrollController) => FixedTagDetailsBody(
      entryId: entry.id,
      commands: commands,
      scrollController: scrollController,
    ),
  );
}

class _DetailsTitle extends StatelessWidget {
  const _DetailsTitle({required this.entry});

  final FixedTagEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
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
        Text(
          entry.promptType == FixedTagPromptType.positive
              ? context.l10n.fixedTags_positiveTitle
              : context.l10n.fixedTags_negativeTitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class FixedTagDetailsBody extends ConsumerWidget {
  const FixedTagDetailsBody({
    super.key,
    required this.entryId,
    required this.commands,
    this.scrollController,
  });

  final String entryId;
  final FixedTagsDialogCommands commands;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(fixedTagsNotifierProvider);
    final entry = state.entries.where((item) => item.id == entryId).firstOrNull;
    if (entry == null) return const SizedBox.shrink();
    final library = ref.watch(tagLibraryPageNotifierProvider);
    final libraryEntry = entry.sourceEntryId == null
        ? null
        : library.entries
              .where((item) => item.id == entry.sourceEntryId)
              .firstOrNull;
    final usage = ref.watch(
      fixedTagUsageProvider.select((scores) => scores[entry.id]),
    );
    final linked = entry.promptType == FixedTagPromptType.positive
        ? state.linkedNegativesOf(entry.id)
        : state.linkedPositivesOf(entry.id);

    // Actions that open another surface close the details first, so sheets
    // never stack on a phone.
    void closeThen(VoidCallback action) {
      Navigator.of(context).pop();
      action();
    }

    return ContentSizedAdaptiveForm(
      key: const ValueKey('fixed-tag-details'),
      scrollController: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      content: [
        _ContentPreview(entry: entry),
        const SizedBox(height: 12),
        _GroupRow(
          categoryId: libraryEntry?.categoryId ?? entry.categoryId,
          categories: library.categories,
          followsLibrary: libraryEntry != null,
          onPressed: () => closeThen(() => commands.moveToCategory(entry)),
        ),
        _WeightRow(
          weight: entry.weight,
          onChanged: (weight) => commands.setWeight(entry, weight),
        ),
        _PositionRow(
          entry: entry,
          onChanged: () => commands.togglePosition(entry),
        ),
        const SizedBox(height: 8),
        _LinksRow(
          linked: linked,
          onPressed: () => closeThen(() => commands.showLinkManager(entry)),
        ),
        const SizedBox(height: 14),
        _NoteLine(
          key: const ValueKey('fixed-tag-details-usage'),
          icon: Icons.bar_chart_rounded,
          text: usage == null || usage.lastUsedAt == null
              ? context.l10n.fixedTags_usageNever
              : context.l10n.fixedTags_usageSummary(
                  usage.count,
                  lastUsedLabel(context, usage.lastUsedAt!),
                ),
        ),
        if (libraryEntry != null) ...[
          const SizedBox(height: 6),
          _NoteLine(
            key: const ValueKey('fixed-tag-details-library'),
            icon: Icons.sync_rounded,
            text: context.l10n.fixedTags_fromLibraryNote(
              libraryEntry.displayName,
            ),
          ),
        ],
      ],
      footer: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton.icon(
                key: const ValueKey('fixed-tag-details-delete'),
                onPressed: () => closeThen(() => commands.deleteEntry(entry)),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: Text(context.l10n.common_delete),
              ),
              TextButton.icon(
                key: const ValueKey('fixed-tag-details-copy'),
                // Secondary action: neutral, so only delete reads as a risk.
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.onSurface,
                ),
                onPressed: entry.content.isEmpty
                    ? null
                    : () async {
                        await Clipboard.setData(
                          ClipboardData(text: entry.content),
                        );
                        if (context.mounted) {
                          AppToast.success(context, context.l10n.common_copied);
                        }
                      },
                icon: const Icon(Icons.content_copy_rounded, size: 18),
                label: Text(context.l10n.common_copy),
              ),
              FilledButton.tonalIcon(
                key: const ValueKey('fixed-tag-details-edit'),
                onPressed: () => closeThen(
                  () => commands.editEntry(entry, entry.promptType),
                ),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text(context.l10n.common_edit),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContentPreview extends StatelessWidget {
  const _ContentPreview({required this.entry});

  final FixedTagEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      key: const ValueKey('fixed-tag-details-content'),
      decoration: BoxDecoration(
        color: sectionSurfaceColor(theme.colorScheme),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          width: double.infinity,
          child: entry.content.isEmpty
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
                  style: theme.textTheme.bodyMedium,
                ),
        ),
      ),
    );
  }
}

/// A labeled row: the label on the start side, the control on the end side,
/// stacked when large text leaves no room for both.
class _SettingRow extends StatelessWidget {
  const _SettingRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelText = Text(
      label,
      style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
    );
    final stacked = MediaQuery.textScalerOf(context).scale(1) >= 2;
    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: context.interactionPolicy.minimumControlExtent + 8,
      ),
      child: stacked
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [labelText, const SizedBox(height: 6), child],
              ),
            )
          : Row(
              children: [
                labelText,
                const SizedBox(width: 16),
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: child,
                  ),
                ),
              ],
            ),
    );
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({
    required this.categoryId,
    required this.categories,
    required this.followsLibrary,
    required this.onPressed,
  });

  final String? categoryId;
  final List<TagLibraryCategory> categories;
  final bool followsLibrary;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final category = categories
        .where((item) => item.id == categoryId)
        .firstOrNull;
    final name = category?.displayName ?? context.l10n.fixedTags_uncategorized;
    return _SettingRow(
      label: context.l10n.fixedTags_group,
      child: InkWell(
        key: const ValueKey('fixed-tag-details-group'),
        borderRadius: BorderRadius.circular(10),
        onTap: onPressed,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: context.interactionPolicy.minimumControlExtent,
          ),
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: 8, end: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                LibraryGroupIcon(
                  style: category == null
                      ? LibraryGroupStyle.generic
                      : LibraryGroupStyle.of(category.id, categories),
                  size: 24,
                  iconSize: 15,
                  radius: 7,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text.rich(
                    TextSpan(
                      text: name,
                      children: [
                        if (followsLibrary)
                          TextSpan(
                            text:
                                ' · ${context.l10n.fixedTags_groupFollowsLibrary}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WeightRow extends StatelessWidget {
  const _WeightRow({required this.weight, required this.onChanged});

  final double weight;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    void step(int direction) {
      final next =
          ((weight + direction * _weightStep) / _weightStep).round() *
          _weightStep;
      onChanged(next.clamp(_minWeight, _maxWeight).toDouble());
    }

    return _SettingRow(
      label: context.l10n.fixedTags_weight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: controlSurfaceColor(theme.colorScheme),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: const ValueKey('fixed-tag-details-weight-down'),
              tooltip: context.l10n.fixedTags_weightDecrease,
              onPressed: weight <= _minWeight + 0.001 ? null : () => step(-1),
              icon: const Icon(Icons.remove_rounded),
            ),
            // Very large text shrinks the number rather than the buttons.
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 44),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    weight.toStringAsFixed(2),
                    key: const ValueKey('fixed-tag-details-weight'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              key: const ValueKey('fixed-tag-details-weight-up'),
              tooltip: context.l10n.fixedTags_weightIncrease,
              onPressed: weight >= _maxWeight - 0.001 ? null : () => step(1),
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _PositionRow extends StatelessWidget {
  const _PositionRow({required this.entry, required this.onChanged});

  final FixedTagEntry entry;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return _SettingRow(
      label: context.l10n.fixedTags_position,
      child: HorizontalSegmentedControl(
        child: SegmentedButton<FixedTagPosition>(
          key: const ValueKey('fixed-tag-details-position'),
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: FixedTagPosition.prefix,
              label: Text(context.l10n.fixedTags_prefix),
            ),
            ButtonSegment(
              value: FixedTagPosition.suffix,
              label: Text(context.l10n.fixedTags_suffix),
            ),
          ],
          selected: {entry.position},
          onSelectionChanged: (selection) {
            if (selection.first != entry.position) onChanged();
          },
        ),
      ),
    );
  }
}

class _LinksRow extends StatelessWidget {
  const _LinksRow({required this.linked, required this.onPressed});

  final List<FixedTagEntry> linked;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: controlSurfaceColor(theme.colorScheme),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: const ValueKey('fixed-tag-details-links'),
        borderRadius: BorderRadius.circular(12),
        onTap: onPressed,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(
                  Icons.link_rounded,
                  size: 20,
                  color: linked.isEmpty
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.colorScheme.secondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        context.l10n.fixedTags_manageLinks,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        linked.isEmpty
                            ? context.l10n.fixedTags_linkCount(0)
                            : context.l10n.fixedTags_linkedToNames(
                                linked
                                    .map((item) => item.displayName)
                                    .join(', '),
                              ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NoteLine extends StatelessWidget {
  const _NoteLine({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 15, color: color),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}
