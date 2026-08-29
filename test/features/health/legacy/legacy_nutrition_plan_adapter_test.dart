import 'package:canil_gcm/features/health/domain/legacy_nutrition_views.dart';
import 'package:canil_gcm/features/health/domain/nutrition_plan.dart';
import 'package:canil_gcm/features/health/legacy/legacy_health_adapters.dart';
import 'package:canil_gcm/features/health/legacy/legacy_nutrition_plan_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const adapter = LegacyNutritionPlanAdapter();

  group('LegacyNutritionPlanAdapter', () {
    test('produz LegacyNutritionPlanView — NÃO NutritionPlan', () {
      final result = adapter.parse(
        sourceId: 'presc-1',
        dogId: 'dog-1',
        data: {
          'food_type': 'Ração',
          'amount_grams_per_day': 500,
          'meals_per_day': 2,
          'vigent_from': '2026-01-01T00:00:00Z',
          'vigent_until': '2026-12-31T00:00:00Z',
        },
      );
      expect(result.hasValue, isTrue);
      expect(result.value, isA<LegacyNutritionPlanView>());
      expect(result.value, isNot(isA<NutritionPlan>()));
      final view = result.value!;
      expect(view.mealScheduleUnavailable, isTrue);
      expect(view.vigentFrom, DateTime.parse('2026-01-01T00:00:00Z'));
      expect(view.compatibilityNote, contains('not_canonical'));
      expect(
        result.issues.any((i) => i.code == 'meal_schedule_unavailable'),
        isTrue,
      );
    });

    test('não fabrica mealSchedule nem status canônico persistido', () {
      final result = adapter.parse(
        sourceId: 'presc-2',
        dogId: 'dog-1',
        data: {
          'food_type': 'Ração',
          'amount_grams_per_day': 400,
          'meals_per_day': 2,
          'vigent_from': '2026-01-01T00:00:00Z',
          'status': 'active',
        },
      );
      final view = result.value!;
      expect(view.mealScheduleUnavailable, isTrue);
      expect(view.rawStatus, 'active'); // bruto, não NutritionPlanStatus
    });

    test('amount inválido → issue explícita', () {
      final result = adapter.parse(
        sourceId: 'presc-3',
        dogId: 'dog-1',
        data: {
          'food_type': 'Ração',
          'amount_grams_per_day': 0,
          'meals_per_day': 1,
          'vigent_from': '2026-01-01T00:00:00Z',
        },
      );
      expect(result.state, LegacyParseState.failure);
      expect(
        result.issues.any((i) => i.field == 'amount_grams_per_day'),
        isTrue,
      );
    });
  });
}
