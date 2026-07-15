import 'health_v1_enums_ext.dart';
import 'health_v1_models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// HealthDocument — arquivo clínico (Domain Model §2.10).
// Apenas contratos de domínio — nenhum upload/download/Storage/OCR/PDF.
// ─────────────────────────────────────────────────────────────────────────────

final class HealthDocument {
  HealthDocument({
    required this.id,
    required this.dogId,
    required this.documentType,
    required String title,
    required this.storagePath,
    required this.mimeType,
    required this.recordedBy,
    required DateTime uploadedAt,
    required this.schemaVersion,
    this.caseId,
    this.eventId,
    this.examId,
    String? description,
    String? issuer,
    this.issueDate,
    this.expiryDate,
    this.fileSizeBytes,
    this.storageUrl,
  }) : title = title.trim(),
       uploadedAt = uploadedAt,
       description = description?.trim(),
       issuer = issuer?.trim() {
    if (schemaVersion <= 0) {
      throw const HealthDomainException(
        'invalid_schema_version',
        'schema_version deve ser positivo',
      );
    }
    if (title.isEmpty) {
      throw const HealthDomainException(
        'missing_document_title',
        'title é obrigatório',
      );
    }
    if (storagePath.trim().isEmpty) {
      throw const HealthDomainException(
        'missing_storage_path',
        'storage_path é a identidade canônica do documento',
      );
    }
    if (mimeType.trim().isEmpty) {
      throw const HealthDomainException(
        'missing_mime_type',
        'mime_type é obrigatório',
      );
    }
    if (expiryDate != null &&
        issueDate != null &&
        expiryDate!.isBefore(issueDate!)) {
      throw const HealthDomainException(
        'inconsistent_document_dates',
        'expiry_date não pode ser anterior a issue_date',
      );
    }
    if (fileSizeBytes != null && fileSizeBytes! < 0) {
      throw const HealthDomainException(
        'invalid_file_size',
        'file_size_bytes não pode ser negativo',
      );
    }
  }

  final String id;
  final String dogId;
  final HealthDocumentType documentType;
  final String title;
  final String storagePath;
  final String mimeType;
  final RecordedBy recordedBy;
  final DateTime uploadedAt;
  final int schemaVersion;
  final String? caseId;
  final String? eventId;
  final String? examId;
  final String? description;
  final String? issuer;
  final DateTime? issueDate;
  final DateTime? expiryDate;
  final int? fileSizeBytes;
  final String? storageUrl;

  /// `is_expired` derivado (Domain Model §2.10). Não persistido.
  bool isExpiredAt(DateTime reference) =>
      expiryDate != null && reference.isAfter(expiryDate!);
}
