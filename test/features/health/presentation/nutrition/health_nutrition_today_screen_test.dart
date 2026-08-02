import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/data/coexistence/nutrition/coexistence_nutrition_read_source.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/legacy_nutrition_views.dart';
import 'package:canil_gcm/features/health/domain/meal_occurrence.dart';
import 'package:canil_gcm/features/health/domain/meal_schedule_slot.dart';
import 'package:canil_gcm/features/health/domain/nutrition_plan.dart';
import 'package:canil_gcm/features/health/domain/nutrition_read_models.dart';
import 'package:canil_gcm/features/health/domain/nutrition_read_state.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_read_controller.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_today_screen.dart';

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
  String dogId = 'dog-a',
  String foodType = 'Ração Premium',
  double amountGramsPerDay = 600,
  String timezone = NutritionPlan.defaultTimezone,
}) {
  return NutritionPlan(
    id: 'plan-1',
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
    validFrom: DateTime.utc(2026, 1, 1),
    timezone: timezone,
    recordedBy: actor,
    status: NutritionPlanStatus.active,
    schemaVersion: 1,
    revision: 1,
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

    expect(find.textContaining('Ração Premium'), findsOneWidget);
    expect(find.textContaining('MANHÃ'), findsWidgets);
    expect(find.textContaining('Plano ativo'), findsOneWidget);
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
    final controller = HealthNutritionReadController(source: source);
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

    expect(find.text('Oferecido: 500 g de 500 g'), findsOneWidget);
    expect(find.text('Consumido conhecido: 250 g de 500 g'), findsOneWidget);
    expect(find.text('Há refeições sem quantidade consumida'), findsOneWidget);
    final bars = tester
        .widgetList<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        )
        .toList();
    expect(bars[0].value, 1);
    expect(bars[1].value, 0.5);
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
    final controller = HealthNutritionReadController(source: source);
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
      find.text('Quantidade consumida não medida'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Aceitou tudo'), findsOneWidget);
    expect(find.text('Quantidade consumida não medida'), findsOneWidget);
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
    final controller = HealthNutritionReadController(source: source);
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
    final controller = HealthNutritionReadController(source: source);

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
    final controller = HealthNutritionReadController(source: source);
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
      expect(find.textContaining('Plano ativo'), findsOneWidget);
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
    expect(find.textContaining('Em uso (legado)'), findsOneWidget);
    expect(
      find.textContaining('Não é uma administração pontual'),
      findsOneWidget,
    );
    expect(find.textContaining('ADMINISTRAÇÕES REGISTRADAS'), findsOneWidget);
    controller.dispose();
  });
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
