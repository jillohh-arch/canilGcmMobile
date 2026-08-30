import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/legacy/legacy_document_adapter.dart';
import 'package:canil_gcm/features/health/legacy/legacy_health_adapters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const adapter = LegacyDocumentAdapter();

  group('LegacyDocumentAdapter', () {
    test('documento real → partial sem promover canônico', () {
      // Fonte: DogDocument — caoId, nome, descricao, tipo, url, dataUpload, emissor.
      final result = adapter.parse(
        sourceId: 'doc-1',
        dogId: 'dog-1',
        data: const {
          'nome': 'laudo.pdf',
          'url':
              'https://storage.googleapis.com/canil/documentos/dog-1/laudo.pdf',
          'dataUpload': '2026-07-14T10:00:00Z',
          'descricao': 'Resultado de hemograma',
          'emissor': 'Clínica Norte',
          'tipo': 'laudo',
        },
      );
      expect(result.state, LegacyParseState.partial);
      expect(result.value, isA<LegacyHealthRecordView>());
      final view = result.value! as LegacyHealthRecordView;
      expect(view.originalPayload['tipo'], 'laudo');
      expect(view.originalPayload['url'], isNotNull);
      expect(view.originalPayload['emissor'], 'Clínica Norte');
      expect(result.issues.any((i) => i.code == 'no_recorded_by'), isTrue);
    });

    test('tipo legado PT (laudo/certificado/documento) não é promovido', () {
      for (final tipo in ['laudo', 'certificado', 'documento', 'report']) {
        final result = adapter.parse(
          sourceId: 'doc-tipo',
          dogId: 'dog-1',
          data: {
            'nome': 'arquivo.pdf',
            'url': 'https://example.com/file',
            'dataUpload': '2026-07-14T10:00:00Z',
            'tipo': tipo,
          },
        );
        expect(result.state, LegacyParseState.partial);
        final view = result.value! as LegacyHealthRecordView;
        expect(view.originalPayload['tipo'], tipo);
        // Sem mapeamento a HealthDocumentType; só partial por autoria.
        expect(result.value, isA<LegacyHealthRecordView>());
      }
    });

    test('URL com path /documentos/ NÃO deriva storage_path canônico', () {
      final result = adapter.parse(
        sourceId: 'doc-path',
        dogId: 'dog-1',
        data: const {
          'nome': 'laudo.pdf',
          'url':
              'https://storage.googleapis.com/canil/documentos/dog-1/laudo.pdf',
          'dataUpload': '2026-07-14T10:00:00Z',
        },
      );
      expect(result.state, LegacyParseState.partial);
      // Resultado é view legada, não HealthDocument com storagePath.
      expect(result.value, isA<LegacyHealthRecordView>());
      expect(result.value, isNot(isA<Never>()));
    });

    test('nome com extensão NÃO infere MIME canônico', () {
      final result = adapter.parse(
        sourceId: 'doc-mime',
        dogId: 'dog-1',
        data: const {
          'nome': 'foto-lesao.png',
          'url': 'https://example.com/foto.png',
          'dataUpload': '2026-07-14T10:00:00Z',
        },
      );
      expect(result.state, LegacyParseState.partial);
      expect(result.value, isA<LegacyHealthRecordView>());
    });

    test('URL ausente → failure', () {
      final result = adapter.parse(
        sourceId: 'doc-9',
        dogId: 'dog-1',
        data: const {'nome': 'Laudo', 'dataUpload': '2026-07-14T10:00:00Z'},
      );
      expect(result.state, LegacyParseState.failure);
    });

    test('data de upload inválida → failure', () {
      final result = adapter.parse(
        sourceId: 'doc-10',
        dogId: 'dog-1',
        data: const {
          'nome': 'Laudo',
          'url': 'https://example.com/x.pdf',
          'dataUpload': 'invalida',
        },
      );
      expect(result.state, LegacyParseState.failure);
    });

    test('título ausente → failure', () {
      final result = adapter.parse(
        sourceId: 'doc-11',
        dogId: 'dog-1',
        data: const {
          'url': 'https://example.com/x.pdf',
          'dataUpload': '2026-07-14T10:00:00Z',
        },
      );
      expect(result.state, LegacyParseState.failure);
    });
  });
}
