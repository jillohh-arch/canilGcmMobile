import 'package:canil_gcm/features/health/domain/health_document.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final actor = RecordedBy(
    uid: 'u1',
    name: 'Condutor',
    internalRole: 'condutor',
  );
  final uploaded = DateTime.utc(2026, 7, 14, 10);
  final expiry = DateTime.utc(2027, 7, 14);

  HealthDocument build({
    String title = 'Laudo',
    String storagePath = 'documentos/dog-1/laudo.pdf',
    String mimeType = 'application/pdf',
    DateTime? issueDate,
    DateTime? expiryDate,
    int? fileSizeBytes,
  }) => HealthDocument(
    id: 'doc-1',
    dogId: 'dog-1',
    documentType: HealthDocumentType.report,
    title: title,
    storagePath: storagePath,
    mimeType: mimeType,
    recordedBy: actor,
    uploadedAt: uploaded,
    schemaVersion: 1,
    issueDate: issueDate,
    expiryDate: expiryDate,
    fileSizeBytes: fileSizeBytes,
  );

  group('HealthDocument', () {
    test('construção válida', () {
      final doc = build();
      expect(doc.documentType, HealthDocumentType.report);
      expect(doc.title, 'Laudo');
    });

    test('storagePath vazio é rejeitado', () {
      expect(
        () => build(storagePath: '   '),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('mimeType vazio é rejeitado', () {
      expect(
        () => build(mimeType: ''),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('title vazio é rejeitado', () {
      expect(
        () => build(title: ''),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('expiry anterior a issueDate é rejeitado', () {
      expect(
        () => build(
          issueDate: expiry,
          expiryDate: expiry.subtract(const Duration(days: 1)),
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('fileSizeBytes negativo é rejeitado', () {
      expect(
        () => build(fileSizeBytes: -1),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('schemaVersion <= 0 é rejeitado', () {
      expect(
        () => HealthDocument(
          id: 'doc-1',
          dogId: 'dog-1',
          documentType: HealthDocumentType.report,
          title: 'Laudo',
          storagePath: 'documentos/dog-1/laudo.pdf',
          mimeType: 'application/pdf',
          recordedBy: actor,
          uploadedAt: uploaded,
          schemaVersion: 0,
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('isExpiredAt retorna true somente após expiryDate', () {
      final doc = build(expiryDate: expiry);
      expect(doc.isExpiredAt(expiry.subtract(const Duration(days: 1))), isFalse);
      expect(doc.isExpiredAt(expiry), isFalse);
      expect(doc.isExpiredAt(expiry.add(const Duration(days: 1))), isTrue);
    });

    test('isExpiredAt retorna false quando expiryDate ausente', () {
      final doc = build();
      expect(doc.isExpiredAt(uploaded.add(const Duration(days: 365))), isFalse);
    });

    test('campos opcionais preservam imutabilidade (não há setter)', () {
      final doc = build();
      // Verificação estática: o construtor exige imutabilidade por
      // ausência de setters na API pública.
      expect(doc.caseId, isNull);
      expect(doc.issuer, isNull);
    });
  });
}