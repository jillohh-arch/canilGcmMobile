import 'dart:io';

import 'package:canil_gcm/core/services/media_processing_service.dart';
import 'package:canil_gcm/core/services/storage_service.dart';

class OccurrenceEventMediaService {
  final MediaProcessingService mediaProcessingService;
  final StorageService storageService;

  const OccurrenceEventMediaService({
    this.mediaProcessingService = const MediaProcessingService(),
    required this.storageService,
  });

  Future<List<File>> pickCompressedPhotos() {
    return mediaProcessingService.pickAndCompressImages();
  }

  Future<List<Map<String, dynamic>>> uploadPhotos({
    required List<File> files,
    required String incidentIdOrDogId,
  }) async {
    if (files.isEmpty) return const [];

    final uploaded = <Map<String, dynamic>>[];
    final folder = 'incidents/$incidentIdOrDogId/events';

    for (var i = 0; i < files.length; i++) {
      final url = await storageService.uploadImage(files[i], folder);
      if (url == null) {
        throw Exception('Falha ao subir a foto do evento ${i + 1}.');
      }
      uploaded.add({
        'url': url,
        'type': 'photo',
        'caption': '',
        'uploadedAt': DateTime.now().toIso8601String(),
      });
    }

    return uploaded;
  }
}
