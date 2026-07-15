import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/nutrition_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final actor = RecordedBy(
    uid: 'u1',
    name: 'Admin',
    internalRole: 'admin',
  );
  final from = DateTime.utc(2026, 7, 14);
  final to = DateTime.utc(2026, 8, 14);

  group('NutritionPlan', () {
    test('construção válida', () {
      final plan = NutritionPlan(
        id: 'np-1',
        dogId: 'dog-1',
        foodType: 'Ração premium',
        amountGramsPerDay: 600,
        mealsPerDay: 2,
        vigentFrom: from,
        recordedBy: actor,
        status: NutritionPlanStatus.active,
        schemaVersion: 1,
      );
      expect(plan.amountPerMeal, 300);
      expect(plan.amountGramsPerDay, 600);
      expect(plan.status, NutritionPlanStatus.active);
    });

    test('amount <= 0 é rejeitado', () {
      expect(
        () => NutritionPlan(
          id: 'np-1',
          dogId: 'dog-1',
          foodType: 'Ração',
          amountGramsPerDay: 0,
          mealsPerDay: 2,
          vigentFrom: from,
          recordedBy: actor,
          status: NutritionPlanStatus.active,
          schemaVersion: 1,
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('mealsPerDay <= 0 é rejeitado', () {
      expect(
        () => NutritionPlan(
          id: 'np-1',
          dogId: 'dog-1',
          foodType: 'Ração',
          amountGramsPerDay: 500,
          mealsPerDay: 0,
          vigentFrom: from,
          recordedBy: actor,
          status: NutritionPlanStatus.active,
          schemaVersion: 1,
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('hydration negativa é rejeitada', () {
      expect(
        () => NutritionPlan(
          id: 'np-1',
          dogId: 'dog-1',
          foodType: 'Ração',
          amountGramsPerDay: 500,
          mealsPerDay: 2,
          vigentFrom: from,
          recordedBy: actor,
          status: NutritionPlanStatus.active,
          schemaVersion: 1,
          hydrationMl: -1,
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('vigent_until anterior a vigent_from é rejeitado', () {
      expect(
        () => NutritionPlan(
          id: 'np-1',
          dogId: 'dog-1',
          foodType: 'Ração',
          amountGramsPerDay: 500,
          mealsPerDay: 2,
          vigentFrom: from,
          vigentUntil: from.subtract(const Duration(days: 1)),
          recordedBy: actor,
          status: NutritionPlanStatus.active,
          schemaVersion: 1,
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('vigência válida é aceita', () {
      final plan = NutritionPlan(
        id: 'np-1',
        dogId: 'dog-1',
        foodType: 'Ração',
        amountGramsPerDay: 500,
        mealsPerDay: 2,
        vigentFrom: from,
        vigentUntil: to,
        recordedBy: actor,
        status: NutritionPlanStatus.active,
        schemaVersion: 1,
      );
      expect(plan.vigentUntil, to);
    });
  });

  group('NutritionPlanConflictPolicy', () {
    final policy = const NutritionPlanConflictPolicy();

    test('sem planos ativos não há conflito', () {
      final plans = [
        NutritionPlan(
          id: 'a',
          dogId: 'dog-1',
          foodType: 'x',
          amountGramsPerDay: 100,
          mealsPerDay: 1,
          vigentFrom: from,
          recordedBy: actor,
          status: NutritionPlanStatus.superseded,
          schemaVersion: 1,
        ),
      ];
      expect(policy.evaluate(plans), isEmpty);
    });

    test('dois planos ativos para o mesmo K9 geram conflito', () {
      final plans = [
        NutritionPlan(
          id: 'a',
          dogId: 'dog-1',
          foodType: 'x',
          amountGramsPerDay: 100,
          mealsPerDay: 1,
          vigentFrom: from,
          recordedBy: actor,
          status: NutritionPlanStatus.active,
          schemaVersion: 1,
        ),
        NutritionPlan(
          id: 'b',
          dogId: 'dog-1',
          foodType: 'y',
          amountGramsPerDay: 200,
          mealsPerDay: 2,
          vigentFrom: from.add(const Duration(days: 1)),
          recordedBy: actor,
          status: NutritionPlanStatus.active,
          schemaVersion: 1,
        ),
      ];
      final conflicts = policy.evaluate(plans);
      expect(conflicts, hasLength(1));
      expect(conflicts.single, contains('dog-1'));
    });

    test('planos ativos de K9s diferentes não conflitam', () {
      final plans = [
        NutritionPlan(
          id: 'a',
          dogId: 'dog-1',
          foodType: 'x',
          amountGramsPerDay: 100,
          mealsPerDay: 1,
          vigentFrom: from,
          recordedBy: actor,
          status: NutritionPlanStatus.active,
          schemaVersion: 1,
        ),
        NutritionPlan(
          id: 'b',
          dogId: 'dog-2',
          foodType: 'y',
          amountGramsPerDay: 200,
          mealsPerDay: 2,
          vigentFrom: from,
          recordedBy: actor,
          status: NutritionPlanStatus.active,
          schemaVersion: 1,
        ),
      ];
      expect(policy.evaluate(plans), isEmpty);
    });
  });
}