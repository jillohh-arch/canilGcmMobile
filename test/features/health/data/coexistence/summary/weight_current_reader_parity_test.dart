import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/dogs/data/weight_history_service.dart';
import 'package:canil_gcm/features/health/data/coexistence/summary/health_summary_weight_reader.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_section_status.dart';

/// WEIGHT-01E-C1 §17/§29 — os dois readers Mobile devem selecionar exatamente
/// o mesmo peso atual para a mesma coleção.
///
/// Antes do C1, `WeightHistoryService` usava `orderBy(...).limit(1)` e o summary
/// usava `sort` ASC + `last`; com empate de `measured_at` o resultado divergia e
/// dependia da ordenação implícita do Firestore. Estes testes provam que a
/// decisão agora vem da policy compartilhada, e não da ordem de origem.
void main() {
  const dogId = 'dog-apolo';
  final measured = DateTime.utc(2026, 8, 6, 10);
  final earlier = DateTime.utc(2026, 6, 17, 14);

  CollectionReference<Map<String, dynamic>> col(
    FakeFirebaseFirestore firestore,
  ) => firestore.collection('dogs').doc(dogId).collection('weight_records');

  Map<String, dynamic> v1(num weight, DateTime measuredAt) => {
    'weight_kg': weight,
    'schema_version': 1,
    'measured_at': Timestamp.fromDate(measuredAt),
    'recorded_by': const {
      'uid': 'uid-fixture',
      'name': 'Operador Fixture',
      'internal_role': 'condutor',
    },
  };

  Map<String, dynamic> malformed(DateTime measuredAt) => {
    'weight_kg': 'nao-numerico',
    'schema_version': 1,
    'measured_at': Timestamp.fromDate(measuredAt),
  };

  Map<String, dynamic> unsupported(DateTime measuredAt) => {
    'weight_kg': 33.3,
    'schema_version': 99,
    'measured_at': Timestamp.fromDate(measuredAt),
  };

  Future<double?> summaryCurrent(FakeFirebaseFirestore firestore) async {
    final section = await HealthSummaryWeightReader(
      firestore: firestore,
    ).readCurrent(dogId);
    return section.status == HealthSummarySectionStatus.available
        ? section.value!.weightKg
        : null;
  }

  Future<double?> serviceCurrent(FakeFirebaseFirestore firestore) async {
    final record = await WeightHistoryService(
      firestore: firestore,
    ).getLatest(dogId);
    return record?.weightKg;
  }

  test('empate de measured_at: ambos escolhem o entityId maior', () async {
    final firestore = FakeFirebaseFirestore();
    // Inseridos deliberadamente com o id menor por último, para que a ordem de
    // origem não coincida com a decisão canônica.
    await col(firestore).doc('idA').set(v1(32.0, measured));
    await col(firestore).doc('idB').set(v1(33.3, measured));

    expect(await serviceCurrent(firestore), 33.3);
    expect(await summaryCurrent(firestore), 33.3);
  });

  test('empate: recorded_at factual do v2 vence null do v1', () async {
    final firestore = FakeFirebaseFirestore();
    // `zzz` tem entityId maior mas sem recorded_at; o desempate de nível 2
    // precisa decidir antes do nível 3.
    await col(firestore).doc('zzz').set(v1(32.0, measured));
    await col(firestore).doc('aaa').set({
      'weight_kg': 33.3,
      'schema_version': 2,
      'measured_at': Timestamp.fromDate(measured),
      'recorded_at': Timestamp.fromDate(measured.add(const Duration(hours: 2))),
      'record_type': 'quick',
      'origin_record_type': 'quick',
      'status': 'valid',
      'revision': 1,
      'dog_id': dogId,
      'recorded_by': const {
        'uid': 'uid-fixture',
        'name': 'Operador Fixture',
        'internal_role': 'condutor',
      },
    });

    expect(await serviceCurrent(firestore), 33.3);
    expect(await summaryCurrent(firestore), 33.3);
  });

  test('malformed em qualquer posição bloqueia os dois readers', () async {
    final firestore = FakeFirebaseFirestore();
    // Válido é o mais recente; o malformed é anterior. Sob a regra posicional
    // antiga o summary devolvia 33.3.
    await col(firestore).doc('good').set(v1(33.3, measured));
    await col(firestore).doc('bad').set(malformed(earlier));

    await expectLater(
      serviceCurrent(firestore),
      throwsA(isA<WeightHistoryReadException>()),
    );
    expect(await summaryCurrent(firestore), isNull);
  });

  test('unsupported em qualquer posição bloqueia os dois readers', () async {
    final firestore = FakeFirebaseFirestore();
    await col(firestore).doc('good').set(v1(33.3, measured));
    await col(firestore).doc('future').set(unsupported(earlier));

    await expectLater(
      serviceCurrent(firestore),
      throwsA(isA<WeightHistoryReadException>()),
    );
    expect(await summaryCurrent(firestore), isNull);
  });

  test('invalidated mais recente: ambos caem no válido anterior', () async {
    final firestore = FakeFirebaseFirestore();
    await col(firestore).doc('valid').set(v1(33.3, measured));
    await col(firestore).doc('invalid').set({
      'weight_kg': 40.0,
      'schema_version': 2,
      'measured_at': Timestamp.fromDate(DateTime.utc(2026, 8, 10)),
      'recorded_at': Timestamp.fromDate(DateTime.utc(2026, 8, 10)),
      'record_type': 'quick',
      'origin_record_type': 'quick',
      'status': 'invalidated',
      'revision': 1,
      'dog_id': dogId,
      'recorded_by': const {
        'uid': 'uid-fixture',
        'name': 'Operador Fixture',
        'internal_role': 'condutor',
      },
    });

    expect(await serviceCurrent(firestore), 33.3);
    expect(await summaryCurrent(firestore), 33.3);
  });

  test('coleção vazia: nenhum reader inventa atual', () async {
    final firestore = FakeFirebaseFirestore();

    expect(await serviceCurrent(firestore), isNull);
    expect(await summaryCurrent(firestore), isNull);
  });

  test('writer v1 fiel é legível e vira atual nos dois readers', () async {
    final firestore = FakeFirebaseFirestore();
    // Shape do writer canônico: sem recorded_at, sem status, com aliases e
    // extras que o parser deve tolerar.
    await col(firestore).doc('7cJk2p').set({
      'dogId': dogId,
      'dog_id': dogId,
      'weight_kg': 33.3,
      'measured_at': Timestamp.fromDate(measured),
      'recorded_by': const {
        'uid': 'uid-fixture',
        'name': 'Operador Fixture',
        'internal_role': 'condutor',
      },
      'schema_version': 1,
      'created_at': Timestamp.fromDate(measured),
      'updated_at': Timestamp.fromDate(measured),
      'context': 'routine',
      'audit_trail': const [
        {'action': 'created', 'by': 'uid-fixture'},
      ],
    });

    expect(await serviceCurrent(firestore), 33.3);
    expect(await summaryCurrent(firestore), 33.3);
  });
}
