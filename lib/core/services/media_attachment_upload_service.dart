import 'package:canil_gcm/core/widgets/media_attachment_rows.dart';
import 'storage_service.dart';

class MediaAttachmentUploadService {
  final StorageService storageService;

  const MediaAttachmentUploadService({required this.storageService});

  Future<List<Map<String, dynamic>>> uploadAll({
    required List<Map<String, dynamic>> attachments,
    required String folder,
    void Function(Map<String, dynamic> attachment)? onUploading,
    void Function(Map<String, dynamic> attachment, String url)? onUploaded,
    void Function(Map<String, dynamic> attachment)? onPending,
  }) async {
    final finalMedia = <Map<String, dynamic>>[];

    for (var i = 0; i < attachments.length; i++) {
      final attachment = attachments[i];
      if (MediaAttachmentRows.isDone(attachment)) {
        final payload = MediaAttachmentRows.uploadedPayload(attachment);
        if (payload != null) {
          finalMedia.add(payload);
        }
        continue;
      }

      onUploading?.call(attachment);

      final url = await storageService.uploadProfileImage(
        MediaAttachmentRows.file(attachment),
        folder,
      );

      if (url == null) {
        onPending?.call(attachment);
        throw Exception('Falha ao subir a foto ${i + 1}.');
      }

      onUploaded?.call(attachment, url);
      finalMedia.add({
        'url': url,
        'caption': MediaAttachmentRows.captionText(attachment),
      });
    }

    return finalMedia;
  }
}
