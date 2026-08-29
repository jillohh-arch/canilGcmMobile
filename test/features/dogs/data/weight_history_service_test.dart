import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/dogs/data/weight_history_service.dart';
import 'package:canil_gcm/features/dogs/domain/weight_record.dart';

void main() {
  test('reads only canonical weight_records in measured_at order', () async {
    final firestore = FakeFirebaseFirestore();
    final canonical = firestore
        .collection('dogs')
        .doc('dog-1')
        .collection('weight_records');
    await canonical.doc('older').set({
      'weight_kg': 24.2,
      'schema_version': 1,
      'measured_at': Timestamp.fromDate(DateTime.utc(2026, 8, 1)),
      'recorded_by': {
        'uid': 'user-1',
        'name': 'Ana',
        'internal_role': 'condutor',
      },
      'context': 'routine',
      'notes': 'após treino',
    });
    await canonical.doc('newer').set({
      'weight_kg': 24.8,
      'schema_version': 1,
      'measured_at': Timestamp.fromDate(DateTime.utc(2026, 8, 2)),
      'recorded_by': {'uid': 'user-2', 'name': 'Bia', 'internal_role': 'admin'},
    });
    await firestore
        .collection('dogs')
        .doc('dog-1')
        .collection('weight_history')
        .doc('legacy')
        .set({'weight': 99});

    final records = await WeightHistoryService(
      firestore: firestore,
    ).getHistory('dog-1');

    expect(records.map((record) => record.id), ['newer', 'older']);
    expect(records.first.weightKg, 24.8);
    expect(records.last.recordedBy?.name, 'Ana');
    expect(records.last.contextLabel, 'Rotina');
    expect(records, hasLength(2));
  });

  test('latest, stats and empty state derive from canonical records', () async {
    final firestore = FakeFirebaseFirestore();
    final collection = firestore
        .collection('dogs')
        .doc('dog-1')
        .collection('weight_records');
    for (final entry in [(23.0, 1), (25.0, 2), (24.0, 3)]) {
      await collection.add({
        'weight_kg': entry.$1,
        'schema_version': 1,
        'measured_at': Timestamp.fromDate(DateTime.utc(2026, 8, entry.$2)),
        'recorded_by': {
          'uid': 'user-1',
          'name': 'Ana',
          'internal_role': 'condutor',
        },
      });
    }
    final service = WeightHistoryService(firestore: firestore);

    expect((await service.getLatest('dog-1'))!.weightKg, 24);
    expect(await service.getStats('dog-1'), {
      'min': 23.0,
      'max': 25.0,
      'avg': 24.0,
    });
    expect(await service.getHistory('missing'), isEmpty);
  });

  test('rejects a non-canonical recorded_by contract', () {
    expect(
      () => WeightRecord.fromJson({
        'id': 'weight-1',
        'weight_kg': 20,
        'schema_version': 1,
        'measured_at': Timestamp.now(),
        'recorded_by': {
          'uid': 'user-1',
          'name': 'Ana',
          'internal_role': 'veterinario',
        },
      }),
      throwsFormatException,
    );
  });

  test('requires schema_version 1 and tolerates unknown canonical fields', () {
    final base = {
      'id': 'weight-1',
      'weight_kg': 20,
      'measured_at': Timestamp.now(),
      'recorded_by': {
        'uid': 'user-1',
        'name': 'Ana',
        'internal_role': 'condutor',
      },
      'unknown_future_field': {'safe': true},
    };
    expect(
      () => WeightRecord.fromJson({...base, 'schema_version': 2}),
      throwsFormatException,
    );
    final record = WeightRecord.fromJson({...base, 'schema_version': 1});
    expect(record.schemaVersion, 1);
    expect(record.context, isEmpty);
    expect(record.notes, isNull);
  });

  // PRE-V2-WEIGHT-RECORDEDAT-FACADE-CORRECTIONS: esta rota NÃO parseia
  // `recorded_at`. Um documento `schema_version: 1` + `recorded_at` é
  // `hybridV1V2`/malformed para o parser canônico, então testar esse shape
  // aqui como V1 válido codificaria o oposto do contrato. A propagação real
  // do campo é coberta em
  // test/features/health/data/weight/weight_assessment_read_adapter_test.dart.
  test('v1 canônico não expõe recordedAt por esta rota', () {
    final record = WeightRecord.fromJson({
      'id': 'weight-1',
      'weight_kg': 20,
      'schema_version': 1,
      'measured_at': Timestamp.fromDate(DateTime.utc(2026, 8, 6, 10)),
      'recorded_by': {
        'uid': 'user-1',
        'name': 'Ana',
        'internal_role': 'condutor',
      },
    });

    expect(record.recordedAt, isNull);
    expect(record.measuredAt.toUtc(), DateTime.utc(2026, 8, 6, 10));
  });
}
