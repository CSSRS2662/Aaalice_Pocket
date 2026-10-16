import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/localization_extension.dart';
import '../../providers/grid_columns_provider.dart';
import '../common/grid_column_count.dart';
import 'gallery_library_toolbar.dart';
import 'gallery_scope_controls.dart';

/// Column switch for an image waterfall: each press goes 2 → 3 → 4 → 2, and
/// [surface] remembers the choice on this device.
///
/// Library toolbars show it with its label; tight headers pass [iconOnly];
/// filter rows, which scroll sideways, show it as one of their chips.
class MasonryColumnsAction extends ConsumerWidget {
  const MasonryColumnsAction({
    super.key,
    required this.surface,
    this.iconOnly = false,
    this.chip = false,
  });

  final GridColumnsSurface surface;
  final bool iconOnly;
  final bool chip;

  static Key buttonKey(GridColumnsSurface surface) =>
      ValueKey('masonry-columns-${surface.name}');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = gridColumnsProvider(surface);
    final columns = ref.watch(provider);
    void cycle() => ref.read(provider.notifier).cycle();
    if (chip) {
      return GalleryFilterChipButton(
        key: buttonKey(surface),
        icon: GridColumnCount.icon(columns),
        label: context.l10n.common_columnCount(columns),
        active: false,
        onPressed: cycle,
      );
    }
    if (iconOnly) {
      return GridColumnCountButton(
        key: buttonKey(surface),
        columns: columns,
        onPressed: cycle,
      );
    }
    return GalleryLibraryAction(
      key: buttonKey(surface),
      icon: GridColumnCount.icon(columns),
      label: context.l10n.common_columnCount(columns),
      tooltip: context.l10n.common_columnCountTooltip(columns),
      onPressed: cycle,
    );
  }
}
