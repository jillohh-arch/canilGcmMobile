import 'package:canil_gcm/features/health/domain/health_evidence_file.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MIME mapping', () {
    test('todas as extensões suportadas mapeiam para o MIME do B0', () {
      const expected = <String, String>{
        'laudo.pdf': 'application/pdf',
        'foto.jpg': 'image/jpeg',
        'foto.jpeg': 'image/jpeg',
        'foto.png': 'image/png',
        'foto.webp': 'image/webp',
        'atestado.doc': 'application/msword',
        'atestado.docx':
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      };
      for (final entry in expected.entries) {
        expect(
          healthEvidenceMimeFor(entry.key),
          entry.value,
          reason: entry.key,
        );
      }
    });

    test('extensão é case-insensitive', () {
      expect(healthEvidenceMimeFor('LAUDO.PDF'), 'application/pdf');
      expect(healthEvidenceMimeFor('Foto.JPeG'), 'image/jpeg');
      expect(healthEvidenceMimeFor('doc.DOCX'), isNotNull);
    });

    test('extensão não suportada devolve null', () {
      for (final name in [
        'arquivo.heic',
        'arquivo.txt',
        'arquivo.zip',
        'arquivo.exe',
        'arquivo.svg',
        'arquivo',
        'arquivo.',
        '',
      ]) {
        expect(healthEvidenceMimeFor(name), isNull, reason: name);
      }
    });

    test('whitelist e lista do picker são coerentes', () {
      for (final ext in kHealthEvidenceAllowedExtensions) {
        expect(
          kHealthEvidenceMimeByExtension.containsKey(ext),
          isTrue,
          reason: 'extensão $ext oferecida no picker sem MIME mapeado',
        );
      }
      expect(
        kHealthEvidenceMimeByExtension.length,
        kHealthEvidenceAllowedExtensions.length,
      );
    });
  });

  group('validação de arquivo', () {
    test('aceita arquivo válido e normaliza', () {
      final result = validateHealthEvidenceFile(
        name: '  laudo.pdf  ',
        path: '  /tmp/laudo.pdf  ',
        size: 4096,
      );
      expect(result, isA<HealthEvidenceFileAccepted>());
      final file = (result as HealthEvidenceFileAccepted).file;
      expect(file.name, 'laudo.pdf');
      expect(file.path, '/tmp/laudo.pdf');
      expect(file.sizeBytes, 4096);
      expect(file.mimeType, 'application/pdf');
    });

    test('aceita todas as extensões da whitelist', () {
      for (final ext in kHealthEvidenceAllowedExtensions) {
        final result = validateHealthEvidenceFile(
          name: 'arquivo.$ext',
          path: '/tmp/arquivo.$ext',
          size: 1024,
        );
        expect(result, isA<HealthEvidenceFileAccepted>(), reason: ext);
      }
    });

    test('extensão maiúscula é aceita', () {
      final result = validateHealthEvidenceFile(
        name: 'LAUDO.PDF',
        path: '/tmp/LAUDO.PDF',
        size: 1024,
      );
      expect(result, isA<HealthEvidenceFileAccepted>());
    });

    test('extensão não suportada é recusada', () {
      final result = validateHealthEvidenceFile(
        name: 'arquivo.heic',
        path: '/tmp/arquivo.heic',
        size: 1024,
      );
      expect(
        (result as HealthEvidenceFileRejected).reason,
        HealthEvidenceFileRejection.unsupportedExtension,
      );
    });

    test('arquivo de 0 byte é recusado', () {
      final result = validateHealthEvidenceFile(
        name: 'laudo.pdf',
        path: '/tmp/laudo.pdf',
        size: 0,
      );
      expect(
        (result as HealthEvidenceFileRejected).reason,
        HealthEvidenceFileRejection.empty,
      );
    });

    test('acima de 20 MB é recusado ANTES de qualquer leitura', () {
      final result = validateHealthEvidenceFile(
        name: 'laudo.pdf',
        path: '/tmp/laudo.pdf',
        size: kHealthEvidenceMaxBytes + 1,
      );
      expect(
        (result as HealthEvidenceFileRejected).reason,
        HealthEvidenceFileRejection.tooLarge,
      );
    });

    test('exatamente 20 MB é aceito', () {
      final result = validateHealthEvidenceFile(
        name: 'laudo.pdf',
        path: '/tmp/laudo.pdf',
        size: kHealthEvidenceMaxBytes,
      );
      expect(result, isA<HealthEvidenceFileAccepted>());
    });

    test('limite bate com MAX_DOCUMENT_BYTES do backend', () {
      expect(kHealthEvidenceMaxBytes, 20 * 1024 * 1024);
    });

    test('path ausente ou vazio é recusado', () {
      for (final path in <String?>[null, '', '   ']) {
        final result = validateHealthEvidenceFile(
          name: 'laudo.pdf',
          path: path,
          size: 1024,
        );
        expect(
          (result as HealthEvidenceFileRejected).reason,
          HealthEvidenceFileRejection.unreadable,
          reason: 'path=$path',
        );
      }
    });

    test('extensão é avaliada antes do tamanho', () {
      // Um .heic gigante deve reportar extensão, não tamanho: a mensagem
      // precisa dizer o que realmente impede o envio.
      final result = validateHealthEvidenceFile(
        name: 'foto.heic',
        path: '/tmp/foto.heic',
        size: kHealthEvidenceMaxBytes + 1,
      );
      expect(
        (result as HealthEvidenceFileRejected).reason,
        HealthEvidenceFileRejection.unsupportedExtension,
      );
    });
  });

  group('natureza do documento', () {
    test('mapeia para os tipos canônicos do B0', () {
      expect(HealthEvidenceNature.certificate.wireName, 'certificate');
      expect(HealthEvidenceNature.report.wireName, 'report');
      expect(HealthEvidenceNature.other.wireName, 'other');
    });

    test('não existe restriction_evidence', () {
      final wires = HealthEvidenceNature.values
          .map((n) => n.wireName)
          .toList();
      expect(wires, isNot(contains('restriction_evidence')));
      expect(wires, isNot(contains('vet_release')));
    });

    test('rótulos são operacionais', () {
      expect(HealthEvidenceNature.certificate.label, 'Atestado');
      expect(HealthEvidenceNature.report.label, 'Laudo / Relatório');
      expect(HealthEvidenceNature.other.label, 'Outro documento');
    });
  });

  group('identidade local', () {
    test('muda quando o arquivo muda', () {
      const a = SelectedHealthEvidenceFile(
        name: 'laudo.pdf',
        path: '/tmp/laudo.pdf',
        sizeBytes: 4096,
        mimeType: 'application/pdf',
      );
      const mesmoConteudoOutroPath = SelectedHealthEvidenceFile(
        name: 'laudo.pdf',
        path: '/outro/laudo.pdf',
        sizeBytes: 4096,
        mimeType: 'application/pdf',
      );
      const outroTamanho = SelectedHealthEvidenceFile(
        name: 'laudo.pdf',
        path: '/tmp/laudo.pdf',
        sizeBytes: 9999,
        mimeType: 'application/pdf',
      );

      // Path não entra na identidade: o mesmo arquivo copiado para um cache
      // temporário diferente não deve invalidar a intenção documental.
      expect(a.localIdentity, mesmoConteudoOutroPath.localIdentity);
      expect(a.localIdentity, isNot(outroTamanho.localIdentity));
    });
  });
}
