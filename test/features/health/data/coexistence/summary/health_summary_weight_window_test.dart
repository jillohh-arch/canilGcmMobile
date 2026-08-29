import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/dogs/data/weight_history_service.dart';
import 'package:canil_gcm/features/health/data/coexistence/summary/health_summary_weight_reader.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_section_status.dart';

/// WEIGHT-01E-C1.2 — a policy do Summary precisa observar a coleção COMPLETA.
///
/// Antes do C1.2 a leitura era `orderBy(measured_at desc).limit(trendLimit)`,
/// então um bloqueador fora dos `trendLimit` documentos mais recentes ficava
/// invisível e o Summary reportava um peso atual que o `WeightHistoryService`
/// recusaria. Estes testes atravessam deliberadamente essa janela — algo que
/// nenhuma fixture do C1 fazia (todas tinham no máximo 2 documentos).
void main() {
  const dogId = 'dog-apolo';
  final limit = HealthSummaryWeightReader.trendLimit;

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

  /// `trendLimit` documentos válidos recentes, todos posteriores a [oldest].
  ///
  /// `entityId` com prefixo ordenado (`recent-00`…) para que a ordem de
  /// inserção/ordenação implícita não coincida com a decisão canônica.
  Future<void> seedRecentValid(FakeFirebaseFirestore firestore) async {
    for (var i = 0; i < limit; i++) {
      await col(firestore)
          .doc('recent-${i.toString().padLeft(2, '0')}')
          .set(
            v1(
              30.0 + i * 0.1,
              DateTime.utc(2026, 8, 6, 10).add(Duration(days: i)),
            ),
          );
    }
  }

  /// Documento antigo: fora da antiga janela `limit(trendLimit)` DESC.
  final outsideWindow = DateTime.utc(2020, 1, 1);

  Future<HealthSummarySectionStatus> summaryStatus(
    FakeFirebaseFirestore firestore,
  ) async {
    final section = await HealthSummaryWeightReader(
      firestore: firestore,
    ).readCurrent(dogId);
    return section.status;
  }

  test('preflight: fixture realmente excede a antiga janela', () async {
    final firestore = FakeFirebaseFirestore();
    await seedRecentValid(firestore);
    await col(firestore).doc('old-extra').set(v1(25.0, outsideWindow));

    final all = await col(firestore).get();
    expect(all.docs.length, greaterThan(limit));
  });

  test('malformed FORA da antiga janela bloqueia o current', () async {
    final firestore = FakeFirebaseFirestore();
    await seedRecentValid(firestore);
    // Malformed mais antigo: sob `limit(30)` DESC nunca seria lido.
    await col(firestore).doc('old-malformed').set({
      'weight_kg': 'nao-numerico',
      'schema_version': 1,
      'measured_at': Timestamp.fromDate(outsideWindow),
    });

    expect(
      await summaryStatus(firestore),
      HealthSummarySectionStatus.unavailable,
    );
  });

  test('unsupported FORA da antiga janela bloqueia o current', () async {
    final firestore = FakeFirebaseFirestore();
    await seedRecentValid(firestore);
    await col(firestore).doc('old-unsupported').set({
      'weight_kg': 33.3,
      'schema_version': 99,
      'measured_at': Timestamp.fromDate(outsideWindow),
    });

    expect(
      await summaryStatus(firestore),
      HealthSummarySectionStatus.unavailable,
    );
  });

  test('invalidated FORA da antiga janela NÃO bloqueia', () async {
    final firestore = FakeFirebaseFirestore();
    await seedRecentValid(firestore);
    await col(firestore).doc('old-invalidated').set({
      'weight_kg': 99.0,
      'schema_version': 2,
      'measured_at': Timestamp.fromDate(outsideWindow),
      'recorded_at': Timestamp.fromDate(outsideWindow),
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

    // Prova que não estamos tratando "qualquer doc extra" como bloqueador.
    expect(
      await summaryStatus(firestore),
      HealthSummarySectionStatus.available,
    );
  });

  test('trend recorta em trendLimit mesmo com coleção maior', () async {
    final firestore = FakeFirebaseFirestore();
    await seedRecentValid(firestore);
    // 5 válidos adicionais bem antigos → coleção = limit + 5.
    for (var i = 0; i < 5; i++) {
      await col(firestore)
          .doc('old-valid-$i')
          .set(v1(20.0 + i, outsideWindow.add(Duration(days: i))));
    }

    final reader = HealthSummaryWeightReader(firestore: firestore);
    final bundle = await reader.readBundle(dogId);

    final all = await col(firestore).get();
    expect(all.docs.length, limit + 5);
    // Coleção completa analisada, porém tendência limitada.
    expect(bundle.trend.value!.points.length, limit);
  });

  test('trend permanece em ordem cronológica ascendente', () async {
    final firestore = FakeFirebaseFirestore();
    await seedRecentValid(firestore);
    for (var i = 0; i < 3; i++) {
      await col(firestore)
          .doc('old-valid-$i')
          .set(v1(20.0 + i, outsideWindow.add(Duration(days: i))));
    }

    final bundle = await HealthSummaryWeightReader(
      firestore: firestore,
    ).readBundle(dogId);
    final points = bundle.trend.value!.points;

    for (var i = 1; i < points.length; i++) {
      expect(
        points[i - 1].at.isAfter(points[i].at),
        isFalse,
        reason: 'série de tendência deve ser ascendente',
      );
    }
    // Os mais recentes são preservados: o último ponto é o mais novo válido.
    // `isAtSameMomentAs` porque o parser devolve DateTime local e o `==` de
    // DateTime também compara a flag `isUtc`.
    expect(
      points.last.at.isAtSameMomentAs(
        DateTime.utc(2026, 8, 6, 10).add(Duration(days: limit - 1)),
      ),
      isTrue,
    );
  });

  test('current além da janela: os dois readers convergem', () async {
    final firestore = FakeFirebaseFirestore();
    await seedRecentValid(firestore);
    await col(firestore).doc('old-malformed').set({
      'weight_kg': 'nao-numerico',
      'schema_version': 1,
      'measured_at': Timestamp.fromDate(outsideWindow),
    });

    // Summary bloqueia...
    expect(
      await summaryStatus(firestore),
      HealthSummarySectionStatus.unavailable,
    );
    // ...e o service também. Paridade preservada fora da janela.
    await expectLater(
      WeightHistoryService(firestore: firestore).getLatest(dogId),
      throwsA(isA<WeightHistoryReadException>()),
    );
  });

  test('sem bloqueador: current é o válido mais recente da coleção', () async {
    final firestore = FakeFirebaseFirestore();
    await seedRecentValid(firestore);
    await col(firestore).doc('old-valid').set(v1(20.0, outsideWindow));

    final section = await HealthSummaryWeightReader(
      firestore: firestore,
    ).readCurrent(dogId);
    final expected = 30.0 + (limit - 1) * 0.1;

    expect(section.status, HealthSummarySectionStatus.available);
    expect(section.value!.weightKg, closeTo(expected, 0.0001));

    final latest = await WeightHistoryService(
      firestore: firestore,
    ).getLatest(dogId);
    expect(latest!.weightKg, closeTo(expected, 0.0001));
  });
}
