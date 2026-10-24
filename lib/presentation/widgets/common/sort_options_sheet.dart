import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../adaptive/adaptive_presenter.dart';
import '../../adaptive/content_sized_adaptive_form.dart';
import 'themed_radio.dart';
import 'themed_switch.dart';

/// One way to sort, with a line saying what it does.
@immutable
class SortOption<T> {
  const SortOption({
    required this.value,
    required this.title,
    required this.subtitle,
  });

  final T value;
  final String title;
  final String subtitle;
}

/// A switch shown under the sort options, such as "favorites first".
@immutable
class SortToggle {
  const SortToggle({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.key,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;
  final Key? key;
}

/// What a sort sheet shows: the choices, the current one and an optional
/// switch below them.
@immutable
class SortOptionsSpec<T> {
  const SortOptionsSpec({
    required this.options,
    required this.selected,
    required this.onSelected,
    this.toggle,
  });

  final List<SortOption<T>> options;
  final T selected;
  final ValueChanged<T> onSelected;
  final SortToggle? toggle;
}

/// Shows the sort choices; picking one applies it and closes the sheet, the
/// toggle applies at once and leaves it open. [specOf] watches whatever it
/// reads, so the sheet follows changes while it is open.
Future<void> showSortOptionsSheet<T>({
  required BuildContext context,
  required String title,
  required SortOptionsSpec<T> Function(WidgetRef ref) specOf,
}) {
  return AdaptivePresenter.showForm<void>(
    context: context,
    title: title,
    dialogWidth: 420,
    builder: (sheetContext, scrollController) => Consumer(
      builder: (context, ref, _) {
        final spec = specOf(ref);
        return _SortOptionsBody<T>(
          scrollController: scrollController,
          options: spec.options,
          selected: spec.selected,
          onSelected: (value) {
            spec.onSelected(value);
            Navigator.of(context).pop();
          },
          toggle: spec.toggle,
        );
      },
    ),
  );
}

class _SortOptionsBody<T> extends StatelessWidget {
  const _SortOptionsBody({
    required this.scrollController,
    required this.options,
    required this.selected,
    required this.onSelected,
    required this.toggle,
  });

  final ScrollController? scrollController;
  final List<SortOption<T>> options;
  final T selected;
  final ValueChanged<T> onSelected;
  final SortToggle? toggle;

  @override
  Widget build(BuildContext context) {
    final toggle = this.toggle;
    return ContentSizedAdaptiveForm(
      key: const ValueKey('sort-options-sheet'),
      scrollController: scrollController,
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
      content: [
        for (final option in options)
          _SortOptionTile<T>(
            option: option,
            selected: option.value == selected,
            onTap: () => onSelected(option.value),
          ),
        if (toggle != null) ...[
          const Divider(height: 17, indent: 16, endIndent: 16),
          _SortToggleTile(toggle: toggle),
        ],
      ],
    );
  }
}

class _SortOptionTile<T> extends StatelessWidget {
  const _SortOptionTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final SortOption<T> option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: InkWell(
        key: ValueKey('sort-option-${option.value}'),
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                ExcludeSemantics(
                  child: ThemedRadio<bool>(
                    value: true,
                    groupValue: selected,
                    onChanged: (_) => onTap(),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        option.title,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        option.subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SortToggleTile extends StatelessWidget {
  const _SortToggleTile({required this.toggle});

  final SortToggle toggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = toggle.enabled;
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.38);
    return MergeSemantics(
      child: InkWell(
        key: toggle.key,
        borderRadius: BorderRadius.circular(12),
        onTap: enabled ? () => toggle.onChanged(!toggle.value) : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        toggle.title,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: enabled ? null : muted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        toggle.subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: enabled
                              ? theme.colorScheme.onSurfaceVariant
                              : muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                ThemedSwitch(
                  value: toggle.value,
                  enabled: enabled,
                  onChanged: enabled ? toggle.onChanged : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
