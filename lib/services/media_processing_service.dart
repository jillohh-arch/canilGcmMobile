import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

class MediaProcessingService {
  const MediaProcessingService();

  Future<File?> compressImage(File file) async {
    try {
      final dir = await getTemporaryDirectory();
      final targetPath =
          '${dir.absolute.path}/temp_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final result = await FlutterImageCompress.compressAndGetFile(
        file.absolute.path,
        targetPath,
        quality: 70,
        format: CompressFormat.jpeg,
      );

      return result != null ? File(result.path) : null;
    } catch (e) {
      debugPrint('Erro ao comprimir imagem: $e');
      return null;
    }
  }

  Future<List<File>> pickAndCompressImages({
    double maxWidth = 1280,
    double maxHeight = 1280,
    int imageQuality = 60,
  }) async {
    final picker = ImagePicker();
    final images = await picker.pickMultiImage(
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      imageQuality: imageQuality,
    );
    if (images.isEmpty) return const [];

    final files = <File>[];
    for (final image in images) {
      final originalFile = File(image.path);
      final compressed = await compressImage(originalFile);
      files.add(compressed ?? originalFile);
    }
    return files;
  }
}
