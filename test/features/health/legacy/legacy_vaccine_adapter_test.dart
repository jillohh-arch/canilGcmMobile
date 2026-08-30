import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/legacy/legacy_health_adapters.dart';
import 'package:canil_gcm/features/health/legacy/legacy_vaccine_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const adapter = LegacyVaccineAdapter();

  group('LegacyVaccineAdapter', () {
    test('documento real com campos mínimos → partial (sem recorded_by)', () {
      // Fonte: VaccineRecord em dog_profile_service.dart.
      // Campos reais: id, caoId, nome, dataAplicacao, dataVencimento, status.
      final result = adapter.parse(
        sourceId: 'vac-1',
        dogId: 'dog-1',
        data: const {
          'nome': 'V10',
          'dataAplicacao': '2026-07-14T10:00:00Z',
          'dataVencimento': '2027-07-14T10:00:00Z',
          'status': 'ativo',
        },
      );
      expect(result.state, LegacyParseState.partial);
      expect(result.value, isA<LegacyHealthRecordView>());
      final view = result.value! as LegacyHealthRecordView;
      expect(view.description, 'V10');
      expect(view.originalPayload['status'], 'ativo');
      expect(view.originalPayload['dataVencimento'], isNotNull);
      expect(result.issues.any((i) => i.code == 'no_recorded_by'), isTrue);
    });

    test('status legado bruto é preservado sem normalização', () {
      for (final status in ['ativo', 'cancelado', 'cancelled', '', 'xyz']) {
        final result = adapter.parse(
          sourceId: 'vac-st',
          dogId: 'dog-1',
          data: {
            'nome': 'Antirrábica',
            'dataAplicacao': '2026-07-14T10:00:00Z',
            if (status.isNotEmpty) 'status': status,
          },
        );
        expect(result.state, LegacyParseState.partial);
        final view = result.value! as LegacyHealthRecordView;
        if (status.isNotEmpty) {
          expect(view.originalPayload['status'], status);
        }
        // Sem promoção canônica nem código novo de status.
        expect(
          result.issues.any((i) => i.code == 'cancelled_legacy_record'),
          isFalse,
        );
        expect(
          result.issues.any((i) => i.code == 'unmapped_legacy_status'),
          isFalse,
        );
      }
    });

    test('data de aplicação ausente → failure', () {
      final result = adapter.parse(
        sourceId: 'vac-3',
        dogId: 'dog-1',
        data: const {'nome': 'V10'},
      );
      expect(result.state, LegacyParseState.failure);
    });

    test('data de aplicação inválida → failure', () {
      final result = adapter.parse(
        sourceId: 'vac-bad-date',
        dogId: 'dog-1',
        data: const {'nome': 'V10', 'dataAplicacao': 'não-é-data'},
      );
      expect(result.state, LegacyParseState.failure);
    });

    test('nome ausente → failure', () {
      final result = adapter.parse(
        sourceId: 'vac-4',
        dogId: 'dog-1',
        data: const {'dataAplicacao': '2026-07-14T10:00:00Z'},
      );
      expect(result.state, LegacyParseState.failure);
    });

    test('source_id vazio → failure', () {
      final result = adapter.parse(
        sourceId: ' ',
        dogId: 'dog-1',
        data: const {'nome': 'V10', 'dataAplicacao': '2026-07-14T10:00:00Z'},
      );
      expect(result.state, LegacyParseState.failure);
    });

    test('campos fabricados (fabricante/lote/created_by) são ignorados', () {
      final result = adapter.parse(
        sourceId: 'vac-6',
        dogId: 'dog-1',
        data: const {
          'nome': 'V10',
          'dataAplicacao': '2026-07-14T10:00:00Z',
          'fabricante': 'VetLab',
          'lote': 'L-001',
          'created_by': 'u-legacy',
          'createdBy': 'u-legacy',
          'recorded_by': {
            'uid': 'u1',
            'name': 'Condutor',
            'internal_role': 'condutor',
          },
        },
      );
      // Mesmo com recorded_by fabricado na fixture, a fonte real não o provê
      // como campo canônico do VaccineRecord — partial por no_recorded_by.
      expect(result.state, LegacyParseState.partial);
      expect(result.issues.any((i) => i.code == 'no_recorded_by'), isTrue);
      expect(result.value, isA<LegacyHealthRecordView>());
    });
  });
}
