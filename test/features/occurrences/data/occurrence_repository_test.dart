import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/occurrences/data/occurrence_repository.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_result.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_status.dart';

void main() {
  late FakeFirebaseFirestore fakeFirestore;
  late OccurrenceRepository repository;

  final now = DateTime(2026, 5, 18, 14, 30);

  Occurrence buildOccurrence({
    String id = 'occ-001',
    String dogId = 'dog-001',
    OccurrenceStatus status = OccurrenceStatus.inProgress,
  }) {
    return Occurrence(
      id: id,
      shiftId: 'shift-001',
      primaryHandlerId: 'handler-001',
      dogId: dogId,
      typeCode: 'FARO_VEICULO',
      typeName: 'Faro em Veículo',
      locationAddress: 'Rua Brasil, 100',
      gpsLat: -22.5642,
      gpsLng: -47.4019,
      gpsAccuracy: 4.2,
      startedAt: now,
      createdAt: now,
      updatedAt: now,
      status: status,
    );
  }

  setUp(() {
    fakeFirestore = FakeFirebaseFirestore();
    repository = OccurrenceRepository(fakeFirestore);
  });

  group('OccurrenceRepository', () {
    group('create', () {
      test('salva documento na coleção occurrences', () async {
        final occ = buildOccurrence();
        final created = await repository.create(occ);

        final snap = await fakeFirestore
            .collection('occurrences')
            .doc('occ-001')
            .get();
        expect(snap.exists, isTrue);
        expect(snap.data()!['dog_id'], equals('dog-001'));
        expect(snap.data()!['type_code'], equals('FARO_VEICULO'));
        expect(snap.data()!['status'], equals('in_progress'));
        expect(created.auditTrail.length, equals(1));
        expect(created.auditTrail.first['action'], equals('created'));
      });
    });

    group('getById', () {
      test('retorna occurrence existente', () async {
        await repository.create(buildOccurrence());
        final result = await repository.getById('occ-001');

        expect(result, isNotNull);
        expect(result!.id, equals('occ-001'));
        expect(result.typeCode, equals('FARO_VEICULO'));
      });

      test('retorna null se não existe', () async {
        final result = await repository.getById('inexistente');
        expect(result, isNull);
      });

      test('retorna null se soft-deleted', () async {
        await repository.create(buildOccurrence());
        await repository.softDelete('occ-001', 'user-001', 'Teste');

        final result = await repository.getById('occ-001');
        expect(result, isNull);
      });
    });

    group('update', () {
      test('atualiza campos e registra audit entry', () async {
        await repository.create(buildOccurrence());
        await repository.update('occ-001', {
          'location_address': 'Rua Nova, 200',
        });

        final snap = await fakeFirestore
            .collection('occurrences')
            .doc('occ-001')
            .get();
        final data = snap.data()!;

        expect(data['location_address'], equals('Rua Nova, 200'));
        final trail = data['audit_trail'] as List;
        expect(trail.length, greaterThan(1));
        final lastEntry = trail.last as Map;
        expect(lastEntry['action'], equals('updated'));
        expect(lastEntry['field_name'], equals('location_address'));
      });
    });

    group('softDelete', () {
      test('marca campos de deleção e registra audit', () async {
        await repository.create(buildOccurrence());
        await repository.softDelete('occ-001', 'user-001', 'Duplicada');

        final snap = await fakeFirestore
            .collection('occurrences')
            .doc('occ-001')
            .get();
        final data = snap.data()!;

        expect(data['deleted_by'], equals('user-001'));
        expect(data['delete_reason'], equals('Duplicada'));
        expect(data['deleted_at'], isNotNull);
      });
    });

    group('finalize', () {
      test('marca status finalized e salva hash', () async {
        await repository.create(buildOccurrence());
        await repository.finalize(
          id: 'occ-001',
          integrityHash: 'abc123hash',
          finalReport: 'Droga localizada no painel',
          results: [OccurrenceResult.drugSeized],
          details: {'drug_type': 'cocaína', 'drug_weight': '50g'},
        );

        final snap = await fakeFirestore
            .collection('occurrences')
            .doc('occ-001')
            .get();
        final data = snap.data()!;

        expect(data['status'], equals('finalized'));
        expect(data['integrity_hash'], equals('abc123hash'));
        expect(data['final_report'], equals('Droga localizada no painel'));
        expect(data['results'], contains('drug_seized'));
        expect(data['details']['drug_type'], equals('cocaína'));
      });
    });

    group('recordPdfAccess', () {
      test('registra acesso ao PDF no documento', () async {
        await repository.create(buildOccurrence());
        await repository.recordPdfAccess(
          id: 'occ-001',
          action: 'pdf_previewed',
          pdfUrl: 'https://storage.test/pdf_final.pdf',
        );

        final snap = await fakeFirestore
            .collection('occurrences')
            .doc('occ-001')
            .get();
        final data = snap.data()!;
        final accessLog = data['pdf_access_log'] as List;
        final auditTrail = data['audit_trail'] as List;

        expect(accessLog, hasLength(1));
        expect(accessLog.first['action'], equals('pdf_previewed'));
        expect(accessLog.first['pdf_url'], contains('pdf_final.pdf'));
        expect(accessLog.first['ip'], equals('client-unavailable'));
        expect(auditTrail.last['action'], equals('pdf_previewed'));
      });
    });

    group('findOpen', () {
      test('retorna ocorrência in_progress do cão', () async {
        await repository.create(buildOccurrence());
        final result = await repository.findOpen('dog-001');

        expect(result, isNotNull);
        expect(result!.status, equals(OccurrenceStatus.inProgress));
      });

      test('retorna null se não há aberta', () async {
        await repository.create(
          buildOccurrence(status: OccurrenceStatus.finalized),
        );
        final result = await repository.findOpen('dog-001');

        expect(result, isNull);
      });

      test('retorna null para outro cão', () async {
        await repository.create(buildOccurrence());
        final result = await repository.findOpen('dog-999');

        expect(result, isNull);
      });

      test('ignora soft-deleted', () async {
        await repository.create(buildOccurrence());
        await repository.softDelete('occ-001', 'user-001', 'Teste');

        final result = await repository.findOpen('dog-001');
        expect(result, isNull);
      });
    });
  });
}
