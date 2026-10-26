import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/constants/api_constants.dart';
import 'package:nai_launcher/data/models/image/image_params.dart';
import 'package:nai_launcher/presentation/providers/cost_estimate_provider.dart';
import 'package:nai_launcher/presentation/providers/generation/image_workflow_controller.dart';

void main() {
  const base = ImageWorkflowState();

  int? priceOf(ImageParams params, [ImageWorkflowState workflow = base]) =>
      opusUsageImageAnlas(params, workflow);

  test('a free V5 image is priced like the website', () {
    // The default the website counts its images by.
    expect(
      priceOf(
        const ImageParams(model: ImageModels.animeDiffusionV5Full, steps: 23),
      ),
      26,
    );
    expect(
      priceOf(
        const ImageParams(model: ImageModels.animeDiffusionV5Full, steps: 28),
      ),
      30,
    );
    expect(
      priceOf(
        const ImageParams(
          model: ImageModels.animeDiffusionV5Full,
          width: 512,
          height: 768,
          steps: 23,
        ),
      ),
      11,
    );
  });

  test('Medium effort uses its own fixed 14 steps', () {
    // The standard effort's 40 steps stay in the params but are not sent.
    expect(
      priceOf(
        const ImageParams(
          model: ImageModels.animeDiffusionV5FullMedium,
          steps: 40,
        ),
      ),
      17,
    );
  });

  test('settings that do not use the limit have no price', () {
    expect(
      priceOf(
        const ImageParams(model: ImageModels.animeDiffusionV5Full, steps: 29),
      ),
      isNull,
    );
    expect(
      priceOf(
        const ImageParams(
          model: ImageModels.animeDiffusionV5Full,
          width: 1024,
          height: 1536,
          steps: 23,
        ),
      ),
      isNull,
    );
    expect(
      priceOf(
        const ImageParams(model: ImageModels.animeDiffusionV45Full, steps: 23),
      ),
      isNull,
    );
    expect(
      priceOf(
        const ImageParams(model: ImageModels.animeDiffusionV5Full, steps: 23),
        const ImageWorkflowState(mode: ImageWorkflowMode.upscale),
      ),
      isNull,
    );
  });
}
