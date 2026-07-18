import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/nutrition_document_parser.dart';
import 'package:canil_gcm/features/health/domain/nutrition_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final recordedBy = {'uid': 'u1', 'name': 'Admin', 'internal_role': 'admin'};

  group('NutritionPlanDocumentParser', () {
    test('parse canônico completo', () {
      final plan = NutritionPlanDocumentParser.parse(
        id: 'p1',
        dogId: 'dog-1',
        data: {
          'food_type': 'Ração',
          'amount_grams_per_day': 600,
          'meals_per_day': 2,
          'valid_from': '2026-07-01T00:00:00Z',
          'timezone': 'America/Sao_Paulo',
          'status': 'active',
          'recorded_by': recordedBy,
          'schema_version': 1,
          'revision': 1,
          'meal_schedule': [
            {
              'id': 'am',
              'period': 'morning',
              'scheduled_time': '07:00',
              'target_grams': 300,
            },
            {
              'id': 'pm',
              'period': 'night',
              'scheduled_time': '19:00',
              'target_grams': 300,
            },
          ],
        },
      );
      expect(plan.status, NutritionPlanStatus.active);
      expect(plan.mealSchedule, hasLength(2));
      expect(plan.diagnoseCoherence().isFullyCoherent, isTrue);
    });

    test('falha sem food_type', () {
      expect(
        () => NutritionPlanDocumentParser.parse(
          id: 'p1',
          dogId: 'dog-1',
          data: {
            'amount_grams_per_day': 100,
            'meals_per_day': 1,
            'valid_from': '2026-07-01T00:00:00Z',
            'status': 'active',
            'recorded_by': recordedBy,
            'schema_version': 1,
            'revision': 1,
          },
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('revision < 1 rejeitada', () {
      expect(
        () => NutritionPlanDocumentParser.parse(
          id: 'p1',
          dogId: 'dog-1',
          data: {
            'food_type': 'Ração',
            'amount_grams_per_day': 100,
            'meals_per_day': 1,
            'valid_from': '2026-07-01T00:00:00Z',
            'status': 'active',
            'recorded_by': recordedBy,
            'schema_version': 1,
            'revision': 0,
          },
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('timestamp inválido rejeitado', () {
      expect(
        () => NutritionPlanDocumentParser.parse(
          id: 'p1',
          dogId: 'dog-1',
          data: {
            'food_type': 'Ração',
            'amount_grams_per_day': 100,
            'meals_per_day': 1,
            'valid_from': 'not-a-date',
            'status': 'active',
            'recorded_by': recordedBy,
            'schema_version': 1,
            'revision': 1,
          },
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('status wire desconhecido rejeitado (não vira active)', () {
      expect(
        () => NutritionPlanDocumentParser.parse(
          id: 'p1',
          dogId: 'dog-1',
          data: {
            'food_type': 'Ração',
            'amount_grams_per_day': 100,
            'meals_per_day': 1,
            'valid_from': '2026-07-01T00:00:00Z',
            'status': 'scheduled',
            'recorded_by': recordedBy,
            'schema_version': 1,
            'revision': 1,
          },
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('slot ids duplicados rejeitados', () {
      expect(
        () => NutritionPlanDocumentParser.parse(
          id: 'p1',
          dogId: 'dog-1',
          data: {
            'food_type': 'Ração',
            'amount_grams_per_day': 200,
            'meals_per_day': 2,
            'valid_from': '2026-07-01T00:00:00Z',
            'status': 'active',
            'recorded_by': recordedBy,
            'schema_version': 1,
            'revision': 1,
            'meal_schedule': [
              {
                'id': 'dup',
                'period': 'morning',
                'scheduled_time': '07:00',
                'target_grams': 100,
              },
              {
                'id': 'dup',
                'period': 'night',
                'scheduled_time': '19:00',
                'target_grams': 100,
              },
            ],
          },
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('meal_schedule malformado (não-list) rejeitado', () {
      expect(
        () => NutritionPlanDocumentParser.parse(
          id: 'p1',
          dogId: 'dog-1',
          data: {
            'food_type': 'Ração',
            'amount_grams_per_day': 100,
            'meals_per_day': 1,
            'valid_from': '2026-07-01T00:00:00Z',
            'status': 'active',
            'recorded_by': recordedBy,
            'schema_version': 1,
            'revision': 1,
            'meal_schedule': 'not-a-list',
          },
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });
  });

  group('MealLogDocumentParser', () {
    test('parse canônico avulso', () {
      final meal = MealLogDocumentParser.parse(
        id: 'm1',
        dogId: 'dog-1',
        data: {
          'period': 'morning',
          'offered_grams': 200,
          'acceptance': 'full',
          'fed_at': '2026-07-14T08:00:00Z',
          'recorded_by': recordedBy,
          'schema_version': 1,
          'revision': 1,
        },
      );
      expect(meal.offeredGrams, 200);
      expect(meal.isAdHoc, isTrue);
    });

    test('parse planejado com occurrence', () {
      final meal = MealLogDocumentParser.parse(
        id: 'm1',
        dogId: 'dog-1',
        data: {
          'period': 'morning',
          'offered_grams': 300,
          'acceptance': 'partial',
          'consumed_grams': 150,
          'fed_at': '2026-07-14T08:00:00Z',
          'plan_id': 'p1',
          'planned_meal_id': 'am',
          'meal_occurrence_id': 'occ-1',
          'prescription_amount_at_time': 300,
          'recorded_by': recordedBy,
          'schema_version': 1,
          'revision': 1,
        },
      );
      expect(meal.isPlanned, isTrue);
      expect(meal.prescriptionAmountAtTime, 300);
    });

    test('offered ausente rejeitado', () {
      expect(
        () => MealLogDocumentParser.parse(
          id: 'm1',
          dogId: 'dog-1',
          data: {
            'period': 'morning',
            'acceptance': 'full',
            'fed_at': '2026-07-14T08:00:00Z',
            'recorded_by': recordedBy,
            'schema_version': 1,
            'revision': 1,
          },
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('period unknown preservado (política Health v1)', () {
      final meal = MealLogDocumentParser.parse(
        id: 'm1',
        dogId: 'dog-1',
        data: {
          'period': 'brunch',
          'offered_grams': 100,
          'acceptance': 'unknown',
          'fed_at': '2026-07-14T08:00:00Z',
          'recorded_by': recordedBy,
          'schema_version': 1,
          'revision': 1,
        },
      );
      expect(meal.period.isUnknown, isTrue);
      expect(meal.period.raw, 'brunch');
    });
  });

  group('SupplementLogDocumentParser', () {
    test('dose inválida rejeitada', () {
      expect(
        () => SupplementLogDocumentParser.parse(
          id: 's1',
          dogId: 'dog-1',
          data: {
            'supplement_name': 'X',
            'dose': 0,
            'unit': 'mg',
            'administered_at': '2026-07-14T08:00:00Z',
            'recorded_by': recordedBy,
            'schema_version': 1,
            'revision': 1,
          },
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('unit desconhecida rejeitada (não inventa other)', () {
      expect(
        () => SupplementLogDocumentParser.parse(
          id: 's1',
          dogId: 'dog-1',
          data: {
            'supplement_name': 'X',
            'dose': 10,
            'unit': 'pílula',
            'administered_at': '2026-07-14T08:00:00Z',
            'recorded_by': recordedBy,
            'schema_version': 1,
            'revision': 1,
          },
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });
  });
}
