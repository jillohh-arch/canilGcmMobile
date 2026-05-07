import 'dart:io';

import 'package:file_picker/file_picker.dart';

import 'storage_service.dart';

class PickedPdfAttachment {
  final File file;
  final String name;

  const PickedPdfAttachment({required this.file, required this.name});
}

class PdfAttachmentService {
  const PdfAttachmentService();

  Future<PickedPdfAttachment?> pickPdf() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      allowMultiple: false,
    );
    final path = result?.files.single.path;
    if (path == null) return null;

    return PickedPdfAttachment(
      file: File(path),
      name: result!.files.single.name,
    );
  }

  Future<String?> uploadExamPdf(File file) async {
    return StorageService().uploadFile(
      file,
      'health/exams',
      mimeType: 'application/pdf',
      extension: 'pdf',
    );
  }
}
