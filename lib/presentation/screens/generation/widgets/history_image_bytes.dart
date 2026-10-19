import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../providers/generation/generated_image_file_cache.dart';
import '../../../providers/generation/generation_models.dart';
import '../../../themes/core/layered_surface_style.dart';

/// Builds a history card with its image bytes. A file-backed image is read
/// off the UI thread first, showing a plain tile meanwhile, so scrolling
/// never waits on a file. The bytes stay with this element: a card on
/// screen keeps them while the shared cache evicts older images.
class HistoryImageBytes extends StatefulWidget {
  const HistoryImageBytes({
    super.key,
    required this.image,
    required this.builder,
  });

  final GeneratedImage image;
  final Widget Function(Uint8List bytes) builder;

  @override
  State<HistoryImageBytes> createState() => _HistoryImageBytesState();
}

class _HistoryImageBytesState extends State<HistoryImageBytes> {
  Uint8List? _bytes;
  String? _resolvedId;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant HistoryImageBytes oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget.image;
    final image = widget.image;
    if (old.id != image.id ||
        old.isStored != image.isStored ||
        old.storedPath != image.storedPath) {
      _resolve();
    }
  }

  void _resolve() {
    final image = widget.image;
    final id = image.id;
    _resolvedId = id;
    final path = image.storedPath;
    if (!image.isStored || path == null) {
      _bytes = image.bytes;
      return;
    }
    _bytes = GeneratedImageFileCache.peek(path);
    if (_bytes != null) return;
    GeneratedImageFileCache.load(path).then((bytes) {
      if (!mounted || _resolvedId != id) return;
      setState(() => _bytes = bytes);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes != null) return widget.builder(bytes);
    return DecoratedBox(
      key: const ValueKey('history-image-loading'),
      decoration: BoxDecoration(
        color: controlSurfaceColor(Theme.of(context).colorScheme),
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }
}
