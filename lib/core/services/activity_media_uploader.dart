import 'package:canil_gcm/core/services/media_attachment_upload_service.dart';
import 'package:canil_gcm/core/services/storage_service.dart';

abstract final class ActivityMediaUploader {
  static Future<List<Map<String, dynamic>>> upload({
    required List<Map<String, dynamic>> attachments,
    required String folder,
    required void Function(Map<String, dynamic>) onUploading,
    required void Function(Map<String, dynamic>, String) onUploaded,
    required void Function(Map<String, dynamic>) onPending,
  }) async {
    if (attachments.isEmpty) return const [];

    return MediaAttachmentUploadService(
      storageService: StorageService(),
    ).uploadAll(
      attachments: attachments,
      folder: folder,
      onUploading: onUploading,
      onUploaded: onUploaded,
      onPending: onPending,
    );
  }
}
