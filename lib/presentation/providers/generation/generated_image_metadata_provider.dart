import 'package:flutter_riverpod/flutter_riverpod.dart' show Ref;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../data/models/gallery/nai_image_metadata.dart';
import '../../../data/services/image_metadata_service.dart';
import 'generation_models.dart';

part 'generated_image_metadata_provider.g.dart';

/// 解析生成结果自带的 NovelAI 元数据
///
/// 优先使用 [GeneratedImage.metadata]，旧记录缺少元数据时从 PNG 解析。
/// 解析结果由 [ImageMetadataService] 按内容哈希缓存，
/// family key 走 [GeneratedImage] 的 id 相等语义，保存路径回填时不会重复解析。
@riverpod
Future<NaiImageMetadata?> generatedImageMetadata(
  Ref ref,
  GeneratedImage image,
) async {
  final embedded = image.metadata;
  if (embedded != null) return embedded;
  if (image.bytes.isEmpty) return null;

  return ImageMetadataService().getMetadataFromBytes(image.bytes);
}
