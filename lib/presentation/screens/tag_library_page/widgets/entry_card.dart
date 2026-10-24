import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../../data/models/tag_library/tag_library_entry.dart';
import '../../../adaptive/interaction_policy.dart';
import '../../../selection/card_selection_scope.dart';
import '../../../themes/core/layered_surface_style.dart';
import '../../../widgets/tag_library/library_group_style.dart';
import '../../../widgets/tag_library/tag_library_entry_hover_preview.dart';
import 'entry_avatar.dart';

/// Fixed line heights so card extents do not depend on the CJK fallback
/// font's metrics.
const double entryCardNameLineHeight = 1.3;
const double entryCardSnippetLineHeight = 1.35;

/// One library entry in the two-column list: its preview or group icon, the
/// name with a heart for favorites and a pin for fixed tags, and the first
/// line of its content.
///
/// Tapping opens the entry; long-press starts selecting. In selection mode a
/// tap toggles the entry, which sits on the light theme color inside a
/// theme-colored outline.
class EntryCard extends StatefulWidget {
  const EntryCard({
    super.key,
    required this.entry,
    required this.groupStyle,
    required this.onTap,
    this.isFixedTag = false,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onToggleSelection,
    this.onContextMenu,
  });

  final TagLibraryEntry entry;

  /// The entry's group, for the icon shown without a preview image.
  final LibraryGroupStyle groupStyle;
  final VoidCallback onTap;

  /// Added to the fixed tags, so it is sent with every generation.
  final bool isFixedTag;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback? onToggleSelection;

  /// Right-click with a mouse, at the pointer's global position.
  final ValueChanged<Offset>? onContextMenu;

  /// The height that fits the avatar, a name line and a snippet line.
  static double extentFor(
    BuildContext context, {
    required TextScaler textScaler,
  }) {
    final theme = Theme.of(context);
    final name = textScaler.scale(theme.textTheme.bodyMedium?.fontSize ?? 14);
    final snippet = textScaler.scale(theme.textTheme.bodySmall?.fontSize ?? 12);
    final text =
        name * entryCardNameLineHeight +
        snippet * entryCardSnippetLineHeight +
        24;
    return text < 62 ? 62 : text;
  }

  @override
  State<EntryCard> createState() => _EntryCardState();
}

class _EntryCardState extends State<EntryCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final entry = widget.entry;
    final selected = widget.isSelectionMode && widget.isSelected;
    final base = selected
        ? colors.primaryContainer
        : sectionSurfaceColor(colors);
    final background = _hovering
        ? Color.alphaBlend(colors.onSurface.withValues(alpha: 0.04), base)
        : base;
    final radius = BorderRadius.circular(16);
    final card = Semantics(
      selected: widget.isSelectionMode ? selected : null,
      button: true,
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          key: ValueKey('tag-library-entry-${entry.id}'),
          borderRadius: radius,
          hoverColor: Colors.transparent,
          onHover: context.interactionPolicy.precisePointerAvailable
              ? (value) => setState(() => _hovering = value)
              : null,
          onTap: () {
            if (CardSelectionScope.handleTap(context, entry.id)) return;
            (widget.isSelectionMode ? widget.onToggleSelection : widget.onTap)
                ?.call();
          },
          onLongPress:
              widget.isSelectionMode || widget.onToggleSelection == null
              ? null
              : () {
                  HapticFeedback.mediumImpact();
                  widget.onToggleSelection!();
                },
          onSecondaryTapUp: widget.onContextMenu == null
              ? null
              : (details) => widget.onContextMenu!(details.globalPosition),
          child: Ink(
            decoration: BoxDecoration(
              color: background,
              borderRadius: radius,
              border: Border.all(
                color: selected ? colors.primary : Colors.transparent,
                width: 1.5,
              ),
            ),
            padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 10, 8),
            child: Row(
              children: [
                EntryAvatar(entry: entry, style: widget.groupStyle),
                const SizedBox(width: 10),
                Expanded(
                  child: _EntryText(entry: entry, selected: selected),
                ),
                if (widget.isFixedTag) ...[
                  const SizedBox(width: 4),
                  Tooltip(
                    message: context.l10n.tagLibrary_isFixedTag,
                    child: Icon(
                      Icons.push_pin_rounded,
                      key: ValueKey('tag-library-entry-fixed-${entry.id}'),
                      size: 15,
                      color: colors.primary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    return TagLibraryEntryHoverPreview(
      entry: entry,
      enabled: !widget.isSelectionMode,
      child: card,
    );
  }
}

class _EntryText extends StatelessWidget {
  const _EntryText({required this.entry, required this.selected});

  final TagLibraryEntry entry;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final snippet = entry.content.replaceAll(RegExp(r'\s+'), ' ').trim();
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                entry.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  height: entryCardNameLineHeight,
                  color: selected ? colors.onPrimaryContainer : null,
                ),
              ),
            ),
            if (entry.isFavorite) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.favorite_rounded,
                key: ValueKey('tag-library-entry-favorite-${entry.id}'),
                size: 13,
                color: colors.error.withValues(alpha: 0.8),
              ),
            ],
          ],
        ),
        Text(
          snippet.isEmpty ? context.l10n.common_emptyValue : snippet,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            height: entryCardSnippetLineHeight,
            color: selected
                ? colors.onPrimaryContainer.withValues(alpha: 0.72)
                : colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
