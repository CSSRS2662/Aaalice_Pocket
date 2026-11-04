import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/utils/localization_extension.dart';
import '../../../../providers/image_generation_provider.dart';

class GenerationActiveLabel extends ConsumerWidget {
  const GenerationActiveLabel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(
      imageGenerationNotifierProvider.select(
        (state) => (
          current: state.currentImage,
          total: state.totalImages,
          progress: state.progress,
          completed: state.currentImages.length,
        ),
      ),
    );
    final total = data.total > 0
        ? data.total
        : data.completed > 0
        ? data.completed
        : 1;
    final current = data.current == 0 && data.progress >= 1
        ? total
        : data.current.clamp(1, total);
    final percent = (data.progress * 100).clamp(0, 100).round();
    final label = '$current/$total $percent%';
    return Semantics(
      label: '${context.l10n.common_cancel} · $label',
      excludeSemantics: true,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.stop_circle_outlined, size: 20),
            const SizedBox(width: 6),
            Text(
              label,
              key: const ValueKey('generation-active-progress'),
              softWrap: false,
            ),
          ],
        ),
      ),
    );
  }
}
