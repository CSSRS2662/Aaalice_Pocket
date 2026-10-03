import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/app_logger.dart';
import '../../core/utils/localization_extension.dart';
import '../widgets/common/app_toast.dart';
import 'image_metadata_import_workflow.dart';

class PickedImageData {
  const PickedImageData({required this.fileName, required this.bytes});

  final String fileName;
  final Uint8List bytes;
}

typedef ImageBytesPicker = Future<PickedImageData?> Function();
typedef PickedImageProcessor =
    Future<void> Function(
      BuildContext context,
      WidgetRef ref,
      PickedImageData image,
    );

/// Reads the parameters of a system-picked image.
///
/// Uses the same flow as "reuse parameters" in favorites and history: choose
/// the parameters to apply, apply them, then return to generation.
class MobileImageMetadataImporter {
  MobileImageMetadataImporter({
    ImageBytesPicker? imageBytesPicker,
    PickedImageProcessor? imageProcessor,
    ImageMetadataImportWorkflow? workflow,
  }) : _imageBytesPicker = imageBytesPicker ?? _pickImageBytes,
       _imageProcessor =
           imageProcessor ??
           _workflowProcessor(workflow ?? ImageMetadataImportWorkflow.shared);

  static final MobileImageMetadataImporter shared =
      MobileImageMetadataImporter();

  final ImageBytesPicker _imageBytesPicker;
  final PickedImageProcessor _imageProcessor;

  Future<void> run({
    required BuildContext context,
    required WidgetRef ref,
  }) async {
    final PickedImageData image;
    try {
      final selectedImage = await _imageBytesPicker();
      if (selectedImage == null || !context.mounted) return;
      image = selectedImage;
      if (image.bytes.isEmpty) {
        throw const FormatException('Selected image is empty');
      }
    } catch (error, stackTrace) {
      AppLogger.e(
        'Failed to read selected image',
        error,
        stackTrace,
        'MobileMetadataImport',
      );
      if (context.mounted) {
        AppToast.error(context, context.l10n.metadataImport_readFailed);
      }
      return;
    }

    try {
      await _imageProcessor(context, ref, image);
    } catch (error, stackTrace) {
      AppLogger.e(
        'Failed to process selected image',
        error,
        stackTrace,
        'MobileMetadataImport',
      );
      if (context.mounted) {
        AppToast.error(context, context.l10n.metadataImport_processFailed);
      }
    }
  }

  static Future<PickedImageData?> _pickImageBytes() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png', 'webp'],
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;

    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      throw StateError(
        'The system picker did not provide readable image bytes',
      );
    }
    return PickedImageData(fileName: file.name, bytes: bytes);
  }

  static PickedImageProcessor _workflowProcessor(
    ImageMetadataImportWorkflow workflow,
  ) {
    return (context, ref, image) =>
        workflow.run(context: context, read: ref.read, bytes: image.bytes);
  }
}
