import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/localization_extension.dart';
import '../../providers/local_gallery_provider.dart';
import 'gallery_scope_controls.dart';

/// 本地图库的快捷范围栏：日期与分类以可清除的条件显示当前取值。图库只放
/// 收藏，没有全部 / 收藏切换。只负责呈现与转发，真实的过滤逻辑由调用方提供。
class LocalGalleryScopeBar extends ConsumerWidget {
  const LocalGalleryScopeBar({
    super.key,
    required this.onPickDateRange,
    required this.onClearDateRange,
    required this.onOpenCollections,
    required this.onClearCollection,
    this.collectionLabel,
  });

  /// 当前选中的分类或相簿名称；未选时为 null。
  final String? collectionLabel;

  final VoidCallback onPickDateRange;
  final VoidCallback onClearDateRange;
  final VoidCallback onOpenCollections;
  final VoidCallback onClearCollection;

  static String formatDateRange(DateTime? start, DateTime? end) {
    final format = DateFormat('M/d');
    if (start != null && end != null) {
      return '${format.format(start)} ~ ${format.format(end)}';
    }
    if (start != null) return '${format.format(start)} ~';
    if (end != null) return '~ ${format.format(end)}';
    return '';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final criteria = ref.watch(
      localGalleryNotifierProvider.select((state) => state.filterCriteria),
    );
    final hasDate = criteria.dateStart != null || criteria.dateEnd != null;
    final collection = collectionLabel;

    return GalleryScopeRow(
      key: const ValueKey('local-gallery-scope-bar'),
      children: [
        GalleryFilterChipButton(
          key: const ValueKey('local-gallery-date-chip'),
          clearKey: const ValueKey('local-gallery-date-clear'),
          icon: Icons.event_rounded,
          label: hasDate
              ? formatDateRange(criteria.dateStart, criteria.dateEnd)
              : l10n.common_date,
          active: hasDate,
          onPressed: onPickDateRange,
          onClear: hasDate ? onClearDateRange : null,
          clearTooltip: l10n.common_clear,
        ),
        GalleryFilterChipButton(
          key: const ValueKey('local-gallery-collection-chip'),
          clearKey: const ValueKey('local-gallery-collection-clear'),
          icon: Icons.folder_outlined,
          label: collection ?? l10n.common_categories,
          active: collection != null,
          onPressed: onOpenCollections,
          onClear: collection != null ? onClearCollection : null,
          clearTooltip: l10n.common_clear,
        ),
      ],
    );
  }
}
