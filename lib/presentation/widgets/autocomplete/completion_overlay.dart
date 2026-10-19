import 'package:flutter/material.dart';

import '../../../core/autocomplete/autocomplete_settings.dart';
import '../../../core/autocomplete/cooccurrence_data_pack_service.dart';
import '../../../core/autocomplete/completion_models.dart';
import '../../../core/autocomplete/zh_dictionary_service.dart';
import '../../../core/utils/localization_extension.dart';
import '../../adaptive/interaction_policy.dart';
import 'completion_candidate_rows.dart';
import 'completion_category_filter.dart';
import 'completion_footer.dart';
import 'completion_header.dart';
import 'completion_tile_layout.dart';

/// Compact completion popup inspired by editor command palettes.
///
/// The header holds the category buttons and the popup actions, the footer
/// reports source health (and is the legend of the source dots), and the
/// middle shows the candidates as wrapped, justified rows of compact tiles
/// in match order.
class CompletionOverlay extends StatelessWidget {
  const CompletionOverlay({
    super.key,
    required this.state,
    required this.selectedIndex,
    required this.maxHeight,
    required this.scrollController,
    required this.settings,
    required this.dictionaryState,
    this.cooccurrenceDataPackState = const CooccurrenceDataPackState(),
    required this.showAliases,
    required this.showTranslations,
    required this.showCategory,
    required this.showCount,
    required this.onSelected,
    required this.onClose,
    required this.onOpenSettings,
    required this.measurer,
    required this.geometry,
    this.tagSections = const {},
    this.onInsertSeparator,
    this.isRelatedPinned = false,
    this.onToggleRelatedPin,
    this.categoryFilter,
  });

  final CompletionState state;
  final int selectedIndex;
  final double maxHeight;
  final ScrollController scrollController;
  final AutocompleteSettings settings;
  final ZhDictionaryState dictionaryState;
  final CooccurrenceDataPackState cooccurrenceDataPackState;
  final bool showAliases;
  final bool showTranslations;
  final bool showCategory;
  final bool showCount;
  final ValueChanged<int> onSelected;
  final VoidCallback onClose;
  final VoidCallback onOpenSettings;

  /// Measures tiles; kept by the field so sizes survive rebuilds.
  final CompletionTileMeasurer measurer;

  /// Receives the row layout, which the field uses for scrolling.
  final CompletionListGeometry geometry;

  /// Sections (1-based) of a grouped prompt that already hold each tag.
  final Map<String, List<int>> tagSections;

  /// Ends the tag being written with a comma; shown when given.
  final VoidCallback? onInsertSeparator;
  final bool isRelatedPinned;
  final VoidCallback? onToggleRelatedPin;

  /// Narrows the list to categories; the header buttons show when given.
  final CompletionCategoryFilter? categoryFilter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final touchInput = context.interactionPolicy.touchAvailable;
    final headerExtent = CompletionHeader.extentOf(context);
    final footerExtent = CompletionFooter.extentOf(context);
    // One row of tiles with the list padding.
    final rowExtent = (touchInput ? 44.0 : 40.0) + 12;
    final showFooter = maxHeight >= headerExtent + rowExtent + footerExtent;
    final scrollHeader = maxHeight < headerExtent + rowExtent;
    final filter = categoryFilter;
    final header = CompletionHeader(
      resultCount: state.candidates.length,
      related: state.query?.relatedTag != null,
      isRelatedPinned: isRelatedPinned,
      onToggleRelatedPin: onToggleRelatedPin,
      filter: filter,
      onOpenSettings: showFooter ? null : onOpenSettings,
      onInsertSeparator: showFooter ? null : onInsertSeparator,
      onClose: onClose,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final touchCompact = touchInput && constraints.maxWidth < 600;
        final popupSurface = Color.alphaBlend(
          theme.colorScheme.onSurface.withValues(alpha: dark ? 0.075 : 0.012),
          theme.colorScheme.surface,
        );
        final radius = BorderRadius.all(
          Radius.circular(touchCompact ? 12 : 10),
        );
        return DecoratedBox(
          key: const ValueKey('autocomplete-popup-surface'),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: touchCompact
                ? Border.all(
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.7,
                    ),
                  )
                : null,
            boxShadow: [
              if (dark)
                BoxShadow(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.1),
                  blurRadius: 5,
                  spreadRadius: -1,
                ),
              BoxShadow(
                color: theme.colorScheme.primary.withValues(
                  alpha: dark ? 0.12 : 0.06,
                ),
                blurRadius: 22,
                spreadRadius: -6,
                offset: const Offset(0, 7),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? 0.68 : 0.2),
                blurRadius: 34,
                spreadRadius: dark ? 3 : 0,
                offset: const Offset(0, 15),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? 0.38 : 0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: radius,
            clipBehavior: Clip.antiAlias,
            child: Material(
              key: const ValueKey('autocomplete-popup-background'),
              color: popupSurface,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!scrollHeader) header,
                    Flexible(
                      child: state.candidates.isEmpty
                          ? SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _EmptyCompletionBody(
                                    state: state,
                                    onClearFilter:
                                        filter != null && filter.active
                                        ? filter.onClear
                                        : null,
                                  ),
                                  if (scrollHeader) header,
                                ],
                              ),
                            )
                          : CompletionCandidateRows(
                              state: state,
                              selectedIndex: selectedIndex,
                              scrollController: scrollController,
                              touchCompact: touchCompact,
                              showAliases: showAliases,
                              showTranslations: showTranslations,
                              showCategory: showCategory,
                              showCount: showCount,
                              showMatchNote: settings.showMatchNotes,
                              tagSections: tagSections,
                              measurer: measurer,
                              geometry: geometry,
                              onSelected: onSelected,
                              // When the keyboard leaves very little room,
                              // candidates stay first; header actions remain
                              // reachable in the same scrollable surface.
                              trailing: [if (scrollHeader) header],
                            ),
                    ),
                    if (showFooter)
                      CompletionFooter(
                        state: state,
                        settings: settings,
                        dictionaryState: dictionaryState,
                        cooccurrenceDataPackState: cooccurrenceDataPackState,
                        onOpenSettings: onOpenSettings,
                        onInsertSeparator: onInsertSeparator,
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EmptyCompletionBody extends StatelessWidget {
  const _EmptyCompletionBody({required this.state, this.onClearFilter});

  final CompletionState state;

  /// Clears the categories the list is narrowed to; given while some are
  /// chosen, so an empty list says why and offers the way out.
  final VoidCallback? onClearFilter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loading = state.isLocalLoading || state.isRemoteLoading;
    final related = state.query?.relatedTag != null;
    final error = state.localError ?? state.remoteError;
    final clearFilter = loading || error != null ? null : onClearFilter;
    final message = _message(context, theme, loading, related, error);
    if (clearFilter == null) {
      return SizedBox(
        key: const ValueKey('autocomplete-popup-empty'),
        height: 78,
        child: Center(child: message),
      );
    }
    return Padding(
      key: const ValueKey('autocomplete-popup-empty'),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          message,
          const SizedBox(height: 8),
          Focus(
            canRequestFocus: false,
            descendantsAreFocusable: false,
            child: FilledButton.tonal(
              key: const ValueKey('autocomplete-related-filter-clear'),
              onPressed: clearFilter,
              child: Text(context.l10n.autocomplete_relatedFilterClear),
            ),
          ),
        ],
      ),
    );
  }

  Widget _message(
    BuildContext context,
    ThemeData theme,
    bool loading,
    bool related,
    String? error,
  ) {
    final l10n = context.l10n;
    final filtered = onClearFilter != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading)
            SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(
                value: MediaQuery.disableAnimationsOf(context) ? 0.75 : null,
                strokeWidth: 1.8,
                color: theme.colorScheme.primary,
              ),
            )
          else
            Icon(
              error != null
                  ? Icons.error_outline_rounded
                  : filtered
                  ? Icons.filter_alt_off_outlined
                  : Icons.manage_search_rounded,
              size: 18,
              color: error == null
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.error,
            ),
          const SizedBox(width: 9),
          Flexible(
            child: Tooltip(
              message: error ?? '',
              child: Text(
                loading
                    ? related
                          ? l10n.autocomplete_relatedLoading
                          : l10n.autocomplete_loading
                    : error != null
                    ? l10n.autocomplete_statusError
                    : filtered
                    ? related
                          ? l10n.autocomplete_relatedFilterEmpty
                          : l10n.autocomplete_filterEmpty
                    : related
                    ? l10n.autocomplete_relatedEmpty
                    : l10n.autocomplete_empty,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: error == null
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.colorScheme.error,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
