import 'generation_models.dart';

typedef GenerationButtonViewData = ({
  bool isGenerating,
  bool isPreparing,
  int currentImage,
  int totalImages,
});

GenerationButtonViewData selectGenerationButtonViewData(
  ImageGenerationState state,
) => (
  isGenerating: state.isGenerating,
  isPreparing: state.isPreparing,
  currentImage: state.currentImage,
  totalImages: state.totalImages,
);

GenerationPanelImages selectGenerationPanelImages(ImageGenerationState state) =>
    state.panelImages;

List<GeneratedImage> selectDisplayImages(ImageGenerationState state) =>
    state.displayImages;

double selectGenerationProgress(ImageGenerationState state) => state.progress;

/// The retry being sent now, or null when the request is not retrying.
typedef GenerationRetryViewData = ({int attempt, int maxRetries});

GenerationRetryViewData? selectGenerationRetry(ImageGenerationState state) =>
    state.isGenerating && state.retryAttempt > 0
    ? (attempt: state.retryAttempt, maxRetries: state.maxRetries)
    : null;

/// 中央画布当前承载的已完成图像 id，供附件引用使用。
String? selectCurrentCanvasImageId(ImageGenerationState state) {
  for (final image in state.displayImages) {
    if (image.kind == GeneratedImageKind.completed) return image.id;
  }
  return null;
}
