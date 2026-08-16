import 'dart:typed_data';

import 'package:canil_gcm/features/health/data/restriction/storage_health_evidence_uploader.dart';
import 'package:canil_gcm/features/health/domain/health_evidence_file.dart';
import 'package:canil_gcm/features/health/domain/health_restriction_flow_errors.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const file = SelectedHealthEvidenceFile(
    name: 'laudo.pdf',
    path: '/tmp/laudo.pdf',
    sizeBytes: 4096,
    mimeType: 'application/pdf',
  );

  const uploadPath = 'health_document_uploads/dog-1/hd_abc';

  Future<Uint8List> bytes(SelectedHealthEvidenceFile _) async =>
      Uint8List.fromList(List<int>.filled(16, 7));

  test('sucesso envia no path exato com MIME explícito', () async {
    final paths = <String>[];
    final mimes = <String>[];
    final uploader = StorageHealthEvidenceUploader(
      bytesReader: bytes,
      sink: (data, path, {String mimeType = 'application/octet-stream'}) async {
        paths.add(path);
        mimes.add(mimeType);
        return 'https://exemplo/download-url';
      },
    );

    await uploader.upload(file: file, uploadPath: uploadPath);

    expect(paths.single, uploadPath);
    expect(mimes.single, 'application/pdf');
  });

  test('FAIL-CLOSED: null do uploadBytes vira erro de integridade', () async {
    // Este é o comportamento que justifica o wrapper: `object-not-found`
    // devolve null em StorageService, um sucesso aparente.
    final uploader = StorageHealthEvidenceUploader(
      bytesReader: bytes,
      sink: (data, path, {String mimeType = 'application/octet-stream'}) async =>
          null,
    );

    await expectLater(
      uploader.upload(file: file, uploadPath: uploadPath),
      throwsA(
        isA<HealthRestrictionFlowIntegrity>().having(
          (e) => e.step,
          'step',
          HealthRestrictionFlowStep.documentUpload,
        ),
      ),
    );
  });

  test('exceção do Storage vira falha offline', () async {
    final uploader = StorageHealthEvidenceUploader(
      bytesReader: bytes,
      sink: (data, path, {String mimeType = 'application/octet-stream'}) async {
        throw Exception('Falha ao subir arquivo. Verifique sua conexão.');
      },
    );

    await expectLater(
      uploader.upload(file: file, uploadPath: uploadPath),
      throwsA(isA<HealthRestrictionFlowOffline>()),
    );
  });

  test('arquivo ilegível vira validação com mensagem acionável', () async {
    final uploader = StorageHealthEvidenceUploader(
      bytesReader: (_) async => throw Exception('no such file'),
      sink: (data, path, {String mimeType = 'application/octet-stream'}) async =>
          'url',
    );

    await expectLater(
      uploader.upload(file: file, uploadPath: uploadPath),
      throwsA(
        isA<HealthRestrictionFlowValidation>().having(
          (e) => e.message,
          'message',
          contains('Escolha o arquivo novamente'),
        ),
      ),
    );
  });

  test('arquivo vazio não é enviado', () async {
    var called = false;
    final uploader = StorageHealthEvidenceUploader(
      bytesReader: (_) async => Uint8List(0),
      sink: (data, path, {String mimeType = 'application/octet-stream'}) async {
        called = true;
        return 'url';
      },
    );

    await expectLater(
      uploader.upload(file: file, uploadPath: uploadPath),
      throwsA(isA<HealthRestrictionFlowValidation>()),
    );
    expect(called, isFalse, reason: 'nada é enviado para o Storage');
  });

  test('uploadPath vazio é bug de orquestração, não vai ao Storage', () async {
    var called = false;
    final uploader = StorageHealthEvidenceUploader(
      bytesReader: bytes,
      sink: (data, path, {String mimeType = 'application/octet-stream'}) async {
        called = true;
        return 'url';
      },
    );

    for (final path in ['', '   ']) {
      await expectLater(
        uploader.upload(file: file, uploadPath: path),
        throwsA(isA<HealthRestrictionFlowIntegrity>()),
      );
    }
    expect(called, isFalse);
  });

  test('cliente nunca constrói path canônico', () async {
    final paths = <String>[];
    final uploader = StorageHealthEvidenceUploader(
      bytesReader: bytes,
      sink: (data, path, {String mimeType = 'application/octet-stream'}) async {
        paths.add(path);
        return 'url';
      },
    );

    await uploader.upload(file: file, uploadPath: uploadPath);

    // O único destino é o staging devolvido pelo PREPARE.
    expect(paths.single, startsWith('health_document_uploads/'));
    expect(
      paths.single,
      isNot(startsWith('health_documents/')),
      reason: 'namespace canônico é backend-only',
    );
  });
}
