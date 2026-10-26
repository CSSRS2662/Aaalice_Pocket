import 'dart:math' as math;

/// V5 Opus 使用上限（界面称“体力”）的估算。
///
/// 依据：
/// - 官方说明（journal.novelai.net/opus-usage-limit-explained）：配额按每张 V5
///   图的 Anlas 价格扣减，尺寸越小、步数越少扣得越少；默认设置（23 步、约 1MP）
///   约每 1% 17 张、满格约 1730 张。
/// - 网页端：剩余张数写死为 `round(17.3 × 百分比)`，即默认生成（V5 标准档、
///   832×1216、23 步，价格 26 Anlas）的张数；额外购买的配额
///   `purchasedPercent` 与剩余百分比相加计入；回充速度显示为
///   `86400 / timeUntilNextPercent` %/天。
///
/// 所以 1% 约等于 17.3 × 26 ≈ 450 Anlas 的免费生成，张数按当前设置下一张图的
/// Anlas 价格折算：节约档、小尺寸、图生图强度低时张数相应增加。服务端只返回
/// 百分比，界面必须标注“约”或“估算”。
abstract final class OpusUsageEstimator {
  /// 网页端每 1% 计的张数，对应默认生成。
  static const double defaultImagesPerPercent = 17.3;

  /// 默认生成（V5 标准档、832×1216、23 步）的 Anlas 价格。
  static const int defaultImageAnlas = 26;

  /// 1% 配额对应的 Anlas 价格总量。
  static const double anlasPerPercent =
      defaultImagesPerPercent * defaultImageAnlas;

  /// 一张价格为 [imageAnlas] 的免费图占用的配额百分比。
  static double percentPerImage(int imageAnlas) =>
      imageAnlas <= 0 ? 0 : imageAnlas / anlasPerPercent;

  /// [percent] 的配额约可生成多少张价格为 [imageAnlas] 的图；与网页端一样四舍
  /// 五入，默认生成时与网页端显示一致。
  static int imagesForPercent(double percent, {required int imageAnlas}) {
    if (percent <= 0 || imageAnlas <= 0) return 0;
    return (percent * anlasPerPercent / imageAnlas).round();
  }

  /// 每天回充的百分比；服务端未给出回充速度时为 0。
  static double refillPercentPerDay(double secondsPerPercent) =>
      secondsPerPercent <= 0 ? 0 : 86400 / secondsPerPercent;

  /// 按当前回充速度回满 100% 所需的时间；已满时为 [Duration.zero]，回充速度
  /// 未知时为 null。超过 100% 时网页端暂停回充。
  static Duration? timeToFull({
    required double percent,
    required double secondsPerPercent,
  }) {
    if (percent >= 100) return Duration.zero;
    if (secondsPerPercent <= 0) return null;
    final missing = 100 - math.max(0, percent);
    return Duration(seconds: (missing * secondsPerPercent).round());
  }
}
