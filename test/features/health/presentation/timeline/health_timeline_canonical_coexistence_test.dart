import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/data/coexistence/timeline/coexistence_health_timeline_source.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_query.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_source.dart';

void main() {
  group('CoexistenceHealthTimelineSource canonical logs integration', () {
    late FakeFirebaseFirestore firestore;

    setUp(() {
      firestore = FakeFirebaseFirestore();
    });

    test('refeição planejada e alimentação avulsa canônicas aparecem no histórico de coexistência com semântica explícita', () async {
      final mealLogPath = 'dogs/dog-a/meal_logs';

      // 1. Refeição Planejada (consumo nulo, oferecido 125g, aceitou tudo/full)
      await firestore.collection(mealLogPath).doc('meal-planned').set({
        'fed_at': Timestamp.fromDate(DateTime.utc(2026, 8, 3, 12, 0)),
        'offered_grams': 125,
        'consumed_grams': null,
        'acceptance': 'full',
        'schema_version': 1,
        'revision': 1,
        'recorded_by': {
          'uid': 'user-1',
          'name': 'Geraldo',
          'internal_role': 'vet',
        },
        'plan_id': 'plan-1',
        'planned_meal_id': 'planned-1',
        'meal_occurrence_id': 'occ-1',
      });

      // 2. Alimentação Avulsa (consumo medido 130g, oferecido 150g, parcial)
      await firestore.collection(mealLogPath).doc('meal-adhoc').set({
        'fed_at': Timestamp.fromDate(DateTime.utc(2026, 8, 3, 14, 0)),
        'offered_grams': 150,
        'consumed_grams': 130,
        'acceptance': 'partial',
        'schema_version': 1,
        'revision': 1,
        'recorded_by': {
          'uid': 'user-1',
          'name': 'Geraldo',
          'internal_role': 'vet',
        },
      });

      final source = CoexistenceHealthTimelineSourceFactory.forFirestore(
        firestore: firestore,
      );

      // When: load page for dog-a with no type filter (meaning "Todos")
      final queryAll = HealthTimelineQuery(dogId: 'dog-a');
      final pageAll = await source.loadPage(queryAll);

      // Then: both should appear
      expect(pageAll.items, hasLength(2));

      // Verificando ordenação e semântica exata
      final first = pageAll.items[0];
      final second = pageAll.items[1];

      expect(first.id, 'meal_logs:meal-adhoc');
      expect(first.occurredAt.toUtc(), DateTime.utc(2026, 8, 3, 14, 0));
      expect(first.type.known, HealthTimelineType.meal);
      expect(first.title, 'Alimentação registrada');
      expect(first.subtitle, '130 g consumidos'); // Consumo medido

      expect(second.id, 'meal_logs:meal-planned');
      expect(second.occurredAt.toUtc(), DateTime.utc(2026, 8, 3, 12, 0));
      expect(second.type.known, HealthTimelineType.meal);
      expect(second.title, 'Alimentação registrada');
      expect(second.subtitle, '125 g oferecidos · consumo não informado'); // Consumo não informado

      // When: filtering by Nutrição (meal)
      final queryMeal = HealthTimelineQuery(
        dogId: 'dog-a',
        types: {HealthTimelineType.meal},
      );
      final pageMeal = await source.loadPage(queryMeal);
      expect(pageMeal.items, hasLength(2));
    });

    test('variação semântica de quantidade de refeições', () async {
      final mealLogPath = 'dogs/dog-b/meal_logs';

      // 1. Consumo zero medido
      await firestore.collection(mealLogPath).doc('meal-zero').set({
        'fed_at': Timestamp.fromDate(DateTime.utc(2026, 8, 3, 10, 0)),
        'offered_grams': 100,
        'consumed_grams': 0,
        'acceptance': 'refused',
        'schema_version': 1,
        'revision': 1,
        'recorded_by': {'uid': 'u1', 'name': 'Vet'},
      });

      // 2. Ambos ausentes (sem offered nem consumed)
      await firestore.collection(mealLogPath).doc('meal-no-qty').set({
        'fed_at': Timestamp.fromDate(DateTime.utc(2026, 8, 3, 9, 0)),
        'acceptance': 'unknown',
        'schema_version': 1,
        'revision': 1,
        'recorded_by': {'uid': 'u1', 'name': 'Vet'},
      });

      // 3. Quantidade decimal
      await firestore.collection(mealLogPath).doc('meal-decimal').set({
        'fed_at': Timestamp.fromDate(DateTime.utc(2026, 8, 3, 11, 0)),
        'consumed_grams': 130.5,
        'schema_version': 1,
        'revision': 1,
        'recorded_by': {'uid': 'u1', 'name': 'Vet'},
      });

      final source = CoexistenceHealthTimelineSourceFactory.forFirestore(
        firestore: firestore,
      );

      final page = await source.loadPage(HealthTimelineQuery(dogId: 'dog-b'));
      expect(page.items, hasLength(3));

      expect(page.items[0].subtitle, '130,5 g consumidos');
      expect(page.items[1].subtitle, '0 g consumidos');
      expect(page.items[2].subtitle, 'Consumo não informado');
    });

    test('coexistência legada e canônica com prova rigorosa de precedência canônica', () async {
      final mealLogPath = 'dogs/dog-a/meal_logs';
      final feedingEventsPath = 'dogs/dog-a/feeding_events';

      // 1. Refeição planejada canônica
      await firestore.collection(mealLogPath).doc('meal-planned').set({
        'fed_at': Timestamp.fromDate(DateTime.utc(2026, 8, 3, 12, 0)),
        'offered_grams': 125,
        'consumed_grams': null,
        'acceptance': 'full',
        'schema_version': 1,
        'revision': 1,
        'recorded_by': {'uid': 'user-1', 'name': 'Geraldo'},
        'plan_id': 'plan-1',
        'planned_meal_id': 'planned-1',
        'meal_occurrence_id': 'occ-1',
      });

      // 2. Alimentação avulsa canônica
      await firestore.collection(mealLogPath).doc('meal-adhoc').set({
        'fed_at': Timestamp.fromDate(DateTime.utc(2026, 8, 3, 14, 0)),
        'offered_grams': 150,
        'consumed_grams': 130,
        'acceptance': 'partial',
        'schema_version': 1,
        'revision': 1,
        'recorded_by': {'uid': 'user-1', 'name': 'Geraldo'},
      });

      // 3. Entrada legada exclusiva (continua aparecendo)
      await firestore.collection(feedingEventsPath).doc('legacy-feeding-only').set({
        'fed_at': Timestamp.fromDate(DateTime.utc(2026, 8, 3, 10, 0)),
        'amount_grams': 100,
      });

      // 4. Canônico equivalente ao legado com dados divergentes (legacy_id correspondente)
      // Entrada legada:
      await firestore.collection(feedingEventsPath).doc('legacy-migrated').set({
        'fed_at': Timestamp.fromDate(DateTime.utc(2026, 8, 3, 8, 0)),
        'amount_grams': 200,
      });
      // Documento canônico correspondente (oferecido 200, consumido 180):
      await firestore.collection(mealLogPath).doc('canonical-migrated').set({
        'fed_at': Timestamp.fromDate(DateTime.utc(2026, 8, 3, 8, 0)),
        'offered_grams': 200,
        'consumed_grams': 180,
        'acceptance': 'partial',
        'schema_version': 1,
        'revision': 1,
        'recorded_by': {'uid': 'user-1', 'name': 'Geraldo'},
        'legacy_id': 'legacy-migrated',
        'legacy_source': 'feeding_events',
      });

      // 5. Cão diferente
      await firestore.collection('dogs/dog-other/meal_logs').doc('meal-other-dog').set({
        'fed_at': Timestamp.fromDate(DateTime.utc(2026, 8, 3, 15, 0)),
        'offered_grams': 180,
        'schema_version': 1,
        'revision': 1,
        'recorded_by': {'uid': 'user-1', 'name': 'Geraldo'},
      });

      // 6. Timestamp UTC recente
      await firestore.collection(mealLogPath).doc('meal-today-sp').set({
        'fed_at': Timestamp.fromDate(DateTime.utc(2026, 8, 3, 23, 30)),
        'offered_grams': 110,
        'consumed_grams': 110,
        'schema_version': 1,
        'revision': 1,
        'recorded_by': {'uid': 'user-1', 'name': 'Geraldo'},
      });

      final source = CoexistenceHealthTimelineSourceFactory.forFirestore(
        firestore: firestore,
      );

      final queryAll = HealthTimelineQuery(dogId: 'dog-a');
      final pageAll = await source.loadPage(queryAll);

      // Comprova deduplicação (5 itens e não 6)
      expect(pageAll.items, hasLength(5));

      // Comprova a precedência do canônico sobre o legado!
      final deduplicatedItem = pageAll.items[4];
      expect(deduplicatedItem.id, 'feeding:legacy-migrated');
      expect(deduplicatedItem.subtitle, '180 g consumidos'); // Prova que os dados canônicos (180g) venceram os 200g legados!
      expect(deduplicatedItem.traceability?.sourceCollection, 'dogs/{dogId}/meal_logs'); // Prova origem canônica!
      expect(deduplicatedItem.detailReference?.sourceType, 'meal_logs');

      // Prova exclusão de cão diferente
      expect(pageAll.items.any((e) => e.id.contains('meal-other-dog')), isFalse);
    });

    test('suplementos canônicos aparecem na timeline de coexistência com suporte a filtros e deduplicação', () async {
      final suppLogPath = 'dogs/dog-a/supplement_logs';

      await firestore.collection(suppLogPath).doc('supp-1').set({
        'administered_at': Timestamp.fromDate(DateTime.utc(2026, 8, 3, 16, 0)),
        'supplement_name': 'Vitamina C',
        'dose': 2,
        'unit': 'comprimidos',
        'schema_version': 1,
        'revision': 1,
        'recorded_by': {'uid': 'u1', 'name': 'Vet'},
      });

      final source = CoexistenceHealthTimelineSourceFactory.forFirestore(
        firestore: firestore,
      );

      // 1. Aparece em Todos
      final pageAll = await source.loadPage(HealthTimelineQuery(dogId: 'dog-a'));
      expect(pageAll.items.any((e) => e.title == 'Vitamina C'), isTrue);

      final item = pageAll.items.firstWhere((e) => e.title == 'Vitamina C');
      expect(item.subtitle, '2 comprimidos');
      expect(item.type.known, HealthTimelineType.supplement);

      // 2. Aparece no filtro de Suplementos
      final pageSupp = await source.loadPage(HealthTimelineQuery(
        dogId: 'dog-a',
        types: {HealthTimelineType.supplement},
      ));
      expect(pageSupp.items, hasLength(1));

      // 3. Excluído do filtro exclusivo de refeições (Nutrição/meal)
      final pageMeal = await source.loadPage(HealthTimelineQuery(
        dogId: 'dog-a',
        types: {HealthTimelineType.meal},
      ));
      expect(pageMeal.items.any((e) => e.title == 'Vitamina C'), isFalse);
    });

    test('parser inválido continua fail-closed', () async {
      final mealLogPath = 'dogs/dog-a/meal_logs';

      // Documento sem fed_at (campo obrigatório)
      await firestore.collection(mealLogPath).doc('meal-invalid').set({
        'offered_grams': 125,
        'schema_version': 1,
        'revision': 1,
        'recorded_by': {'uid': 'u1', 'name': 'Vet'},
      });

      final source = CoexistenceHealthTimelineSourceFactory.forFirestore(
        firestore: firestore,
      );

      expect(
        () => source.loadPage(HealthTimelineQuery(dogId: 'dog-a')),
        throwsA(isA<HealthTimelineSourceException>()),
      );
    });

    test('campo quantitativo inválido aciona fail-closed', () async {
      final mealLogPath = 'dogs/dog-c/meal_logs';

      // consumed_grams como string inválida
      await firestore.collection(mealLogPath).doc('meal-bad-qty').set({
        'fed_at': Timestamp.fromDate(DateTime.utc(2026, 8, 3, 10, 0)),
        'consumed_grams': 'cem_gramas',
        'schema_version': 1,
        'revision': 1,
        'recorded_by': {'uid': 'u1', 'name': 'Vet'},
      });

      final source = CoexistenceHealthTimelineSourceFactory.forFirestore(
        firestore: firestore,
      );

      expect(
        () => source.loadPage(HealthTimelineQuery(dogId: 'dog-c')),
        throwsA(isA<HealthTimelineSourceException>()),
      );
    });

    test('prova de fiação no build padrão do app (CoexistenceHealthTimelineSourceFactory.forFirestore)', () async {
      // Prova que a factory padrão utilizada pelo HealthV1EntryScreen constrói os leitores canônicos
      final source = CoexistenceHealthTimelineSourceFactory.forFirestore(
        firestore: firestore,
      );

      await firestore.collection('dogs/dog-wire/meal_logs').doc('meal-1').set({
        'fed_at': Timestamp.fromDate(DateTime.utc(2026, 8, 3, 10, 0)),
        'consumed_grams': 100,
        'schema_version': 1,
        'revision': 1,
        'recorded_by': {'uid': 'u1', 'name': 'Vet'},
      });

      final page = await source.loadPage(HealthTimelineQuery(dogId: 'dog-wire'));
      expect(page.items, hasLength(1));
      expect(page.items.single.id, 'meal_logs:meal-1');
    });
  });
}
