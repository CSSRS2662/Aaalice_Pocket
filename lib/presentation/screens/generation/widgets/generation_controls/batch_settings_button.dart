import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nai_launcher/core/utils/localization_extension.dart';
import 'package:nai_launcher/presentation/adaptive/adaptive_presenter.dart';
import 'package:nai_launcher/presentation/adaptive/interaction_policy.dart';
import 'package:nai_launcher/presentation/providers/image_generation_provider.dart';
import 'package:nai_launcher/presentation/widgets/common/draggable_number_input.dart';

/// 工具栏的批次设置入口。
class BatchSettingsButton extends ConsumerWidget {
  const BatchSettingsButton({
    super.key,
    this.showLabel = false,
    this.compact = false,
  });

  final bool showLabel;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final batchSize = ref.watch(imagesPerRequestProvider);
    final l10n = context.l10n;

    void openSettings() => _showBatchSettingsDialog(context);

    if (showLabel) {
      return FilledButton.tonalIcon(
        onPressed: openSettings,
        icon: const Icon(Icons.burst_mode_rounded),
        label: Text('${l10n.batchSize_title}: $batchSize'),
      );
    }

    final extent = compact
        ? 36.0
        : context.interactionPolicy.minimumControlExtent;
    return IconButton(
      tooltip: l10n.batchSize_tooltip(batchSize),
      style: IconButton.styleFrom(
        tapTargetSize: compact
            ? MaterialTapTargetSize.shrinkWrap
            : MaterialTapTargetSize.padded,
        minimumSize: Size.square(extent),
        maximumSize: Size.square(extent),
        padding: EdgeInsets.zero,
      ),
      icon: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          '$batchSize',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ),
      onPressed: openSettings,
    );
  }

  void _showBatchSettingsDialog(BuildContext context) {
    AdaptivePresenter.showForm<void>(
      context: context,
      titleBuilder: (context) => Text(context.l10n.batchSettings_title),
      dialogWidth: 440,
      builder: (context, scrollController) => ListView(
        controller: scrollController,
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          const BatchGenerationSettings(),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.l10n.common_close),
            ),
          ),
        ],
      ),
    );
  }
}

class BatchGenerationSettings extends ConsumerWidget {
  const BatchGenerationSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final count = ref.watch(
      generationParamsNotifierProvider.select((params) => params.nSamples),
    );
    final size = ref.watch(imagesPerRequestProvider);
    void setCount(int value) => ref
        .read(generationParamsNotifierProvider.notifier)
        .updateNSamples(value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.batchSettings_count, style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconButton(
              tooltip: l10n.common_decrease,
              onPressed: count > 1 ? () => setCount(count - 1) : null,
              icon: const Icon(Icons.remove_rounded),
            ),
            DraggableNumberInput(
              key: const ValueKey('batch-count-input'),
              value: count,
              prefix: '',
              onChanged: setCount,
            ),
            IconButton(
              tooltip: l10n.common_increase,
              onPressed: () => setCount(count + 1),
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(l10n.batchSize_title, style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (var value = 1; value <= 4; value++)
              _BatchSizeOption(
                value: value,
                selected: size == value,
                onPressed: () =>
                    ref.read(imagesPerRequestProvider.notifier).set(value),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(l10n.batchSize_formula(count, size, count * size)),
        if (size > 1) ...[
          const SizedBox(height: 4),
          Text(
            l10n.batchSize_costWarning,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }
}

class _BatchSizeOption extends StatelessWidget {
  const _BatchSizeOption({
    required this.value,
    required this.selected,
    required this.onPressed,
  });

  final int value;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final style = FilledButton.styleFrom(
      minimumSize: const Size(48, 44),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
    final label = Text('$value');
    return Semantics(
      selected: selected,
      child: selected
          ? FilledButton(onPressed: onPressed, style: style, child: label)
          : FilledButton.tonal(
              onPressed: onPressed,
              style: style,
              child: label,
            ),
    );
  }
}
