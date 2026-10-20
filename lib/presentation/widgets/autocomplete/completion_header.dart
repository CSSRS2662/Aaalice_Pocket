import 'package:flutter/material.dart';

import '../../../core/utils/localization_extension.dart';
import '../../adaptive/interaction_policy.dart';
import 'completion_category_filter.dart';
import 'completion_popup_buttons.dart';
import 'completion_tile_layout.dart';

/// The popup header: category buttons that narrow the list at the start,
/// then the result count, keyboard hints where there is room, and the
/// popup actions. The field already shows what is being completed, so the
/// header does not repeat it. When the footer does not fit, its settings
/// button, 分词 key and multi-select actions move here.
class CompletionHeader extends StatelessWidget {
  const CompletionHeader({
    super.key,
    required this.resultCount,
    required this.related,
    required this.isRelatedPinned,
    required this.onToggleRelatedPin,
    required this.onOpenSettings,
    required this.onClose,
    this.onInsertSeparator,
    this.filter,
    this.pickActions,
  });

  final int resultCount;
  final bool related;
  final bool isRelatedPinned;
  final VoidCallback? onToggleRelatedPin;
  final CompletionCategoryFilter? filter;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onInsertSeparator;
  final VoidCallback onClose;

  /// The multi-select actions, while that mode is on and the footer is
  /// hidden.
  final Widget? pickActions;

  /// Room the multi-select actions take from the count and the hints.
  static const double _pickActionsReserve = 150;

  /// Height of the header for the current input and text scale.
  static double extentOf(BuildContext context) {
    // The action buttons with the vertical padding and the bottom border.
    final minimum =
        CompletionPopupIconButton.extentOf(context) +
        _verticalPadding(context) * 2 +
        1;
    final scaled = MediaQuery.textScalerOf(context).scale(14) * 1.35 + 14;
    return scaled > minimum ? scaled : minimum;
  }

  static double _verticalPadding(BuildContext context) =>
      context.interactionPolicy.touchAvailable ? 2 : 4;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final touchInput = context.interactionPolicy.touchAvailable;
    return Container(
      key: const ValueKey('autocomplete-popup-header'),
      height: extentOf(context),
      padding: EdgeInsets.symmetric(
        horizontal: 4,
        vertical: _verticalPadding(context),
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final touchCompact = touchInput && constraints.maxWidth < 600;
          final buttonExtent = CompletionPopupIconButton.extentOf(context);
          final buttons = [
            onOpenSettings != null,
            related && onToggleRelatedPin != null,
            true,
          ].where((shown) => shown).length;
          final categories = filter == null
              ? 0.0
              : CompletionCategoryBar.widthFor(
                  context,
                  filter!.categories.length,
                );
          final reserved =
              buttons * buttonExtent +
              categories +
              (onInsertSeparator == null ? 0 : buttonExtent) +
              (pickActions == null ? 0 : _pickActionsReserve);
          final showCount = constraints.maxWidth - reserved >= 36;
          final showFullShortcuts =
              !touchCompact && constraints.maxWidth - reserved >= 280;
          final showCompactShortcuts =
              !touchCompact && constraints.maxWidth - reserved >= 160;
          return Row(
            children: [
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: filter == null
                      ? const SizedBox.shrink()
                      // Very narrow or enlarged: the buttons scroll sideways
                      // rather than squeezing the actions out.
                      : SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: CompletionCategoryBar(filter: filter!),
                        ),
                ),
              ),
              if (pickActions case final picks?) ...[
                // Shares the row with the category buttons; narrows only
                // when enlarged text leaves no room.
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: SizedBox(
                        height: constraints.maxHeight,
                        child: picks,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              if (showCount) ...[
                Semantics(
                  label: context.l10n.autocomplete_resultsCount(resultCount),
                  excludeSemantics: true,
                  child: Text(
                    '$resultCount',
                    key: const ValueKey('autocomplete-popup-result-count'),
                    maxLines: 1,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontFamily: completionTileFontFamily,
                      color: theme.colorScheme.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              if (showFullShortcuts)
                const _KeyboardHints()
              else if (showCompactShortcuts)
                const _KeyboardHints(compact: true),
              if (onOpenSettings != null)
                CompletionPopupIconButton(
                  key: const ValueKey('autocomplete-popup-settings'),
                  tooltip: context.l10n.autocomplete_openSettings,
                  icon: Icons.settings_rounded,
                  onPressed: onOpenSettings!,
                ),
              if (onInsertSeparator case final split?)
                CompletionSplitButton(onPressed: split),
              if (related && onToggleRelatedPin != null)
                CompletionPopupIconButton(
                  key: const ValueKey('autocomplete-popup-related-pin'),
                  tooltip: isRelatedPinned
                      ? context.l10n.autocomplete_relatedUnpin
                      : context.l10n.autocomplete_relatedPin,
                  icon: isRelatedPinned
                      ? Icons.push_pin_rounded
                      : Icons.push_pin_outlined,
                  active: isRelatedPinned,
                  onPressed: onToggleRelatedPin!,
                ),
              CompletionPopupIconButton(
                key: const ValueKey('autocomplete-popup-close'),
                tooltip: context.l10n.autocomplete_actionClose,
                icon: Icons.close_rounded,
                onPressed: onClose,
              ),
            ],
          );
        },
      ),
    );
  }

  static String shortcutDescription(BuildContext context) =>
      '↑↓ ${context.l10n.autocomplete_actionSelect} · '
      'Enter/Tab ${context.l10n.autocomplete_actionConfirm} · '
      'Esc ${context.l10n.autocomplete_actionClose}';
}

class _KeyboardHints extends StatelessWidget {
  const _KeyboardHints({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mutedStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontSize: 10.5,
    );
    final keyStyle = mutedStyle?.copyWith(
      color: theme.colorScheme.onSurface,
      fontWeight: FontWeight.w600,
    );
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: compact
          ? [
              Text('↑↓', style: keyStyle),
              Text(' · ', style: mutedStyle),
              Text('Enter/Tab', style: keyStyle),
              Text(' · ', style: mutedStyle),
              Text('Esc', style: keyStyle),
            ]
          : [
              Text('↑↓', style: keyStyle),
              const SizedBox(width: 3),
              Text(context.l10n.autocomplete_actionSelect, style: mutedStyle),
              Text(' · ', style: mutedStyle),
              Text('Enter/Tab', style: keyStyle),
              const SizedBox(width: 3),
              Text(context.l10n.autocomplete_actionConfirm, style: mutedStyle),
              Text(' · ', style: mutedStyle),
              Text('Esc', style: keyStyle),
              const SizedBox(width: 3),
              Text(context.l10n.autocomplete_actionClose, style: mutedStyle),
            ],
    );
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: Tooltip(
        message: CompletionHeader.shortcutDescription(context),
        child: ClipRect(
          child: SizedBox(
            width: compact ? 105 : 218,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}
