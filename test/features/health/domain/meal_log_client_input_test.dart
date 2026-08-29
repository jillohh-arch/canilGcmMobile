import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/meal_log_client_input.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 7, 14, 12);

  group('D41 PlannedMealClientInput', () {
    test('aceita campos de cliente sem server-derived', () {
      final input = PlannedMealClientInput(
        dogId: 'dog-1',
        planId: 'p1',
        plannedMealId: 'slot-am',
        offeredGrams: 300,
        acceptance: MealAcceptanceWire.parse('full'),
        fedAt: now,
      );
      expect(input.planId, 'p1');
      expect(input.plannedMealId, 'slot-am');
    });

    test('validateFedAt com relógio injetado', () {
      final input = PlannedMealClientInput(
        dogId: 'dog-1',
        planId: 'p1',
        plannedMealId: 's',
        offeredGrams: 100,
        acceptance: MealAcceptanceWire.parse('unknown'),
        fedAt: now,
      );
      expect(() => input.validateFedAt(referenceNow: now), returnsNormally);
      expect(
        () => input.validateFedAt(
          referenceNow: now.subtract(const Duration(seconds: 1)),
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('server-derived fields catálogo', () {
      expect(
        PlannedMealServerDerivedFields.isServerDerivedField('period'),
        isTrue,
      );
      expect(
        PlannedMealServerDerivedFields.isServerDerivedField(
          'meal_occurrence_id',
        ),
        isTrue,
      );
      expect(
        PlannedMealServerDerivedFields.isClientAuthorityField('offered_grams'),
        isTrue,
      );
      expect(
        PlannedMealServerDerivedFields.isClientAuthorityField('period'),
        isFalse,
      );
    });
  });
}
