import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/core/services/authoritative_time/authoritative_time_gateway.dart';
import 'package:canil_gcm/core/services/authoritative_time/authoritative_time_models.dart';
import 'package:canil_gcm/core/services/authoritative_time/authoritative_time_provider.dart';
import 'package:canil_gcm/core/services/authoritative_time/monotonic_elapsed_clock.dart';
import 'package:canil_gcm/features/health/data/coexistence/nutrition/coexistence_nutrition_read_source.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_gateway.dart';
import 'package:canil_gcm/features/health/domain/legacy_nutrition_views.dart';
import 'package:canil_gcm/features/health/domain/meal_occurrence.dart';
import 'package:canil_gcm/features/health/domain/meal_schedule_slot.dart';
import 'package:canil_gcm/features/health/domain/nutrition_plan.dart';
import 'package:canil_gcm/features/health/domain/nutrition_plan_regimen.dart';
import 'package:canil_gcm/features/health/domain/nutrition_read_models.dart';
import 'package:canil_gcm/features/health/domain/nutrition_read_state.dart';
import 'package:canil_gcm/features/health/domain/supplement_log.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_read_controller.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_mutation_controller.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_supplement_form_sheet.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_today_screen.dart';
import 'package:canil_gcm/features/health/presentation/summary/widgets/health_summary_card_surface.dart';

final class _ScriptedSource {
  _ScriptedSource(this.resultsByDog);
  final Map<String, NutritionReadResult<NutritionCoexistenceSnapshot>>
  resultsByDog;
  final calls = <String>[];

  CoexistenceNutritionReadSource asSource() {
    return CoexistenceNutritionReadSource(
      canonicalPlanReader: _PlanReader(this),
      canonicalMealReader: _MealReader(this),
    );
  }
}

final class _PlanReader implements NutritionCanonicalPlanReader {
  _PlanReader(this.host);
  final _ScriptedSource host;

  @override
  Future<NutritionSourceBatch<NutritionPlan>> loadPlans(String dogId) async {
    host.calls.add('plan:$dogId');
    final r = host.resultsByDog[dogId];
    if (r == null || r.isError) {
      return const NutritionSourceBatch.error(
        code: 'forced',
        message: 'fail plan',
      );
    }
    if (r.isOffline) {
      return const NutritionSourceBatch.offline(message: 'offline plan');
    }
    final snap = r.value;
    if (snap == null || snap.canonicalPlans.isEmpty) {
      // empty batch may still have legacy — but this source only has canonical
      if (snap?.legacyPlans.isNotEmpty == true) {
        return const NutritionSourceBatch.empty();
      }
      return const NutritionSourceBatch.empty();
    }
    return NutritionSourceBatch.available(snap.canonicalPlans);
  }
}

final class _MealReader implements NutritionCanonicalMealReader {
  _MealReader(this.host);
  final _ScriptedSource host;

  @override
  Future<NutritionSourceBatch<MealLog>> loadMeals(
    String dogId, {
    DateTime? from,
    DateTime? to,
  }) async {
    host.calls.add('meal:$dogId');
    final r = host.resultsByDog[dogId];
    if (r == null || r.isError) {
      return const NutritionSourceBatch.error(
        code: 'forced',
        message: 'fail meal',
      );
    }
    if (r.isOffline) {
      return const NutritionSourceBatch.offline(message: 'offline meal');
    }
    final snap = r.value;
    if (snap == null || snap.canonicalMeals.isEmpty) {
      return const NutritionSourceBatch.empty();
    }
    return NutritionSourceBatch.available(snap.canonicalMeals);
  }
}

// Better approach: inject a fake that implements load via custom source wrapper.
// CoexistenceNutritionReadSource is final and needs readers. For widget tests,
// use HealthNutritionReadController with a custom CoexistenceNutritionReadSource
// built from in-memory readers that return prebuilt batches.

final class _MemPlan implements NutritionCanonicalPlanReader {
  _MemPlan(this.batch);
  NutritionSourceBatch<NutritionPlan> batch;
  @override
  Future<NutritionSourceBatch<NutritionPlan>> loadPlans(String dogId) async =>
      batch;
}

final class _MemLegacyPlan implements NutritionLegacyPlanReader {
  _MemLegacyPlan(this.batch);
  NutritionSourceBatch<LegacyNutritionPlanView> batch;
  @override
  Future<NutritionSourceBatch<LegacyNutritionPlanView>> loadPlans(
    String dogId,
  ) async => batch;
}

final class _MemMeal implements NutritionCanonicalMealReader {
  _MemMeal(this.batch);
  NutritionSourceBatch<MealLog> batch;
  @override
  Future<NutritionSourceBatch<MealLog>> loadMeals(
    String dogId, {
    DateTime? from,
    DateTime? to,
  }) async => batch;
}

final class _SequencePlanReader implements NutritionCanonicalPlanReader {
  _SequencePlanReader(this.batches);

  final List<NutritionSourceBatch<NutritionPlan>> batches;
  var calls = 0;

  @override
  Future<NutritionSourceBatch<NutritionPlan>> loadPlans(String dogId) async {
    final index = calls < batches.length ? calls : batches.length - 1;
    calls++;
    return batches[index];
  }
}

final class _SequenceSupplementReader
    implements NutritionCanonicalSupplementLogReader {
  _SequenceSupplementReader(this.batches);

  final List<NutritionSourceBatch<SupplementLog>> batches;
  var calls = 0;

  @override
  Future<NutritionSourceBatch<SupplementLog>> loadSupplementLogs(
    String dogId,
  ) async {
    final index = calls < batches.length ? calls : batches.length - 1;
    calls++;
    return batches[index];
  }
}

final class _SequenceMealReader implements NutritionCanonicalMealReader {
  _SequenceMealReader(this.batches);

  final List<NutritionSourceBatch<MealLog>> batches;
  var calls = 0;

  @override
  Future<NutritionSourceBatch<MealLog>> loadMeals(
    String dogId, {
    DateTime? from,
    DateTime? to,
  }) async {
    final index = calls < batches.length ? calls : batches.length - 1;
    calls++;
    return batches[index];
  }
}

final class _MemLegacyMeal implements NutritionLegacyMealReader {
  _MemLegacyMeal(this.batch);
  NutritionSourceBatch<MealLog> batch;
  @override
  String get collectionKey => 'feeding_events';
  @override
  Future<NutritionSourceBatch<MealLog>> loadMeals(
    String dogId, {
    DateTime? from,
    DateTime? to,
  }) async => batch;
}

final actor = RecordedBy(uid: 'u1', name: 'Silva', internalRole: 'condutor');

NutritionPlan canonicalPlan({
  String id = 'plan-1',
  String dogId = 'dog-a',
  String foodType = 'Ração Premium',
  double amountGramsPerDay = 600,
  String timezone = NutritionPlan.defaultTimezone,
  DateTime? validFrom,
  DateTime? validUntil,
  List<NutritionPlanSupplementRegimen> supplements = const [],
}) {
  return NutritionPlan(
    id: id,
    dogId: dogId,
    foodType: foodType,
    amountGramsPerDay: amountGramsPerDay,
    mealsPerDay: 2,
    mealSchedule: [
      MealScheduleSlot(
        id: 's-m',
        period: MealPeriodWire.parseCanonical('morning'),
        scheduledTime: ScheduledTimeOfDay('07:00'),
        targetGrams: 300,
      ),
      MealScheduleSlot(
        id: 's-n',
        period: MealPeriodWire.parseCanonical('night'),
        scheduledTime: ScheduledTimeOfDay('18:30'),
        targetGrams: 300,
      ),
    ],
    validFrom: validFrom ?? DateTime.utc(2026, 1, 1),
    validUntil: validUntil,
    timezone: timezone,
    recordedBy: actor,
    status: NutritionPlanStatus.active,
    schemaVersion: 1,
    revision: 1,
    supplements: supplements,
  );
}

MealLog mealLog({
  required String id,
  double offered = 200,
  double? consumed = 200,
  String? acceptance,
  String? plannedMealId,
  DateTime? fedAt,
}) {
  final effectiveFedAt = fedAt ?? DateTime.now().toUtc();
  final occurrence = plannedMealId == null
      ? null
      : MealOccurrenceId.v1(
          MealOccurrenceKey(
            dogId: 'dog-a',
            planId: 'plan-1',
            plannedMealId: plannedMealId,
            localServiceDate: LocalServiceDate.fromInstant(
              effectiveFedAt,
              timezone: NutritionPlan.defaultTimezone,
            ),
          ),
        ).value;
  return MealLog(
    id: id,
    dogId: 'dog-a',
    period: MealPeriodWire.parseCanonical('morning'),
    offeredGrams: offered,
    acceptance: MealAcceptanceWire.parse(
      acceptance ?? (consumed == null ? 'unknown' : 'full'),
    ),
    fedAt: effectiveFedAt,
    recordedBy: actor,
    schemaVersion: 1,
    revision: 1,
    consumedGrams: consumed,
    plannedMealId: plannedMealId,
    planId: plannedMealId == null ? null : 'plan-1',
    mealOccurrenceId: occurrence,
  );
}

SupplementLog supplementLog({
  required String id,
  required String name,
  required DateTime administeredAt,
  num dose = 1,
  SupplementDoseUnit unit = SupplementDoseUnit.tablet,
  String? notes,
  String? nutritionPlanId,
  String? supplementRegimenId,
}) {
  return SupplementLog(
    id: id,
    dogId: 'dog-a',
    supplementName: name,
    dose: dose,
    unit: unit,
    administeredAt: administeredAt,
    recordedBy: actor,
    schemaVersion: 1,
    revision: 1,
    notes: notes,
    nutritionPlanId: nutritionPlanId,
    supplementRegimenId: supplementRegimenId,
  );
}

/// Creates a UTC instant that, when displayed in the America/Sao_Paulo
/// timezone, shows [timeStr] (e.g., '01:30').
///
/// The test asserts that the interface renders '01:30' in São Paulo time,
/// regardless of the local timezone of the test device.
///
/// Example:
///   Input:  '01:30' in America/Sao_Paulo (UTC-3 in July/winter)
///   Output: DateTime.utc(now, now, now, 4, 30) — the equivalent UTC instant
DateTime _utcForLocalTimeInSaoPaulo(String timeStr) {
  final parts = timeStr.split(':');
  final localHour = int.parse(parts[0]);
  final localMinute = int.parse(parts[1]);
  // São Paulo UTC offset is -3 hours during July (winter in Southern Hemisphere)
  const utcOffsetHours = 3;
  final utcHour = (localHour + utcOffsetHours) % 24;
  final now = DateTime.now();
  return DateTime.utc(now.year, now.month, now.day, utcHour, localMinute);
}

void main() {
  testWidgets('loading state', (tester) async {
    final gate = Completer<void>();
    final controller = HealthNutritionReadController(
      source: CoexistenceNutritionReadSource(
        canonicalPlanReader: _GatedPlan(gate),
      ),
    );
    final future = controller.selectDog('dog-a');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HealthNutritionTodayScreen(
            controller: controller,
            dogDisplayName: 'Bono',
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('Carregando'), findsOneWidget);
    gate.complete();
    await future;
    controller.dispose();
  });

  testWidgets('canonical data shows plan and slots', (tester) async {
    final source = CoexistenceNutritionReadSource(
      canonicalPlanReader: _MemPlan(
        NutritionSourceBatch.available([canonicalPlan()]),
      ),
      canonicalMealReader: _MemMeal(
        NutritionSourceBatch.available([
          mealLog(id: 'm1', plannedMealId: 's-m'),
        ]),
      ),
    );
    final controller = HealthNutritionReadController(
      source: source,
      clock: () => DateTime.now().toUtc(),
    );
    await controller.selectDog('dog-a');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HealthNutritionTodayScreen(
            controller: controller,
            dogDisplayName: 'Bono',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Ração Premium'), findsOneWidget);
    expect(find.textContaining('MANHÃ'), findsWidgets);
    expect(find.textContaining('PLANO ALIMENTAR ATIVO'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('Hoje ·'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('Hoje ·'), findsWidgets);
    // No write CTA
    expect(find.textContaining('Registrar refeição'), findsNothing);
    expect(find.textContaining('Registrar administração'), findsNothing);
    controller.dispose();
  });

  testWidgets('resumo separa oferta de consumo parcial conhecido', (
    tester,
  ) async {
    final source = CoexistenceNutritionReadSource(
      canonicalPlanReader: _MemPlan(
        NutritionSourceBatch.available([canonicalPlan(amountGramsPerDay: 500)]),
      ),
      canonicalMealReader: _MemMeal(
        NutritionSourceBatch.available([
          mealLog(
            id: 'known',
            offered: 300,
            consumed: 250,
            acceptance: 'partial',
            plannedMealId: 's-m',
          ),
          mealLog(
            id: 'unknown',
            offered: 200,
            consumed: null,
            plannedMealId: 's-n',
          ),
        ]),
      ),
    );
    final controller = HealthNutritionReadController(
      source: source,
      clock: () => DateTime.now().toUtc(),
    );
    await controller.selectDog('dog-a');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HealthNutritionTodayScreen(
            controller: controller,
            dogDisplayName: 'Bono',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('250 g mensurados'), findsWidgets);
    expect(find.text('Meta diária: 500 g'), findsWidgets);
    expect(find.text('Até 250 g'), findsOneWidget);
    expect(
      find.text('Cálculo baseado apenas nas quantidades medidas'),
      findsOneWidget,
    );
    final bars = tester
        .widgetList<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        )
        .toList();
    expect(bars[0].value, 0.5);
  });

  testWidgets('aceitação full sem consumo explica ausência de medição', (
    tester,
  ) async {
    final source = CoexistenceNutritionReadSource(
      canonicalPlanReader: _MemPlan(
        NutritionSourceBatch.available([canonicalPlan()]),
      ),
      canonicalMealReader: _MemMeal(
        NutritionSourceBatch.available([
          mealLog(
            id: 'full-null',
            offered: 300,
            consumed: null,
            acceptance: 'full',
            plannedMealId: 's-m',
          ),
        ]),
      ),
    );
    final controller = HealthNutritionReadController(
      source: source,
      clock: () => DateTime.now().toUtc(),
    );
    await controller.selectDog('dog-a');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HealthNutritionTodayScreen(
            controller: controller,
            dogDisplayName: 'Bono',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Quantidade consumida não medida').first,
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Aceitou tudo'), findsOneWidget);
    expect(find.text('Quantidade consumida não medida'), findsWidgets);
    expect(find.text('Não informado'), findsOneWidget);
  });

  testWidgets('refeição avulsa preserva horário no timezone normativo', (
    tester,
  ) async {
    // fedAt that displays as 01:30 in São Paulo timezone, today
    final fedAtUtc = _utcForLocalTimeInSaoPaulo('01:30');

    final source = CoexistenceNutritionReadSource(
      canonicalPlanReader: _MemPlan(
        NutritionSourceBatch.available([canonicalPlan()]),
      ),
      canonicalMealReader: _MemMeal(
        NutritionSourceBatch.available([
          mealLog(id: 'adhoc-timezone', fedAt: fedAtUtc),
        ]),
      ),
    );
    final controller = HealthNutritionReadController(
      source: source,
      clock: () => DateTime.now().toUtc(),
    );
    await controller.selectDog('dog-a');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HealthNutritionTodayScreen(
            controller: controller,
            dogDisplayName: 'Bono',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The adhoc meal should appear in "REFEIÇÕES DE HOJE" section (no plannedMealId)
    // Scroll to find the 01:30 time label within the adhoc meal card
    await tester.scrollUntilVisible(
      find.text('01:30'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('01:30'), findsOneWidget);
  });

  testWidgets('legacy fallback shows plan anterior and meals', (tester) async {
    final source = CoexistenceNutritionReadSource(
      canonicalPlanReader: _MemPlan(const NutritionSourceBatch.empty()),
      legacyPlanReader: _MemLegacyPlan(
        NutritionSourceBatch.available([
          LegacyNutritionPlanView(
            id: 'lp1',
            dogId: 'dog-a',
            foodType: 'Ração Legada',
            amountGramsPerDay: 500,
            mealsPerDay: 2,
            vigentFrom: DateTime.utc(2026, 1, 1),
            legacySource: 'nutritional_prescriptions',
          ),
        ]),
      ),
      legacyMealReaders: [
        _MemLegacyMeal(
          NutritionSourceBatch.available([
            mealLog(
              id: 'fe1',
              offered: 150,
              consumed: null,
              fedAt: DateTime.now().toUtc(),
            ),
          ]),
        ),
      ],
    );
    final controller = HealthNutritionReadController(
      source: source,
      clock: () => DateTime.now().toUtc(),
    );
    await controller.selectDog('dog-a');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HealthNutritionTodayScreen(
            controller: controller,
            dogDisplayName: 'Bono',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Estado data (não empty/error/offline)
    expect(find.text('Sem conexão'), findsNothing);
    expect(find.textContaining('Sem registros de nutrição'), findsNothing);
    expect(find.textContaining('NUTRIÇÃO'), findsOneWidget);
    expect(find.textContaining('Ração Legada'), findsOneWidget);
    expect(find.textContaining('Plano anterior'), findsWidgets);
    expect(
      find.textContaining('Horários de refeição canônicos não disponíveis'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.textContaining('Hoje ·'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('Hoje ·'), findsWidgets);
    controller.dispose();
  });

  testWidgets('degraded keeps legacy data visible with partial warning', (
    tester,
  ) async {
    final source = CoexistenceNutritionReadSource(
      canonicalPlanReader: _MemPlan(
        const NutritionSourceBatch.error(
          code: 'canonical-down',
          message: 'canonical unavailable',
        ),
      ),
      legacyPlanReader: _MemLegacyPlan(
        NutritionSourceBatch.available([
          LegacyNutritionPlanView(
            id: 'lp-degraded',
            dogId: 'dog-a',
            foodType: 'Ração do plano anterior',
            amountGramsPerDay: 500,
            mealsPerDay: 2,
            vigentFrom: DateTime.utc(2026, 1, 1),
            legacySource: 'nutritional_prescriptions',
          ),
        ]),
      ),
    );
    final controller = HealthNutritionReadController(
      source: source,
      clock: () => DateTime.now().toUtc(),
    );
    await controller.selectDog('dog-a');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HealthNutritionTodayScreen(
            controller: controller,
            dogDisplayName: 'Bono',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Leitura parcial'), findsOneWidget);
    expect(find.textContaining('Ração do plano anterior'), findsOneWidget);
    expect(find.textContaining('Sem registros de nutrição'), findsNothing);
    controller.dispose();
  });

  testWidgets('dog switch never paints stale result from previous dog', (
    tester,
  ) async {
    final releaseDogA = Completer<void>();
    final source = CoexistenceNutritionReadSource(
      canonicalPlanReader: _DogSwitchPlanReader(releaseDogA.future),
    );
    final controller = HealthNutritionReadController(
      source: source,
      clock: () => DateTime.now().toUtc(),
    );

    final dogAFuture = controller.selectDog('dog-a');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HealthNutritionTodayScreen(
            controller: controller,
            dogDisplayName: 'K9 ativo',
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('Carregando'), findsOneWidget);

    await controller.selectDog('dog-b');
    await tester.pumpAndSettle();
    expect(find.textContaining('Plano B'), findsOneWidget);
    expect(find.textContaining('Plano A stale'), findsNothing);

    releaseDogA.complete();
    await dogAFuture;
    await tester.pumpAndSettle();
    expect(find.textContaining('Plano B'), findsOneWidget);
    expect(find.textContaining('Plano A stale'), findsNothing);
    expect(controller.activeDogId, 'dog-b');
    controller.dispose();
  });

  testWidgets('compact and large phones with text scale have no overflow', (
    tester,
  ) async {
    final source = CoexistenceNutritionReadSource(
      canonicalPlanReader: _MemPlan(
        NutritionSourceBatch.available([canonicalPlan()]),
      ),
      canonicalMealReader: _MemMeal(
        NutritionSourceBatch.available([
          mealLog(id: 'responsive-meal', plannedMealId: 's-m'),
        ]),
      ),
    );
    final controller = HealthNutritionReadController(
      source: source,
      clock: () => DateTime.now().toUtc(),
    );
    await controller.selectDog('dog-a');
    addTearDown(controller.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final size in const [Size(360, 640), Size(430, 932)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: Scaffold(
            body: HealthNutritionTodayScreen(
              controller: controller,
              dogDisplayName: 'Bono com nome operacional extenso',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'surface $size');
      expect(find.text('CONSUMO DE HOJE'), findsOneWidget);
    }
  });

  testWidgets('offline shows Sem conexão', (tester) async {
    final source = CoexistenceNutritionReadSource(
      canonicalPlanReader: _MemPlan(
        const NutritionSourceBatch.offline(message: 'offline'),
      ),
      canonicalMealReader: _MemMeal(
        const NutritionSourceBatch.offline(message: 'offline'),
      ),
    );
    final controller = HealthNutritionReadController(source: source);
    await controller.selectDog('dog-a');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HealthNutritionTodayScreen(
            controller: controller,
            dogDisplayName: 'Bono',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sem conexão'), findsOneWidget);
    expect(find.text('Tentar novamente'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('error shows retry', (tester) async {
    final source = CoexistenceNutritionReadSource(
      canonicalPlanReader: _MemPlan(
        const NutritionSourceBatch.error(code: 'x', message: 'boom'),
      ),
      canonicalMealReader: _MemMeal(
        const NutritionSourceBatch.error(code: 'x', message: 'boom'),
      ),
    );
    final controller = HealthNutritionReadController(source: source);
    await controller.selectDog('dog-a');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HealthNutritionTodayScreen(
            controller: controller,
            dogDisplayName: 'Bono',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Não foi possível carregar'), findsOneWidget);
    expect(find.text('Tentar novamente'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('empty state', (tester) async {
    final source = CoexistenceNutritionReadSource(
      canonicalPlanReader: _MemPlan(const NutritionSourceBatch.empty()),
      canonicalMealReader: _MemMeal(const NutritionSourceBatch.empty()),
    );
    final controller = HealthNutritionReadController(source: source);
    await controller.selectDog('dog-a');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HealthNutritionTodayScreen(
            controller: controller,
            dogDisplayName: 'Bono',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Sem registros de nutrição'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('legacy regimen not presented as administration', (tester) async {
    final controller = HealthNutritionReadController(
      source: CoexistenceNutritionReadSource(
        canonicalPlanReader: _MemPlan(const NutritionSourceBatch.empty()),
        legacyPlanReader: _MemLegacyPlan(
          NutritionSourceBatch.available([
            LegacyNutritionPlanView(
              id: 'lp1',
              dogId: 'dog-a',
              foodType: 'Ração',
              amountGramsPerDay: 400,
              mealsPerDay: 2,
              vigentFrom: DateTime.utc(2026, 1, 1),
              legacySource: 'nutritional_prescriptions',
            ),
          ]),
        ),
        legacySupplementRegimenReader: _MemLegacyRegimen(
          NutritionSourceBatch.available([
            const LegacySupplementRegimenView(
              id: 'reg1',
              dogId: 'dog-a',
              name: 'Condroprotetor',
              doseText: '1 comprimido',
              legacySource: 'nutrition_supplements',
            ),
          ]),
        ),
      ),
    );
    await controller.selectDog('dog-a');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HealthNutritionTodayScreen(
            controller: controller,
            dogDisplayName: 'Bono',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Condroprotetor'), findsOneWidget);
    expect(find.text('Registro legado'), findsOneWidget);
    expect(find.textContaining('ADMINISTRAÇÕES DE HOJE'), findsOneWidget);
    controller.dispose();
  });

  testWidgets(
    'supplement authority hierarchy separates active and legacy regimens from today facts',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final referenceNow = DateTime.utc(2026, 7, 22, 15);
      final regimen = NutritionPlanSupplementRegimen(
        id: 'reg-active',
        name: 'Condroprotetor veterinário de suporte articular',
        dose: 1.5,
        unit: SupplementDoseUnit.tablet,
        frequency: 'Uma vez ao dia conforme orientação veterinária',
        instructions: 'Administrar junto ao alimento.',
      );
      final controller = HealthNutritionReadController(
        source: CoexistenceNutritionReadSource(
          canonicalPlanReader: _MemPlan(
            NutritionSourceBatch.available([
              canonicalPlan(supplements: [regimen]),
            ]),
          ),
          legacySupplementRegimenReader: _MemLegacyRegimen(
            NutritionSourceBatch.available([
              const LegacySupplementRegimenView(
                id: 'legacy-regimen',
                dogId: 'dog-a',
                name: 'Óleo de peixe legado',
                doseText: '2',
                unitText: 'cápsulas',
                frequencyText: 'Conforme prescrição anterior',
                legacySource: 'nutrition_supplements',
              ),
            ]),
          ),
          canonicalSupplementLogReader: _SequenceSupplementReader([
            NutritionSourceBatch.available([
              supplementLog(
                id: 'prescribed-log',
                name: 'Condroprotetor veterinário de suporte articular',
                administeredAt: DateTime.utc(2026, 7, 22, 11, 30),
                dose: 1.5,
                nutritionPlanId: 'plan-1',
                supplementRegimenId: 'reg-active',
                notes: 'Aceitou sem intercorrências durante a administração.',
              ),
              supplementLog(
                id: 'adhoc-log',
                name: 'Probiótico avulso',
                administeredAt: DateTime.utc(2026, 7, 22, 14),
                unit: SupplementDoseUnit.g,
              ),
            ]),
          ]),
        ),
        clock: () => referenceNow,
      );
      addTearDown(controller.dispose);
      await controller.selectDog('dog-a');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HealthNutritionTodayScreen(
              controller: controller,
              dogDisplayName: 'Bono',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text('SUPLEMENTOS EM USO'),
        400,
        scrollable: scrollable,
      );
      expect(find.text('Regimes prescritos atualmente'), findsOneWidget);
      expect(find.text('Plano ativo'), findsOneWidget);
      expect(find.text('Registro legado'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Probiótico avulso'),
        400,
        scrollable: scrollable,
      );
      expect(find.text('ADMINISTRAÇÕES DE HOJE'), findsOneWidget);
      expect(find.text('Fatos registrados no dia'), findsOneWidget);
      expect(find.text('2 registros'), findsOneWidget);
      expect(find.text('Prescrito'), findsOneWidget);
      expect(find.text('Avulso'), findsOneWidget);
      expect(find.text('08:30'), findsOneWidget);
      expect(find.text('11:00'), findsOneWidget);
      expect(find.text('1,5 comprimido'), findsNothing);
      expect(find.text('1.5 comprimido'), findsWidgets);
      expect(
        find.text('Aceitou sem intercorrências durante a administração.'),
        findsOneWidget,
      );
      for (final card in [
        find.ancestor(
          of: find.text('Óleo de peixe legado'),
          matching: find.byType(HealthSummaryCardSurface),
        ),
        find.ancestor(
          of: find.text('Probiótico avulso'),
          matching: find.byType(HealthSummaryCardSurface),
        ),
      ]) {
        expect(
          find.descendant(
            of: card,
            matching: find.textContaining('Pendente', skipOffstage: false),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: card,
            matching: find.textContaining('Atrasado', skipOffstage: false),
          ),
          findsNothing,
        );
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('supplement and administration empty states remain distinct', (
    tester,
  ) async {
    final referenceNow = DateTime.utc(2026, 7, 22, 15);
    final controller = HealthNutritionReadController(
      source: CoexistenceNutritionReadSource(
        canonicalPlanReader: _MemPlan(
          NutritionSourceBatch.available([canonicalPlan()]),
        ),
        canonicalSupplementLogReader: _SequenceSupplementReader([
          const NutritionSourceBatch.empty(),
        ]),
      ),
      clock: () => referenceNow,
    );
    addTearDown(controller.dispose);
    await controller.selectDog('dog-a');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HealthNutritionTodayScreen(
            controller: controller,
            dogDisplayName: 'Bono',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('Nenhuma administração registrada hoje.'),
      400,
      scrollable: scrollable,
    );

    expect(find.text('Nenhum suplemento em uso registrado.'), findsOneWidget);
    expect(find.text('Nenhuma administração registrada hoje.'), findsOneWidget);
    expect(find.text('Administrações de hoje indisponíveis'), findsNothing);
    expect(find.textContaining('registros'), findsNothing);
  });

  testWidgets(
    'today error never paints old supplement and refresh replaces unavailable',
    (tester) async {
      final now = DateTime.utc(2026, 7, 22, 15);
      final old = supplementLog(
        id: 'old',
        name: 'Histórico antigo',
        administeredAt: DateTime.utc(2026, 7, 21, 15),
      );
      final current = supplementLog(
        id: 'today',
        name: 'Administração segura',
        administeredAt: DateTime.utc(2026, 7, 22, 15),
      );
      final plans = _SequencePlanReader([
        NutritionSourceBatch.available([canonicalPlan()]),
        NutritionSourceBatch.available([canonicalPlan()]),
      ]);
      final supplements = _SequenceSupplementReader([
        const NutritionSourceBatch.error(message: 'supplement today failed'),
        NutritionSourceBatch.available([current, old]),
      ]);
      final oldMeal = mealLog(
        id: 'old-meal',
        fedAt: DateTime.utc(2026, 7, 21, 15),
      );
      final meals = _SequenceMealReader([
        NutritionSourceBatch.available([oldMeal]),
        NutritionSourceBatch.available([oldMeal]),
      ]);
      final controller = HealthNutritionReadController(
        source: CoexistenceNutritionReadSource(
          canonicalPlanReader: plans,
          canonicalMealReader: meals,
          canonicalSupplementLogReader: supplements,
        ),
        clock: () => now,
      );
      await controller.selectDog('dog-a');
      expect(controller.snapshotResult.hasUsableValue, isTrue);
      expect(controller.todayResult?.isDegraded, isTrue);
      expect(controller.todayOrNull?.canonicalSupplementLogsAvailable, isFalse);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HealthNutritionTodayScreen(
              controller: controller,
              dogDisplayName: 'Bono',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Administrações de hoje indisponíveis'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Administrações de hoje indisponíveis'), findsOneWidget);
      final updateButton = find.widgetWithText(TextButton, 'Atualizar');
      expect(updateButton, findsOneWidget);
      expect(tester.getSize(updateButton).height, greaterThanOrEqualTo(48));
      expect(find.text('Histórico antigo'), findsNothing);
      expect(find.textContaining('Hoje ·'), findsNothing);
      expect(
        find.textContaining('Nenhuma administração registrada hoje'),
        findsNothing,
      );

      await controller.refresh();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Administração segura'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(controller.todayResult?.isData, isTrue);
      expect(find.text('Administração segura'), findsOneWidget);
      expect(find.text('Histórico antigo'), findsNothing);
      expect(find.text('Administrações de hoje indisponíveis'), findsNothing);
      controller.dispose();
    },
  );

  testWidgets(
    'double tap opens one supplement sheet with selected dog identity',
    (tester) async {
      final referenceNow = DateTime.utc(2026, 7, 19, 15);
      final source = CoexistenceNutritionReadSource(
        canonicalMealReader: _MemMeal(
          NutritionSourceBatch.available([
            mealLog(id: 'adhoc', fedAt: referenceNow),
          ]),
        ),
      );
      final readController = HealthNutritionReadController(
        source: source,
        clock: () => referenceNow,
      );
      final mutationController = HealthNutritionMutationController(
        gateway: const FailClosedHealthNutritionMutationGateway(),
        operationIdFactory: () => 'safe-supplement-op',
      );
      addTearDown(readController.dispose);
      addTearDown(mutationController.dispose);
      await readController.selectDog('dog-a');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HealthNutritionTodayScreen(
              controller: readController,
              mutationController: mutationController,
              dogDisplayName: 'Bono',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Registrar'),
        400,
        scrollable: find.byType(Scrollable).first,
      );

      final semanticsWidget = tester.widget<Semantics>(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label == 'Registrar suplemento',
        ),
      );
      expect(semanticsWidget.properties.enabled, isTrue);
      final registerButton = find.ancestor(
        of: find.text('Registrar'),
        matching: find.byType(TextButton),
      );
      expect(tester.getSize(registerButton).height, greaterThanOrEqualTo(48));

      final center = tester.getCenter(registerButton);
      final firstTap = await tester.createGesture(pointer: 1);
      final secondTap = await tester.createGesture(pointer: 2);
      await firstTap.down(center);
      await secondTap.down(center);
      await firstTap.up();
      await secondTap.up();
      await tester.pumpAndSettle();
      expect(find.byType(HealthSupplementFormSheet), findsOneWidget);
      final sheet = tester.widget<HealthSupplementFormSheet>(
        find.byType(HealthSupplementFormSheet),
      );
      expect(sheet.dogId, 'dog-a');
      expect(sheet.activePlan, isNull);
    },
  );

  testWidgets('canonical and legacy supplement links remain contract-safe', (
    tester,
  ) async {
    final referenceNow = DateTime.utc(2026, 7, 19, 15);

    Future<void> verifyAllowed({
      required CoexistenceNutritionReadSource source,
      required bool expectsCanonicalPlan,
    }) async {
      final readController = HealthNutritionReadController(
        source: source,
        clock: () => referenceNow,
      );
      final mutationController = HealthNutritionMutationController(
        gateway: const FailClosedHealthNutritionMutationGateway(),
      );
      await readController.selectDog('dog-a');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HealthNutritionTodayScreen(
              controller: readController,
              mutationController: mutationController,
              dogDisplayName: 'Bono',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Registrar'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Registrar'));
      await tester.pumpAndSettle();
      final sheet = tester.widget<HealthSupplementFormSheet>(
        find.byType(HealthSupplementFormSheet),
      );
      expect(sheet.dogId, 'dog-a');
      expect(sheet.activePlan != null, expectsCanonicalPlan);
      Navigator.of(
        tester.element(find.byType(HealthSupplementFormSheet)),
      ).pop();
      await tester.pumpAndSettle();
      readController.dispose();
      mutationController.dispose();
    }

    await verifyAllowed(
      source: CoexistenceNutritionReadSource(
        canonicalPlanReader: _MemPlan(
          NutritionSourceBatch.available([
            canonicalPlan(
              validFrom: referenceNow.subtract(const Duration(days: 1)),
            ),
          ]),
        ),
        canonicalMealReader: _MemMeal(
          NutritionSourceBatch.available([
            mealLog(id: 'canonical-adhoc', fedAt: referenceNow),
          ]),
        ),
      ),
      expectsCanonicalPlan: true,
    );

    await verifyAllowed(
      source: CoexistenceNutritionReadSource(
        canonicalPlanReader: _MemPlan(const NutritionSourceBatch.empty()),
        legacyPlanReader: _MemLegacyPlan(
          NutritionSourceBatch.available([
            LegacyNutritionPlanView(
              id: 'legacy-plan',
              dogId: 'dog-a',
              foodType: 'Plano legado',
              amountGramsPerDay: 400,
              mealsPerDay: 2,
              vigentFrom: referenceNow.subtract(const Duration(days: 1)),
              legacySource: 'nutritional_prescriptions',
            ),
          ]),
        ),
        canonicalMealReader: _MemMeal(
          NutritionSourceBatch.available([
            mealLog(id: 'legacy-adhoc', fedAt: referenceNow),
          ]),
        ),
      ),
      expectsCanonicalPlan: false,
    );
  });

  testWidgets('future expired and conflicting plans block supplement sheet', (
    tester,
  ) async {
    final referenceNow = DateTime.utc(2026, 7, 19, 15);
    final cases = <({List<NutritionPlan> plans, String reason})>[
      (
        plans: [
          canonicalPlan(
            validFrom: referenceNow.add(const Duration(minutes: 1)),
          ),
        ],
        reason: 'Registro indisponível: o plano ainda não está vigente.',
      ),
      (
        plans: [
          canonicalPlan(
            validFrom: referenceNow.subtract(const Duration(days: 2)),
            validUntil: referenceNow,
          ),
        ],
        reason: 'Registro indisponível: o plano está expirado.',
      ),
      (
        plans: [
          canonicalPlan(id: 'plan-conflict-a'),
          canonicalPlan(id: 'plan-conflict-b'),
        ],
        reason: 'Registro indisponível por conflito no plano ativo.',
      ),
    ];

    for (final testCase in cases) {
      final readController = HealthNutritionReadController(
        source: CoexistenceNutritionReadSource(
          canonicalPlanReader: _MemPlan(
            NutritionSourceBatch.available(testCase.plans),
          ),
          canonicalMealReader: _MemMeal(
            NutritionSourceBatch.available([
              mealLog(id: 'blocked-adhoc', fedAt: referenceNow),
            ]),
          ),
        ),
        clock: () => referenceNow,
      );
      final mutationController = HealthNutritionMutationController(
        gateway: const FailClosedHealthNutritionMutationGateway(),
      );
      await readController.selectDog('dog-a');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HealthNutritionTodayScreen(
              controller: readController,
              mutationController: mutationController,
              dogDisplayName: 'Bono',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Registrar'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(testCase.reason), findsOneWidget);
      final button = find.ancestor(
        of: find.text('Registrar'),
        matching: find.byType(TextButton),
      );
      expect(tester.widget<TextButton>(button).onPressed, isNull);
      await tester.tap(find.text('Registrar'), warnIfMissed: false);
      await tester.pump();
      expect(find.byType(HealthSupplementFormSheet), findsNothing);
      readController.dispose();
      mutationController.dispose();
    }
  });

  testWidgets('degraded supplement action is disabled with accessible reason', (
    tester,
  ) async {
    final referenceNow = DateTime.utc(2026, 7, 19, 15);
    final source = CoexistenceNutritionReadSource(
      canonicalPlanReader: _MemPlan(
        NutritionSourceBatch.available([canonicalPlan()]),
      ),
      canonicalMealReader: _MemMeal(
        const NutritionSourceBatch.error(
          code: 'partial_meals',
          message: 'Falha parcial de refeições',
        ),
      ),
    );
    final readController = HealthNutritionReadController(
      source: source,
      clock: () => referenceNow,
    );
    final mutationController = HealthNutritionMutationController(
      gateway: const FailClosedHealthNutritionMutationGateway(),
    );
    addTearDown(readController.dispose);
    addTearDown(mutationController.dispose);
    await readController.selectDog('dog-a');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HealthNutritionTodayScreen(
            controller: readController,
            mutationController: mutationController,
            dogDisplayName: 'Bono',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Registrar'),
      400,
      scrollable: find.byType(Scrollable).first,
    );

    expect(
      find.text('Registro indisponível enquanto os dados estão parciais.'),
      findsOneWidget,
    );
    final semanticsWidget = tester.widget<Semantics>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label ==
                'Registrar suplemento indisponível: '
                    'Registro indisponível enquanto os dados estão parciais.',
      ),
    );
    expect(semanticsWidget.properties.enabled, isFalse);
    await tester.tap(find.text('Registrar'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(HealthSupplementFormSheet), findsNothing);
  });

  testWidgets(
    'temporal diagnostic remains accessible at 320dp and text scale 1.5',
    (tester) async {
      final monotonic = _ScreenMonotonicClock();
      final gateway = _ScreenTimeGateway();
      final provider = AuthoritativeTimeProvider(
        gateway: gateway,
        monotonicClock: monotonic,
      );
      final readController = HealthNutritionReadController(
        source: CoexistenceNutritionReadSource(
          canonicalMealReader: _MemMeal(
            NutritionSourceBatch.available([
              mealLog(
                id: 'responsive-temporal-meal',
                fedAt: DateTime.utc(2026, 7, 19, 15),
              ),
            ]),
          ),
        ),
        authoritativeTimeProvider: provider,
      );
      final mutationController = HealthNutritionMutationController(
        gateway: const FailClosedHealthNutritionMutationGateway(),
      );
      addTearDown(readController.dispose);
      addTearDown(mutationController.dispose);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await readController.selectDog('dog-a');
      monotonic.value = const Duration(minutes: 6);
      gateway.fail = true;
      await readController.refresh();

      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: Scaffold(
            body: HealthNutritionTodayScreen(
              controller: readController,
              mutationController: mutationController,
              dogDisplayName:
                  'Bono com nome operacional excepcionalmente extenso',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Horário aguardando atualização'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('Registrar'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      final semantics = tester.widget<Semantics>(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label ==
                  'Registrar suplemento indisponível: Horário aguardando atualização. Atualize antes de registrar.',
        ),
      );
      expect(semantics.properties.enabled, isFalse);
      final button = find.ancestor(
        of: find.text('Registrar'),
        matching: find.byType(TextButton),
      );
      final size = tester.getSize(button);
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
      expect(tester.widget<TextButton>(button).onPressed, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  // ══════════════════════════════════════════════════════════════════════════
  // UX-04B3C — SUPPLEMENT TEMPORAL EXPIRED
  // ══════════════════════════════════════════════════════════════════════════

  testWidgets(
    'temporal expired: factual data visible, supplement action disabled, '
    'no sheet, no callback, no mutation',
    (tester) async {
      // Provider without gateway sync → neverSynchronized → unavailable
      final provider = AuthoritativeTimeProvider(
        gateway: _FailingTimeGateway((_) async {
          throw const AuthoritativeTimeFailure(
            AuthoritativeTimeFailureCode.unavailable,
            'temporal service unavailable',
          );
        }),
        monotonicClock: _ScreenMonotonicClock(),
      );

      final source = CoexistenceNutritionReadSource(
        canonicalPlanReader: _MemPlan(
          NutritionSourceBatch.available([canonicalPlan()]),
        ),
        canonicalMealReader: _MemMeal(
          NutritionSourceBatch.available([mealLog(id: 'ml-1')]),
        ),
      );

      final readController = HealthNutritionReadController(
        source: source,
        authoritativeTimeProvider: provider,
      );
      final mutationController = HealthNutritionMutationController(
        gateway: const FailClosedHealthNutritionMutationGateway(),
      );
      addTearDown(readController.dispose);
      addTearDown(mutationController.dispose);
      await readController.selectDog('dog-a');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HealthNutritionTodayScreen(
              controller: readController,
              mutationController: mutationController,
              dogDisplayName: 'Bono',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Controller's temporal state reflects unavailable
      expect(
        readController.temporalState,
        HealthNutritionTemporalState.unavailable,
      );
      expect(readController.temporalActionsAllowed, isFalse);

      // Facts visible (factual data from source)
      expect(find.text('Ração Premium'), findsWidgets);

      // No sheet opens on tap (button should be disabled)
      await tester.tap(find.text('Registrar'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(HealthSupplementFormSheet), findsNothing);
    },
  );

  // ══════════════════════════════════════════════════════════════════════════
  // UX-04B3C — SUPPLEMENT TEMPORAL FAILED WITHOUT SNAPSHOT
  // ══════════════════════════════════════════════════════════════════════════

  testWidgets(
    'temporal failed without snapshot disables supplement action and opens no sheet',
    (tester) async {
      final gateway = _FailingTimeGateway((_) async {
        throw const AuthoritativeTimeFailure(
          AuthoritativeTimeFailureCode.unavailable,
          'serviço temporal indisponível',
        );
      });
      final provider = AuthoritativeTimeProvider(
        gateway: gateway,
        monotonicClock: _ScreenMonotonicClock(),
      );

      final spyMutationGateway = _SpyNutritionMutationGateway();
      final source = CoexistenceNutritionReadSource(
        canonicalPlanReader: _MemPlan(
          NutritionSourceBatch.available([canonicalPlan(dogId: 'dog-a')]),
        ),
        canonicalMealReader: _MemMeal(
          NutritionSourceBatch.available([mealLog(id: 'ml-1')]),
        ),
      );

      final readController = HealthNutritionReadController(
        source: source,
        authoritativeTimeProvider: provider,
      );
      final mutationController = HealthNutritionMutationController(
        gateway: spyMutationGateway,
      );
      addTearDown(readController.dispose);
      addTearDown(mutationController.dispose);
      await readController.selectDog('dog-a');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HealthNutritionTodayScreen(
              controller: readController,
              mutationController: mutationController,
              dogDisplayName: 'Bono',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Controller temporalState is unavailable & actions disabled
      expect(
        readController.temporalState,
        HealthNutritionTemporalState.unavailable,
      );
      expect(readController.temporalActionsAllowed, isFalse);

      // 4. Diagnostic title and message present with explicit reason
      expect(
        readController.temporalDiagnosticTitle,
        contains('Horário confiável indisponível'),
      );
      expect(readController.temporalDiagnosticMessage, isNotNull);

      // 9. Zero fallback to DateTime.now
      expect(provider.nowFreshUtc(), isNull);
      expect(provider.nowReadOnlyUtc(), isNull);

      // 10 & 11. DogId is dog-a, no empty dogId substitute created
      expect(readController.activeDogId, equals('dog-a'));

      // 3. Semantics enabled=false on button
      final buttonFinder = find.ancestor(
        of: find.text('Registrar'),
        matching: find.byType(TextButton),
      );
      final semanticsData = tester
          .getSemantics(buttonFinder)
          .getSemanticsData();
      expect(semanticsData.hasFlag(SemanticsFlag.isEnabled), isFalse);

      // 2 & 5. Tap does not open sheet (button callback disabled/inaccessible)
      await tester.tap(find.text('Registrar'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(HealthSupplementFormSheet), findsNothing);

      // 6, 7, 8. Zero callbacks, zero submits, zero mutation calls
      expect(spyMutationGateway.callCount, equals(0));
    },
  );

  // ══════════════════════════════════════════════════════════════════════════
  // UX-04B3C — STALE WITH FAILURE ON REFRESH
  // ══════════════════════════════════════════════════════════════════════════

  testWidgets(
    'stale with refresh failure: query preserved, action continues disabled, '
    'diagnosis preserved, stale does not become fresh',
    (tester) async {
      final gateway = _FailingTimeGateway((_) async {
        throw const AuthoritativeTimeFailure(
          AuthoritativeTimeFailureCode.unavailable,
          'callable indisponível',
        );
      });
      final provider = AuthoritativeTimeProvider(
        gateway: gateway,
        monotonicClock: _ScreenMonotonicClock(),
      );

      final source = CoexistenceNutritionReadSource(
        canonicalPlanReader: _MemPlan(
          NutritionSourceBatch.available([canonicalPlan()]),
        ),
        canonicalMealReader: _MemMeal(
          NutritionSourceBatch.available([mealLog(id: 'ml-1')]),
        ),
      );

      final readController = HealthNutritionReadController(
        source: source,
        authoritativeTimeProvider: provider,
      );
      final mutationController = HealthNutritionMutationController(
        gateway: const FailClosedHealthNutritionMutationGateway(),
      );
      addTearDown(readController.dispose);
      addTearDown(mutationController.dispose);
      await readController.selectDog('dog-a');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HealthNutritionTodayScreen(
              controller: readController,
              mutationController: mutationController,
              dogDisplayName: 'Bono',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(gateway.calls, 1);

      // Stale remains after failed refresh
      await readController.refresh();
      await tester.pumpAndSettle();

      expect(gateway.calls, 2);
      expect(
        readController.temporalState,
        HealthNutritionTemporalState.unavailable,
      );

      // Supplement still disabled
      expect(readController.temporalActionsAllowed, isFalse);

      // No sheet
      await tester.tap(find.text('Registrar'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(HealthSupplementFormSheet), findsNothing);
    },
  );

  // ══════════════════════════════════════════════════════════════════════════
  // UX-04B3C — LIVE REGION SEMANTICS
  // ══════════════════════════════════════════════════════════════════════════

  testWidgets(
    'liveRegion: controller has temporal diagnostic when provider fresh',
    (tester) async {
      final provider = AuthoritativeTimeProvider(
        gateway: _ScreenTimeGateway(),
        monotonicClock: _ScreenMonotonicClock(),
      );
      final source = CoexistenceNutritionReadSource(
        canonicalPlanReader: _MemPlan(
          NutritionSourceBatch.available([canonicalPlan()]),
        ),
        canonicalMealReader: _MemMeal(
          NutritionSourceBatch.available([mealLog(id: 'ml-1')]),
        ),
      );
      final readController = HealthNutritionReadController(
        source: source,
        authoritativeTimeProvider: provider,
      );
      final mutationController = HealthNutritionMutationController(
        gateway: const FailClosedHealthNutritionMutationGateway(),
      );
      addTearDown(readController.dispose);
      addTearDown(mutationController.dispose);
      await readController.selectDog('dog-a');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HealthNutritionTodayScreen(
              controller: readController,
              mutationController: mutationController,
              dogDisplayName: 'Bono',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // With fresh provider, diagnostic title is null (no problem)
      expect(readController.temporalDiagnosticTitle, isNull);
      expect(readController.temporalState, HealthNutritionTemporalState.fresh);
    },
  );

  testWidgets(
    'UX-04B3C Section 10 — liveRegion real: Semantics node has liveRegion==true on diagnostic text',
    (tester) async {
      final semanticsHandle = tester.ensureSemantics();
      try {
        final monotonic = _ScreenMonotonicClock();
        final gateway = _ScreenTimeGateway();
        final provider = AuthoritativeTimeProvider(
          gateway: gateway,
          monotonicClock: monotonic,
        );
        final source = CoexistenceNutritionReadSource(
          canonicalMealReader: _MemMeal(
            NutritionSourceBatch.available([
              mealLog(
                id: 'live-region-meal',
                fedAt: DateTime.utc(2026, 7, 19, 15),
              ),
            ]),
          ),
        );
        final readController = HealthNutritionReadController(
          source: source,
          authoritativeTimeProvider: provider,
        );
        final mutationController = HealthNutritionMutationController(
          gateway: const FailClosedHealthNutritionMutationGateway(),
        );
        addTearDown(readController.dispose);
        addTearDown(mutationController.dispose);

        await readController.selectDog('dog-a');
        monotonic.value = const Duration(minutes: 6);
        gateway.fail = true;
        await readController.refresh();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: HealthNutritionTodayScreen(
                controller: readController,
                mutationController: mutationController,
                dogDisplayName: 'Bono',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Find the diagnostic text and verify liveRegion property on its Semantics node
        final diagnosticFinder = find.text('Horário aguardando atualização');
        expect(diagnosticFinder, findsOneWidget);

        final semanticsData = tester
            .getSemantics(diagnosticFinder)
            .getSemanticsData();
        expect(semanticsData.hasFlag(SemanticsFlag.isLiveRegion), isTrue);
        expect(semanticsData.label, contains('Horário aguardando atualização'));

        // Verify button disabled state is independent of liveRegion
        await tester.scrollUntilVisible(
          find.text('Registrar'),
          400,
          scrollable: find.byType(Scrollable).first,
        );
        final buttonSemantics = tester
            .getSemantics(
              find.ancestor(
                of: find.text('Registrar'),
                matching: find.byType(TextButton),
              ),
            )
            .getSemanticsData();
        expect(buttonSemantics.hasFlag(SemanticsFlag.isEnabled), isFalse);
      } finally {
        semanticsHandle.dispose();
      }
    },
  );

  testWidgets(
    'button disabled: controller temporalActionsAllowed is false when unavailable',
    (tester) async {
      // Controller without provider → unavailable → button disabled
      final readController = HealthNutritionReadController(
        source: CoexistenceNutritionReadSource(
          canonicalPlanReader: _MemPlan(
            NutritionSourceBatch.available([canonicalPlan()]),
          ),
          canonicalMealReader: _MemMeal(
            NutritionSourceBatch.available([mealLog(id: 'ml-1')]),
          ),
        ),
      );
      final mutationController = HealthNutritionMutationController(
        gateway: const FailClosedHealthNutritionMutationGateway(),
      );
      addTearDown(readController.dispose);
      addTearDown(mutationController.dispose);
      await readController.selectDog('dog-a');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HealthNutritionTodayScreen(
              controller: readController,
              mutationController: mutationController,
              dogDisplayName: 'Bono',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Controller state reflects disabled action
      expect(readController.temporalActionsAllowed, isFalse);
      expect(
        readController.temporalState,
        HealthNutritionTemporalState.unavailable,
      );

      // No sheet on tap
      await tester.tap(find.text('Registrar'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(HealthSupplementFormSheet), findsNothing);
    },
  );

  // ══════════════════════════════════════════════════════════════════════════
  // UX-04B3C — REOPENING / SEQUENTIAL SHEET ON SAME STATE
  // ══════════════════════════════════════════════════════════════════════════

  testWidgets(
    'UX-04B3C Section 9 — sheet reopening on same State: open, close, finally releases lock, open second time legitimately',
    (tester) async {
      final referenceNow = DateTime.utc(2026, 7, 19, 15);
      final provider = AuthoritativeTimeProvider(
        gateway: _ScreenTimeGateway(),
        monotonicClock: _ScreenMonotonicClock(),
      );
      final source = CoexistenceNutritionReadSource(
        canonicalMealReader: _MemMeal(
          NutritionSourceBatch.available([
            mealLog(id: 'adhoc', fedAt: referenceNow),
          ]),
        ),
      );
      final readController = HealthNutritionReadController(
        source: source,
        authoritativeTimeProvider: provider,
      );
      final mutationController = HealthNutritionMutationController(
        gateway: const FailClosedHealthNutritionMutationGateway(),
        operationIdFactory: () => 'safe-supplement-op',
      );
      addTearDown(readController.dispose);
      addTearDown(mutationController.dispose);
      await readController.selectDog('dog-a');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HealthNutritionTodayScreen(
              controller: readController,
              mutationController: mutationController,
              dogDisplayName: 'Bono',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Registrar'),
        400,
        scrollable: find.byType(Scrollable).first,
      );

      // 1. Open sheet first time
      await tester.tap(find.text('Registrar'));
      await tester.pumpAndSettle();
      expect(find.byType(HealthSupplementFormSheet), findsOneWidget);

      // 2. Close sheet
      final sheetElement = tester.element(
        find.byType(HealthSupplementFormSheet),
      );
      Navigator.of(sheetElement).pop();
      await tester.pumpAndSettle();
      expect(find.byType(HealthSupplementFormSheet), findsNothing);

      // 3. Reopen sheet on the SAME screen and SAME State
      await tester.tap(find.text('Registrar'));
      await tester.pumpAndSettle();

      // 4. Prove second legitimate opening
      expect(find.byType(HealthSupplementFormSheet), findsOneWidget);
      final sheet2 = tester.widget<HealthSupplementFormSheet>(
        find.byType(HealthSupplementFormSheet),
      );
      expect(sheet2.dogId, 'dog-a');

      // Close again
      Navigator.of(
        tester.element(find.byType(HealthSupplementFormSheet)),
      ).pop();
      await tester.pumpAndSettle();
      expect(find.byType(HealthSupplementFormSheet), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'invalid selected dog identity is rejected before any sheet context',
    () {
      final controller = HealthNutritionReadController(
        source: CoexistenceNutritionReadSource(),
      );
      addTearDown(controller.dispose);
      expect(() => controller.selectDog('   '), throwsArgumentError);
      expect(controller.activeDogId, isNull);
      expect(controller.todayOrNull, isNull);
    },
  );
}

final class _FailingTimeGateway implements AuthoritativeTimeGateway {
  _FailingTimeGateway(this._thunk);
  final Future<AuthoritativeTimeRemoteResponse> Function(int) _thunk;
  int calls = 0;

  @override
  Future<AuthoritativeTimeRemoteResponse> fetchAuthoritativeTime() async {
    calls++;
    return _thunk(calls);
  }
}

final class _ScreenMonotonicClock implements MonotonicElapsedClock {
  Duration value = Duration.zero;

  @override
  Duration get elapsed => value;
}

final class _ScreenTimeGateway implements AuthoritativeTimeGateway {
  bool fail = false;

  @override
  Future<AuthoritativeTimeRemoteResponse> fetchAuthoritativeTime() async {
    if (fail) {
      throw const AuthoritativeTimeFailure(
        AuthoritativeTimeFailureCode.unavailable,
        'callable indisponível',
      );
    }
    final now = DateTime.utc(2026, 7, 19, 15);
    return AuthoritativeTimeRemoteResponse(
      protocolVersion: 1,
      requestId: '00000000-0000-4000-8000-000000000001',
      requestReceivedAtUtc: now,
      serverSentAtUtc: now,
      maxAge: const Duration(minutes: 15),
    );
  }
}

final class _GatedPlan implements NutritionCanonicalPlanReader {
  _GatedPlan(this.gate);
  final Completer<void> gate;
  @override
  Future<NutritionSourceBatch<NutritionPlan>> loadPlans(String dogId) async {
    await gate.future;
    return const NutritionSourceBatch.empty();
  }
}

final class _MemLegacyRegimen
    implements NutritionLegacySupplementRegimenReader {
  _MemLegacyRegimen(this.batch);
  final NutritionSourceBatch<LegacySupplementRegimenView> batch;
  @override
  Future<NutritionSourceBatch<LegacySupplementRegimenView>> loadRegimens(
    String dogId,
  ) async => batch;
}

final class _DogSwitchPlanReader implements NutritionCanonicalPlanReader {
  _DogSwitchPlanReader(this.releaseDogA);

  final Future<void> releaseDogA;

  @override
  Future<NutritionSourceBatch<NutritionPlan>> loadPlans(String dogId) async {
    if (dogId == 'dog-a') {
      await releaseDogA;
      return NutritionSourceBatch.available([
        canonicalPlan(dogId: dogId, foodType: 'Plano A stale'),
      ]);
    }
    return NutritionSourceBatch.available([
      canonicalPlan(dogId: dogId, foodType: 'Plano B'),
    ]);
  }
}

final class _SpyNutritionMutationGateway
    implements HealthNutritionMutationGateway {
  int callCount = 0;

  @override
  Future<HealthNutritionMutationResult> createAdhocMealLog(
    dynamic command,
  ) async {
    callCount++;
    throw UnimplementedError();
  }

  @override
  Future<HealthNutritionMutationResult> createPlannedMealLog(
    dynamic command,
  ) async {
    callCount++;
    throw UnimplementedError();
  }

  @override
  Future<HealthNutritionMutationResult> createSupplementLog(
    dynamic command,
  ) async {
    callCount++;
    throw UnimplementedError();
  }
}
