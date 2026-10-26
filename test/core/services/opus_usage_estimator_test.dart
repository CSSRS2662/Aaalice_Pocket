import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/services/opus_usage_estimator.dart';

void main() {
  group('OpusUsageEstimator', () {
    test('at the default price it counts what the website shows', () {
      // The website: round(17.3 × percent), for the default 26-Anlas image.
      for (final percent in const [1.0, 11.0, 37.5, 86.0, 100.0]) {
        expect(
          OpusUsageEstimator.imagesForPercent(
            percent,
            imageAnlas: OpusUsageEstimator.defaultImageAnlas,
          ),
          (17.3 * percent).round(),
          reason: '$percent%',
        );
      }
      expect(OpusUsageEstimator.imagesForPercent(100, imageAnlas: 26), 1730);
    });

    test('cheaper images fit more, dearer ones fewer', () {
      // Medium effort at 832×1216 is 17 Anlas, 28 standard steps 30,
      // 512×768 at 23 steps 11.
      expect(OpusUsageEstimator.imagesForPercent(100, imageAnlas: 17), 2646);
      expect(OpusUsageEstimator.imagesForPercent(100, imageAnlas: 30), 1499);
      expect(OpusUsageEstimator.imagesForPercent(100, imageAnlas: 11), 4089);
      expect(OpusUsageEstimator.percentPerImage(26), closeTo(1 / 17.3, 1e-9));
      expect(OpusUsageEstimator.percentPerImage(17), lessThan(1 / 17.3));
    });

    test('nothing left or no price counts nothing', () {
      expect(OpusUsageEstimator.imagesForPercent(0, imageAnlas: 26), 0);
      expect(OpusUsageEstimator.imagesForPercent(-3, imageAnlas: 26), 0);
      expect(OpusUsageEstimator.imagesForPercent(50, imageAnlas: 0), 0);
      expect(OpusUsageEstimator.percentPerImage(0), 0);
    });

    test('the refill rate is a day over the seconds per percent', () {
      expect(
        OpusUsageEstimator.refillPercentPerDay(6048),
        closeTo(14.2857, 1e-3),
      );
      expect(
        OpusUsageEstimator.refillPercentPerDay(7888),
        closeTo(10.95, 1e-2),
      );
      expect(OpusUsageEstimator.refillPercentPerDay(0), 0);
    });

    test('time to full follows the current refill rate', () {
      expect(
        OpusUsageEstimator.timeToFull(percent: 67, secondsPerPercent: 6048),
        const Duration(seconds: 33 * 6048),
      );
      expect(
        OpusUsageEstimator.timeToFull(percent: -5, secondsPerPercent: 6048),
        const Duration(seconds: 100 * 6048),
      );
      expect(
        OpusUsageEstimator.timeToFull(percent: 100, secondsPerPercent: 6048),
        Duration.zero,
      );
      expect(
        OpusUsageEstimator.timeToFull(percent: 140, secondsPerPercent: 0),
        Duration.zero,
      );
      expect(
        OpusUsageEstimator.timeToFull(percent: 50, secondsPerPercent: 0),
        isNull,
      );
    });
  });
}
