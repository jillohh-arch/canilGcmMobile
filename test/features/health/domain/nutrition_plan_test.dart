import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/meal_schedule_slot.dart';
import 'package:canil_gcm/features/health/domain/nutrition_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final actor = RecordedBy(uid: 'u1', name: 'Admin', internalRole: 'admin');
  final from = DateTime.utc(2026, 7, 14);
  final to = DateTime.utc(2026, 8, 14);

  List<MealScheduleSlot> twoSlots({double a = 300, double b = 300}) => [
    MealScheduleSlot(
      id: 'slot-am',
      period: MealPeriodWire.parseCanonical('morning'),
      scheduledTime: ScheduledTimeOfDay('07:00'),
      targetGrams: a,
    ),
    MealScheduleSlot(
      id: 'slot-pm',
      period: MealPeriodWire.parseCanonical('night'),
      scheduledTime: ScheduledTimeOfDay('19:00'),
      targetGrams: b,
    ),
  ];

  NutritionPlan buildPlan({
    String id = 'np-1',
    String dogId = 'dog-1',
    num amount = 600,
    int meals = 2,
    List<MealScheduleSlot>? schedule,
    DateTime? validFrom,
    DateTime? validUntil,
    NutritionPlanStatus status = NutritionPlanStatus.active,
    int revision = 1,
    String timezone = NutritionPlan.defaultTimezone,
  }) {
    return NutritionPlan(
      id: id,
      dogId: dogId,
      foodType: 'Ração premium',
      amountGramsPerDay: amount,
      mealsPerDay: meals,
      mealSchedule: schedule ?? twoSlots(),
      validFrom: validFrom ?? from,
      validUntil: validUntil,
      timezone: timezone,
      recordedBy: actor,
      status: status,
      schemaVersion: 1,
      revision: revision,
    );
  }

  group('NutritionPlan', () {
    test('construção válida com schedule e campos canônicos', () {
      final plan = buildPlan(validUntil: to);
      expect(plan.amountPerMeal, 300);
      expect(plan.amountGramsPerDay, 600);
      expect(plan.status, NutritionPlanStatus.active);
      expect(plan.validFrom, from);
      expect(plan.validUntil, to);
      expect(plan.timezone, NutritionPlan.defaultTimezone);
      expect(plan.revision, 1);
      expect(plan.mealSchedule, hasLength(2));
      expect(plan.mealSchedule.first.id, 'slot-am');
    });

    test('amount <= 0 é rejeitado', () {
      expect(() => buildPlan(amount: 0), throwsA(isA<HealthDomainException>()));
    });

    test('mealsPerDay <= 0 é rejeitado', () {
      expect(() => buildPlan(meals: 0), throwsA(isA<HealthDomainException>()));
    });

    test('revision < 1 é rejeitada', () {
      expect(
        () => buildPlan(revision: 0),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('timezone vazio é rejeitado', () {
      expect(
        () => buildPlan(timezone: '  '),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('timezone IANA inválido é rejeitado', () {
      expect(
        () => buildPlan(timezone: 'Not/AZone'),
        throwsA(
          isA<HealthDomainException>().having(
            (e) => e.code,
            'code',
            'invalid_timezone',
          ),
        ),
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
          mealSchedule: twoSlots(a: 250, b: 250),
          validFrom: from,
          timezone: NutritionPlan.defaultTimezone,
          recordedBy: actor,
          status: NutritionPlanStatus.active,
          schemaVersion: 1,
          revision: 1,
          hydrationMl: -1,
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('valid_until <= valid_from é rejeitado (D4 estrito)', () {
      expect(
        () => buildPlan(validUntil: from),
        throwsA(isA<HealthDomainException>()),
      );
      expect(
        () => buildPlan(validUntil: from.subtract(const Duration(days: 1))),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('slot ids duplicados são rejeitados', () {
      expect(
        () => buildPlan(
          schedule: [
            MealScheduleSlot(
              id: 'dup',
              period: MealPeriodWire.parseCanonical('morning'),
              scheduledTime: ScheduledTimeOfDay('07:00'),
              targetGrams: 300,
            ),
            MealScheduleSlot(
              id: 'dup',
              period: MealPeriodWire.parseCanonical('night'),
              scheduledTime: ScheduledTimeOfDay('19:00'),
              targetGrams: 300,
            ),
          ],
        ),
        throwsA(
          isA<HealthDomainException>().having(
            (e) => e.code,
            'code',
            'duplicate_meal_schedule_slot_id',
          ),
        ),
      );
    });

    test('scheduled_time inválido é rejeitado', () {
      expect(
        () => MealScheduleSlot(
          id: 's1',
          period: MealPeriodWire.parseCanonical('morning'),
          scheduledTime: ScheduledTimeOfDay('25:00'),
          targetGrams: 100,
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('diagnoseCoherence reporta divergência sem rejeitar', () {
      final plan = buildPlan(
        amount: 600,
        meals: 2,
        schedule: twoSlots(a: 200, b: 200),
      );
      final c = plan.diagnoseCoherence();
      expect(c.mealsPerDayMatchesScheduleLength, isTrue);
      expect(c.targetGramsSumMatchesAmount, isFalse);
      expect(c.targetGramsSum, 400);
      expect(c.isFullyCoherent, isFalse);
    });

    test('diagnoseCoherence alinhado', () {
      final plan = buildPlan();
      expect(plan.diagnoseCoherence().isFullyCoherent, isTrue);
    });
  });

  group('NutritionPlan.validateForActivation D40', () {
    final serverNow = DateTime.utc(2026, 7, 15, 12);

    test('active com valid_from == serverNow é aceito', () {
      final plan = buildPlan(validFrom: serverNow);
      expect(() => plan.validateForActivation(serverNow), returnsNormally);
    });

    test('active com valid_from no passado é aceito', () {
      final plan = buildPlan(
        validFrom: serverNow.subtract(const Duration(days: 1)),
      );
      expect(() => plan.validateForActivation(serverNow), returnsNormally);
    });

    test('active com valid_from futuro é rejeitado', () {
      final plan = buildPlan(
        validFrom: serverNow.add(const Duration(seconds: 1)),
      );
      expect(
        () => plan.validateForActivation(serverNow),
        throwsA(
          isA<HealthDomainException>().having(
            (e) => e.code,
            'code',
            'future_valid_from',
          ),
        ),
      );
    });

    test('active com valid_until == serverNow é rejeitado', () {
      final plan = buildPlan(
        validFrom: serverNow.subtract(const Duration(days: 2)),
        validUntil: serverNow,
      );
      expect(
        () => plan.validateForActivation(serverNow),
        throwsA(
          isA<HealthDomainException>().having(
            (e) => e.code,
            'code',
            'active_plan_already_expired',
          ),
        ),
      );
    });

    test('active com valid_until > serverNow é aceito', () {
      final plan = buildPlan(
        validFrom: serverNow.subtract(const Duration(days: 1)),
        validUntil: serverNow.add(const Duration(days: 1)),
      );
      expect(() => plan.validateForActivation(serverNow), returnsNormally);
    });

    test('superseded não valida D40 (parsing histórico não muta)', () {
      final plan = buildPlan(
        status: NutritionPlanStatus.superseded,
        validFrom: serverNow.add(const Duration(days: 10)),
      );
      expect(() => plan.validateForActivation(serverNow), returnsNormally);
    });
  });

  group('NutritionPlanConflictPolicy', () {
    final policy = const NutritionPlanConflictPolicy();

    test('sem planos ativos não há conflito', () {
      final plans = [
        buildPlan(id: 'a', status: NutritionPlanStatus.superseded),
      ];
      expect(policy.evaluate(plans), isEmpty);
    });

    test('dois planos ativos para o mesmo K9 geram conflito', () {
      final plans = [
        buildPlan(id: 'a'),
        buildPlan(
          id: 'b',
          validFrom: from.add(const Duration(days: 1)),
          amount: 200,
          meals: 2,
          schedule: twoSlots(a: 100, b: 100),
        ),
      ];
      final conflicts = policy.evaluate(plans);
      expect(conflicts, hasLength(1));
      expect(conflicts.single, contains('dog-1'));
    });

    test('planos ativos de K9s diferentes não conflitam', () {
      final plans = [
        buildPlan(id: 'a', dogId: 'dog-1'),
        buildPlan(id: 'b', dogId: 'dog-2', amount: 200, meals: 2),
      ];
      expect(policy.evaluate(plans), isEmpty);
    });
  });
}
