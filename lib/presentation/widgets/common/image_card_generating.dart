import 'package:flutter/material.dart';

import 'generation_dot_field.dart';
import 'generation_visual_transition.dart';
import 'image_card_models.dart';
import 'image_card_stream_preview.dart';
import 'image_postprocess_indicator.dart';

class ImageCardGenerating extends StatelessWidget {
  const ImageCardGenerating({super.key, required this.data});

  final ImageCardViewData data;

  @override
  Widget build(BuildContext context) {
    final hasPreview =
        data.showStreamPreview && data.streamPreview?.isNotEmpty == true;
    final phase = data.postprocessPhase;
    final Widget content;
    if (hasPreview) {
      content = Stack(
        fit: StackFit.expand,
        children: [
          ImageCardStreamPreview(
            previewBytes: data.streamPreview!,
            placement: data.focusedPreviewPlacement,
          ),
          if (phase != null) ImagePostprocessIndicator(phase: phase),
        ],
      );
    } else {
      content = Stack(
        fit: StackFit.expand,
        children: [
          const GenerationDotField(),
          if (phase != null) ImagePostprocessIndicator(phase: phase),
        ],
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLowest,
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: GenerationVisualTransition(
          stage: hasPreview ? 'preview' : 'dots',
          child: content,
        ),
      ),
    );
  }
}
