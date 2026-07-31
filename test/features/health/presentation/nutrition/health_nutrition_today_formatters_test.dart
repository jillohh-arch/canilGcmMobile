import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/meal_schedule_slot.dart';
import 'package:canil_gcm/features/health/domain/nutrition_plan.dart';
import 'package:canil_gcm/features/health/domain/nutrition_read_models.dart';
import 'package:canil_gcm/features/health/domain/nutrition_read_state.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_today_formatters.dart';

void main() {
  final actor = RecordedBy(uid: 'u1', name: 'A', internalRole: 'admin');
  final t = DateTime.utc(2026, 7, 14, 12);

  MealLog meal({
    required String id,
    double offered = 100,
    double? consumed,
    String acceptance = 'unknown',
  }) {
    return MealLog(
      id: id,
      dogId: 'dog-a',
      period: MealPeriodWire.parseCanonical('morning'),
      offeredGrams: offered,
      acceptance: MealAcceptanceWire.parse(acceptance),
      fedAt: t,
      recordedBy: actor,
      schemaVersion: 1,
      revision: 1,
      consumedGrams: consumed,
    );
  }

  NutritionMealReadItem item(MealLog m, {NutritionDataOrigin? origin}) {
    return NutritionMealReadItem(
      meal: m,
      origin: origin ?? NutritionDataOrigin.canonical,
      mergeKey: 'k:${m.id}',
    );
  }

  group('consumed null != 0', () {
    test('sem refeições → knownSum null', () {
      final a = HealthNutritionTodayFormatters.consumedAggregation(const []);
      expect(a.knownSum, isNull);
      expect(a.hasAnyMeal, isFalse);
    });

    test('todas com consumed null → knownSum null (não zero)', () {
      final a = HealthNutritionTodayFormatters.consumedAggregation([
        item(meal(id: '1', consumed: null)),
        item(meal(id: '2', consumed: null)),
      ]);
      expect(a.knownSum, isNull);
      expect(a.hasUnknownConsumed, isTrue);
      expect(a.hasAnyMeal, isTrue);
    });

    test('mistura: soma só conhecidos e marca unknown', () {
      final a = HealthNutritionTodayFormatters.consumedAggregation([
        item(meal(id: '1', consumed: 100)),
        item(meal(id: '2', consumed: null)),
      ]);
      expect(a.knownSum, 100);
      expect(a.hasUnknownConsumed, isTrue);
    });

    test('todos conhecidos → soma', () {
      final a = HealthNutritionTodayFormatters.consumedAggregation([
        item(meal(id: '1', consumed: 100)),
        item(meal(id: '2', consumed: 50)),
      ]);
      expect(a.knownSum, 150);
      expect(a.hasUnknownConsumed, isFalse);
    });
  });

  group('acceptance labels', () {
    test('pt-BR', () {
      expect(
        HealthNutritionTodayFormatters.acceptanceLabel(
          MealAcceptanceWire.parse('full'),
        ),
        'Aceitou tudo',
      );
      expect(
        HealthNutritionTodayFormatters.acceptanceLabel(
          MealAcceptanceWire.parse('partial'),
        ),
        'Aceitação parcial',
      );
      expect(
        HealthNutritionTodayFormatters.acceptanceLabel(
          MealAcceptanceWire.parse('refused'),
        ),
        'Recusou',
      );
      expect(
        HealthNutritionTodayFormatters.acceptanceLabel(
          MealAcceptanceWire.parse('unknown'),
        ),
        'Não informado',
      );
    });
  });

  group('slot status derivado', () {
    test('completed quando há meal', () {
      final slot = MealScheduleSlot(
        id: 's1',
        period: MealPeriodWire.parseCanonical('morning'),
        scheduledTime: ScheduledTimeOfDay('07:00'),
        targetGrams: 200,
      );
      final st = NutritionTodaySlotUi.statusFor(
        slot: slot,
        meal: item(meal(id: 'm1')),
        serverNow: DateTime.utc(2026, 7, 14, 20),
        timezone: NutritionPlan.defaultTimezone,
      );
      expect(st, NutritionTodaySlotUiStatus.completed);
    });

    test('pending sem meal e horário futuro', () {
      final slot = MealScheduleSlot(
        id: 's1',
        period: MealPeriodWire.parseCanonical('night'),
        scheduledTime: ScheduledTimeOfDay('23:50'),
        targetGrams: 200,
      );
      final now = DateTime(
        DateTime.now().year,
        DateTime.now().month,
        DateTime.now().day,
        10,
        0,
      );
      final st = NutritionTodaySlotUi.statusFor(
        slot: slot,
        meal: null,
        serverNow: now.toUtc(),
        timezone: NutritionPlan.defaultTimezone,
      );
      expect(st, NutritionTodaySlotUiStatus.pending);
    });
  });

  group('contexto temporal America/Sao_Paulo', () {
    const timezone = NutritionPlan.defaultTimezone;

    test(
      'timeShort usa o timezone normativo, não o timezone do dispositivo',
      () {
        expect(
          HealthNutritionTodayFormatters.timeShort(
            DateTime.utc(2026, 7, 19, 0, 30),
            timezone: timezone,
          ),
          '21:30',
        );
      },
    );

    test('23:30 UTC permanece na data local correta', () {
      expect(
        HealthNutritionTodayFormatters.recentDateTimeLabel(
          instant: DateTime.utc(2026, 7, 19, 23, 30),
          serviceDate: '2026-07-19',
          timezone: timezone,
        ),
        'Hoje · 20:30',
      );
    });

    test('00:30 UTC pertence ao dia local anterior', () {
      expect(
        HealthNutritionTodayFormatters.recentDateTimeLabel(
          instant: DateTime.utc(2026, 7, 19, 0, 30),
          serviceDate: '2026-07-19',
          timezone: timezone,
        ),
        'Ontem · 21:30',
      );
    });

    test('registro mais antigo inclui dd/MM e horário', () {
      expect(
        HealthNutritionTodayFormatters.recentDateTimeLabel(
          instant: DateTime.utc(2026, 7, 16, 21, 57),
          serviceDate: '2026-07-19',
          timezone: timezone,
        ),
        '16/07 · 18:57',
      );
    });
  });
}
