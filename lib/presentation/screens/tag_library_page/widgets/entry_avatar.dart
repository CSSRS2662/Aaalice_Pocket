import 'package:flutter/material.dart';

import '../../../../data/models/tag_library/tag_library_entry.dart';
import '../../../widgets/common/thumbnail_display.dart';
import '../../../widgets/tag_library/library_group_style.dart';

/// An entry's rounded square: its preview image when it has one, otherwise
/// its group's icon on the group's tint.
class EntryAvatar extends StatelessWidget {
  const EntryAvatar({
    super.key,
    required this.entry,
    required this.style,
    this.size = 40,
  });

  final TagLibraryEntry entry;
  final LibraryGroupStyle style;
  final double size;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.3);
    final thumbnail = entry.thumbnail;
    if (!entry.hasThumbnail || thumbnail == null) {
      return LibraryGroupIcon(style: style, size: size);
    }
    return SizedBox.square(
      dimension: size,
      child: ClipRRect(
        borderRadius: radius,
        child: ThumbnailDisplay(
          imagePath: thumbnail,
          offsetX: entry.thumbnailOffsetX,
          offsetY: entry.thumbnailOffsetY,
          scale: entry.thumbnailScale,
          width: size,
          height: size,
        ),
      ),
    );
  }
}
