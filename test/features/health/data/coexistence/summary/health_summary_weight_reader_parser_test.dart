import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/data/coexistence/summary/health_summary_weight_reader.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_block_models.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_section_status.dart';

void main() {
  final apoloFirst = DateTime.utc(2026, 6, 17, 10);
  final apoloSecond = DateTime.utc(2026, 8, 6, 10, 32);
  final later = DateTime.utc(2026, 8, 10, 10);

  CollectionReference<Map<String, dynamic>> col(
    FakeFirebaseFirestore firestore,
  ) => firestore
      .collection('dogs')
      .doc('dog-apolo')
      .collection('weight_records');

  Map<String, dynamic> v1(num weight, DateTime measuredAt) => {
    'dog_id': 'dog-apolo',
    'weight_kg': weight,
    'schema_version': 1,
    'measured_at': Timestamp.fromDate(measuredAt),
    'recorded_by': const {
      'uid': 'u',
      'name': 'Ana',
      'internal_role': 'condutor',
    },
  };

  Map<String, dynamic> invalidatedV2(num weight, DateTime measuredAt) => {
    'dog_id': 'dog-apolo',
    'weight_kg': weight,
    'measured_at': Timestamp.fromDate(measuredAt),
    'recorded_at': Timestamp.fromDate(measuredAt),
    'recorded_by': const {
      'uid': 'u',
      'name': 'Bia',
      'internal_role': 'future_role',
    },
    'schema_version': 2,
    'record_type': 'quick',
    'origin_record_type': 'quick',
    'status': 'invalidated',
    'revision': 1,
  };

  Map<String, dynamic> malformed(DateTime measuredAt) => {
    'dog_id': 'dog-apolo',
    'weight_kg': 'nope',
    'measured_at': Timestamp.fromDate(measuredAt),
    'schema_version': 1,
  };

  Future<HealthSummarySectionData<HealthSummaryWeightView>> current(
    FakeFirebaseFirestore firestore,
  ) => HealthSummaryWeightReader(firestore: firestore).readCurrent('dog-apolo');

  test('peso atual = 33.3 (Apolo)', () async {
    final firestore = FakeFirebaseFirestore();
    await col(firestore).add(v1(32.0, apoloFirst));
    await col(firestore).add(v1(33.3, apoloSecond));

    final section = await current(firestore);
    expect(section.status, HealthSummarySectionStatus.available);
    expect(section.value!.weightKg, 33.3);
  });

  test(
    'invalidated mais recente é ignorado; próximo valid vira atual',
    () async {
      final firestore = FakeFirebaseFirestore();
      await col(firestore).add(v1(33.3, apoloSecond));
      await col(firestore).add(invalidatedV2(40.0, later));

      final section = await current(firestore);
      expect(section.status, HealthSummarySectionStatus.available);
      expect(section.value!.weightKg, 33.3);
    },
  );

  test(
    'malformed antes do primeiro valid → inconclusivo (unavailable)',
    () async {
      final firestore = FakeFirebaseFirestore();
      await col(firestore).add(v1(33.3, apoloSecond));
      await col(firestore).add(malformed(later));

      final section = await current(firestore);
      expect(section.status, HealthSummarySectionStatus.unavailable);
    },
  );

  // WEIGHT-01E-C1: o bloqueio passou a ser GLOBAL (paridade com a policy Web).
  // Antes, um malformed posicionado depois do primeiro candidato válido era
  // ignorado; agora a posição física não decide, e o candidato anterior não é
  // promovido silenciosamente.
  test('malformed depois do candidato válido também bloqueia', () async {
    final firestore = FakeFirebaseFirestore();
    // DESC: valid (later) vem antes; malformed (apoloFirst) vem depois.
    await col(firestore).add(v1(33.3, later));
    await col(firestore).add(malformed(apoloFirst));

    final section = await current(firestore);
    expect(section.status, HealthSummarySectionStatus.unavailable);
    expect(section.valueOrNull, isNull);
  });

  test('sem registros → notRecorded', () async {
    final firestore = FakeFirebaseFirestore();
    final section = await current(firestore);
    expect(section.status, HealthSummarySectionStatus.notRecorded);
  });
}
