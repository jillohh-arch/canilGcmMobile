import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/dogs/data/weight_history_service.dart';

void main() {
  final apoloFirst = DateTime.utc(2026, 6, 17, 10);
  final apoloSecond = DateTime.utc(2026, 8, 6, 10, 32);

  CollectionReference<Map<String, dynamic>> weightRecords(
    FakeFirebaseFirestore firestore,
    String dogId,
  ) => firestore.collection('dogs').doc(dogId).collection('weight_records');

  Map<String, dynamic> canonicalV1(num weight, DateTime measuredAt) => {
    'dog_id': 'dog-apolo',
    'weight_kg': weight,
    'schema_version': 1,
    'measured_at': Timestamp.fromDate(measuredAt),
    'recorded_by': const {
      'uid': 'user-1',
      'name': 'Ana',
      'internal_role': 'condutor',
    },
    'context': 'routine',
  };

  Map<String, dynamic> quickV2(num weight, DateTime measuredAt) => {
    'dog_id': 'dog-apolo',
    'weight_kg': weight,
    'measured_at': Timestamp.fromDate(measuredAt),
    'recorded_at': Timestamp.fromDate(measuredAt),
    'recorded_by': const {
      'uid': 'user-2',
      'name': 'Bia',
      'internal_role': 'future_role',
    },
    'schema_version': 2,
    'record_type': 'quick',
    'origin_record_type': 'quick',
    'status': 'valid',
    'revision': 1,
  };

  test('Apolo 32.0 e 33.3 preservados, ordenados e sem duplicação', () async {
    final firestore = FakeFirebaseFirestore();
    final col = weightRecords(firestore, 'dog-apolo');
    await col.doc('first').set(canonicalV1(32.0, apoloFirst));
    await col.doc('second').set(canonicalV1(33.3, apoloSecond));

    final records = await WeightHistoryService(
      firestore: firestore,
    ).getHistory('dog-apolo');

    expect(records, hasLength(2));
    expect(records.map((r) => r.id), ['second', 'first']);
    expect(records.first.weightKg, 33.3);
    expect(records.last.weightKg, 32.0);
    expect(records.first.recordedBy?.name, 'Ana');
  });

  test('target v2 Quick é aceito na leitura (compatibilidade)', () async {
    final firestore = FakeFirebaseFirestore();
    final col = weightRecords(firestore, 'dog-apolo');
    await col.doc('q').set(quickV2(33.3, apoloSecond));

    final records = await WeightHistoryService(
      firestore: firestore,
    ).getHistory('dog-apolo');

    expect(records, hasLength(1));
    expect(records.single.weightKg, 33.3);
  });

  test('invalidated é excluído da lista ordinária, sem hard delete', () async {
    final firestore = FakeFirebaseFirestore();
    final col = weightRecords(firestore, 'dog-apolo');
    await col.doc('ok').set(canonicalV1(32.0, apoloFirst));
    await col.doc('inv').set({
      ...quickV2(40.0, apoloSecond),
      'status': 'invalidated',
    });

    final records = await WeightHistoryService(
      firestore: firestore,
    ).getHistory('dog-apolo');

    expect(records.map((r) => r.id), ['ok']);
    // Documento continua existindo (sem hard delete).
    final still = await col.doc('inv').get();
    expect(still.exists, isTrue);
  });

  Map<String, dynamic> legacyWeb(num weight, DateTime measuredAt) => {
    'dog_id': 'dog-apolo',
    'weight_kg': weight,
    'measured_at': Timestamp.fromDate(measuredAt),
    'measured_by': 'RA-1234',
    'performed_by': 'RA-1234',
  };

  Map<String, dynamic> legacyDogUpdate(num weight, DateTime measuredAt) => {
    'dog_id': 'dog-apolo',
    'weight_kg': weight,
    'measured_at': Timestamp.fromDate(measuredAt),
    'performed_by': 'RA-5678',
  };

  test(
    'recognized legacy Web sem recorder permanece no histórico, sem autoria',
    () async {
      final firestore = FakeFirebaseFirestore();
      final col = weightRecords(firestore, 'dog-apolo');
      await col.doc('legacyWeb').set(legacyWeb(32.0, apoloFirst));

      final records = await WeightHistoryService(
        firestore: firestore,
      ).getHistory('dog-apolo');

      expect(records, hasLength(1));
      expect(records.single.weightKg, 32.0);
      // Pesagem permanece visível, autoria factual ausente (nunca inventada).
      expect(records.single.recordedBy, isNull);
      expect(records.single.measuredBy, '');
    },
  );

  test(
    'recognized legacy dog-update sem recorder permanece no histórico',
    () async {
      final firestore = FakeFirebaseFirestore();
      final col = weightRecords(firestore, 'dog-apolo');
      await col.doc('legacyDog').set(legacyDogUpdate(31.0, apoloFirst));

      final records = await WeightHistoryService(
        firestore: firestore,
      ).getHistory('dog-apolo');

      expect(records, hasLength(1));
      expect(records.single.weightKg, 31.0);
      expect(records.single.recordedBy, isNull);
    },
  );

  test(
    'legacy sem recorder pode ser o getLatest, sem promover anterior',
    () async {
      final firestore = FakeFirebaseFirestore();
      final col = weightRecords(firestore, 'dog-apolo');
      await col.doc('canonical').set(canonicalV1(32.0, apoloFirst));
      await col.doc('legacyLatest').set(legacyWeb(33.3, apoloSecond));

      final latest = await WeightHistoryService(
        firestore: firestore,
      ).getLatest('dog-apolo');

      expect(latest, isNotNull);
      expect(latest!.weightKg, 33.3);
      expect(latest.recordedBy, isNull);
    },
  );

  test('legacy sem recorder participa de getStats (min/max/média)', () async {
    final firestore = FakeFirebaseFirestore();
    final col = weightRecords(firestore, 'dog-apolo');
    await col.doc('canonical').set(canonicalV1(30.0, apoloFirst));
    await col.doc('legacy').set(legacyWeb(40.0, apoloSecond));

    final stats = await WeightHistoryService(
      firestore: firestore,
    ).getStats('dog-apolo');

    expect(stats['min'], 30.0);
    expect(stats['max'], 40.0);
    expect(stats['avg'], 35.0);
  });

  test('malformed causa falha controlada do histórico completo', () async {
    final firestore = FakeFirebaseFirestore();
    final col = weightRecords(firestore, 'dog-apolo');
    await col.doc('ok').set(canonicalV1(32.0, apoloFirst));
    await col.doc('bad').set({
      'dog_id': 'dog-apolo',
      'weight_kg': 'x',
      'measured_at': Timestamp.fromDate(apoloSecond),
      'schema_version': 1,
    });

    await expectLater(
      WeightHistoryService(firestore: firestore).getHistory('dog-apolo'),
      throwsA(isA<WeightHistoryReadException>()),
    );
  });

  test('unsupported (schema futuro) causa falha controlada', () async {
    final firestore = FakeFirebaseFirestore();
    final col = weightRecords(firestore, 'dog-apolo');
    await col.doc('future').set({
      'dog_id': 'dog-apolo',
      'weight_kg': 33.3,
      'measured_at': Timestamp.fromDate(apoloSecond),
      'schema_version': 4,
    });

    await expectLater(
      WeightHistoryService(firestore: firestore).getHistory('dog-apolo'),
      throwsA(isA<WeightHistoryReadException>()),
    );
  });

  test('weight_history não é consultado como fonte', () async {
    final firestore = FakeFirebaseFirestore();
    await weightRecords(
      firestore,
      'dog-apolo',
    ).doc('ok').set(canonicalV1(32.0, apoloFirst));
    await firestore
        .collection('dogs')
        .doc('dog-apolo')
        .collection('weight_history')
        .doc('legacy')
        .set({'weight': 99});

    final records = await WeightHistoryService(
      firestore: firestore,
    ).getHistory('dog-apolo');

    expect(records, hasLength(1));
    expect(records.single.weightKg, 32.0);
  });
}
