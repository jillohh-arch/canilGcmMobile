import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/data/coexistence/summary/health_summary_recent_records_reader.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_block_models.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_section_status.dart';

void main() {
  final apoloSecond = DateTime.utc(2026, 8, 6, 10, 32);
  final later = DateTime.utc(2026, 8, 10, 10);

  CollectionReference<Map<String, dynamic>> weights(
    FakeFirebaseFirestore firestore,
  ) => firestore.collection('dogs').doc('dog-apolo').collection('weight_records');

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

  Map<String, dynamic> invalidatedV2(DateTime measuredAt) => {
    'dog_id': 'dog-apolo',
    'weight_kg': 40.0,
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

  Future<HealthSummarySectionData<HealthSummaryRecentRecordsView>> read(
    FakeFirebaseFirestore firestore,
  ) => HealthSummaryRecentRecordsReader(firestore: firestore).read('dog-apolo');

  List<String> weightItemIds(
    HealthSummarySectionData<HealthSummaryRecentRecordsView> section,
  ) => section.value!.items
      .where((item) => item.type == 'weight')
      .map((item) => item.id)
      .toList();

  test('somente valid vira card; invalidated excluído', () async {
    final firestore = FakeFirebaseFirestore();
    await weights(firestore).doc('ok').set(v1(33.3, apoloSecond));
    await weights(firestore).doc('inv').set(invalidatedV2(later));

    final section = await read(firestore);
    expect(section.status, HealthSummarySectionStatus.available);
    expect(weightItemIds(section), ['wt-ok']);
  });

  test('malformed antes do primeiro valid → bloco unavailable', () async {
    final firestore = FakeFirebaseFirestore();
    await weights(firestore).doc('ok').set(v1(33.3, apoloSecond));
    await weights(firestore).doc('bad').set({
      'dog_id': 'dog-apolo',
      'weight_kg': 'x',
      'schema_version': 1,
      'measured_at': Timestamp.fromDate(later),
    });

    final section = await read(firestore);
    expect(section.status, HealthSummarySectionStatus.unavailable);
  });

  test('sem fallback silencioso para "mais recente" quando topo ilegível', () async {
    final firestore = FakeFirebaseFirestore();
    // DESC: unsupported (later) no topo, valid (apoloSecond) abaixo.
    await weights(firestore).doc('future').set({
      'dog_id': 'dog-apolo',
      'weight_kg': 33.3,
      'schema_version': 7,
      'measured_at': Timestamp.fromDate(later),
    });
    await weights(firestore).doc('ok').set(v1(33.3, apoloSecond));

    final section = await read(firestore);
    expect(section.status, HealthSummarySectionStatus.unavailable);
  });
}
