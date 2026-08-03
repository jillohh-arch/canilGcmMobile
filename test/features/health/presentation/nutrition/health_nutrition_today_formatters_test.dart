import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/meal_schedule_slot.dart';
import 'package:canil_gcm/features/health/domain/nutrition_plan.dart';
import 'package:canil_gcm/features/health/domain/nutrition_read_models.dart';
import 'package:canil_gcm/features/health/domain/nutrition_read_state.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_today_formatters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final actor = RecordedBy(uid: 'u1', name: 'A', internalRole: 'admin');

  NutritionMealReadItem mealItem({
    required String id,
    double offered = 300,
    double? consumed,
  }) {
    final finalOffered = (consumed != null && consumed > offered)
        ? consumed
        : offered;
    return NutritionMealReadItem(
      meal: MealLog(
        id: id,
        dogId: 'dog-1',
        period: MealPeriodWire.parseCanonical('morning'),
        offeredGrams: finalOffered,
        consumedGrams: consumed,
        acceptance: MealAcceptanceWire.parse(
          consumed == null
              ? 'full'
              : (consumed == finalOffered
                    ? 'full'
                    : (consumed == 0 ? 'refused' : 'partial')),
        ),
        fedAt: DateTime.utc(2026, 7, 22, 12),
        recordedBy: actor,
        schemaVersion: 1,
        revision: 1,
      ),
      origin: NutritionDataOrigin.canonical,
      mergeKey: id,
    );
  }

  group('HealthNutritionTodayFormatters — Consumed Aggregation', () {
    test('sem refeições → knownSum null', () {
      final res = HealthNutritionTodayFormatters.consumedAggregation([]);
      expect(res.knownSum, isNull);
      expect(res.hasUnknownConsumed, isFalse);
      expect(res.hasAnyMeal, isFalse);
    });

    test('todas com consumed null → knownSum null (não zero)', () {
      final res = HealthNutritionTodayFormatters.consumedAggregation([
        mealItem(id: '1', consumed: null),
        mealItem(id: '2', consumed: null),
      ]);
      expect(res.knownSum, isNull);
      expect(res.hasUnknownConsumed, isTrue);
      expect(res.hasAnyMeal, isTrue);
    });

    test('mistura: soma só conhecidos e marca unknown', () {
      final res = HealthNutritionTodayFormatters.consumedAggregation([
        mealItem(id: '1', consumed: 100),
        mealItem(id: '2', consumed: null),
      ]);
      expect(res.knownSum, 100);
      expect(res.hasUnknownConsumed, isTrue);
      expect(res.hasAnyMeal, isTrue);
    });

    test('todos conhecidos → soma', () {
      final res = HealthNutritionTodayFormatters.consumedAggregation([
        mealItem(id: '1', offered: 200, consumed: 100),
        mealItem(id: '2', offered: 200, consumed: 50),
      ]);
      expect(res.knownSum, 150);
      expect(res.hasUnknownConsumed, isFalse);
      expect(res.hasAnyMeal, isTrue);
    });
  });

  group('HealthNutritionTodayFormatters — UX-04C summary card formatters', () {
    test(
      'offeredAggregation diferencia ausência de oferta de zero verdadeiro',
      () {
        final noMeals = HealthNutritionTodayFormatters.offeredAggregation([]);
        expect(noMeals.hasRegisteredOffer, isFalse);
        expect(noMeals.sum, isNull);

        final registeredOffer =
            HealthNutritionTodayFormatters.offeredAggregation([
              mealItem(id: 'm1', offered: 100, consumed: 0),
            ]);
        expect(registeredOffer.hasRegisteredOffer, isTrue);
        expect(registeredOffer.sum, 100);
      },
    );

    test('percentageText determinístico', () {
      expect(
        HealthNutritionTodayFormatters.percentageText(
          planned: 500,
          consumedMeasured: 350,
          hasUnknownConsumed: false,
        ),
        '70% da meta diária consumida',
      );

      expect(
        HealthNutritionTodayFormatters.percentageText(
          planned: 500,
          consumedMeasured: null,
          hasUnknownConsumed: false,
        ),
        'Progresso indisponível (nenhum consumo registrado)',
      );
    });

    test('remainingText determinístico (UX-04C Human Review)', () {
      expect(
        HealthNutritionTodayFormatters.remainingText(
          planned: 500,
          consumedMeasured: null,
          hasUnknownConsumed: false,
          hasRegisteredConsumption: false,
        ),
        'Não calculado',
      );

      expect(
        HealthNutritionTodayFormatters.remainingText(
          planned: 500,
          consumedMeasured: null,
          hasUnknownConsumed: true,
          hasRegisteredConsumption: true,
        ),
        'Até 500 g',
      );

      expect(
        HealthNutritionTodayFormatters.remainingText(
          planned: 500,
          consumedMeasured: 250,
          hasUnknownConsumed: true,
          hasRegisteredConsumption: true,
        ),
        'Até 250 g',
      );

      expect(
        HealthNutritionTodayFormatters.remainingText(
          planned: 500,
          consumedMeasured: 350,
          hasUnknownConsumed: false,
          hasRegisteredConsumption: true,
        ),
        '150 g',
      );

      expect(
        HealthNutritionTodayFormatters.remainingText(
          planned: 500,
          consumedMeasured: 550,
          hasUnknownConsumed: false,
          hasRegisteredConsumption: true,
        ),
        '0 g',
      );
    });

    test('statusBadgeText determinístico sem Plano ativo', () {
      expect(
        HealthNutritionTodayFormatters.statusBadgeText(
          planned: 500,
          consumedMeasured: 350,
          hasUnknownConsumed: false,
          hasAnyMeal: true,
        ),
        'Dentro do plano',
      );

      expect(
        HealthNutritionTodayFormatters.statusBadgeText(
          planned: 500,
          consumedMeasured: null,
          hasUnknownConsumed: false,
          hasAnyMeal: false,
        ),
        'Sem registro',
      );

      expect(
        HealthNutritionTodayFormatters.statusBadgeText(
          planned: 500,
          consumedMeasured: null,
          hasUnknownConsumed: true,
          hasAnyMeal: true,
        ),
        'Medição incompleta',
      );
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
    MealScheduleSlot slot({String period = 'morning', String time = '07:00'}) {
      return MealScheduleSlot(
        id: 's1',
        period: MealPeriodWire.parseCanonical(period),
        scheduledTime: ScheduledTimeOfDay(time),
        targetGrams: 200,
      );
    }

    test('completed quando há meal', () {
      expect(
        NutritionTodaySlotUi.statusFor(
          slot: slot(),
          meal: mealItem(id: 'm1'),
          serverNow: DateTime.utc(2026, 7, 14, 20),
          timezone: NutritionPlan.defaultTimezone,
        ),
        NutritionTodaySlotUiStatus.completed,
      );
    });

    test('pending sem meal e horário futuro', () {
      expect(
        NutritionTodaySlotUi.statusFor(
          slot: slot(period: 'night', time: '23:50'),
          meal: null,
          serverNow: DateTime.utc(2026, 7, 14, 13),
          timezone: NutritionPlan.defaultTimezone,
        ),
        NutritionTodaySlotUiStatus.pending,
      );
    });

    test('exactly at planned time remains pending', () {
      expect(
        NutritionTodaySlotUi.statusFor(
          slot: slot(),
          meal: null,
          serverNow: DateTime.utc(2026, 7, 14, 10),
          timezone: NutritionPlan.defaultTimezone,
        ),
        NutritionTodaySlotUiStatus.pending,
      );
    });

    test('fixed serverNow deterministically decides late', () {
      NutritionTodaySlotUiStatus status(DateTime serverNow) =>
          NutritionTodaySlotUi.statusFor(
            slot: slot(),
            meal: null,
            serverNow: serverNow,
            timezone: NutritionPlan.defaultTimezone,
          );

      expect(
        status(DateTime.utc(2026, 7, 14, 9, 59)),
        NutritionTodaySlotUiStatus.pending,
      );
      expect(
        status(DateTime.utc(2026, 7, 14, 10, 1)),
        NutritionTodaySlotUiStatus.late,
      );
      expect(
        status(DateTime.utc(2026, 7, 14, 10, 1)),
        NutritionTodaySlotUiStatus.late,
      );
    });

    test('completed takes precedence after planned time', () {
      expect(
        NutritionTodaySlotUi.statusFor(
          slot: slot(),
          meal: mealItem(id: 'm1'),
          serverNow: DateTime.utc(2026, 7, 14, 20),
          timezone: NutritionPlan.defaultTimezone,
        ),
        NutritionTodaySlotUiStatus.completed,
      );
    });

    test('plan timezone and normative midnight share one clock', () {
      final nightSlot = slot(period: 'night', time: '23:55');
      expect(
        NutritionTodaySlotUi.statusFor(
          slot: nightSlot,
          meal: null,
          serverNow: DateTime.utc(2026, 7, 15, 2, 54),
          timezone: NutritionPlan.defaultTimezone,
        ),
        NutritionTodaySlotUiStatus.pending,
      );
      expect(
        NutritionTodaySlotUi.statusFor(
          slot: nightSlot,
          meal: null,
          serverNow: DateTime.utc(2026, 7, 15, 3, 1),
          timezone: NutritionPlan.defaultTimezone,
        ),
        NutritionTodaySlotUiStatus.pending,
      );
    });
  });

  group('plan validity formatting', () {
    test('instant uses explicit plan timezone near UTC midnight', () {
      expect(
        HealthNutritionTodayFormatters.dateShort(
          DateTime.utc(2026, 7, 19, 0, 30),
          timezone: 'America/Sao_Paulo',
        ),
        '18/07/2026',
      );
    });

    test('default timezone formats start and end deterministically', () {
      expect(
        HealthNutritionTodayFormatters.dateShort(
          DateTime.utc(2026, 1, 1, 3),
          timezone: NutritionPlan.defaultTimezone,
        ),
        '01/01/2026',
      );
      expect(
        HealthNutritionTodayFormatters.dateShort(
          DateTime.utc(2026, 12, 31, 2, 59),
          timezone: NutritionPlan.defaultTimezone,
        ),
        '30/12/2026',
      );
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
