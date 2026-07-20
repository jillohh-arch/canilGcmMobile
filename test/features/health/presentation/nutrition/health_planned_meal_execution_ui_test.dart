import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/data/coexistence/nutrition/coexistence_nutrition_read_source.dart';
import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_commands.dart';
import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_errors.dart';
import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/meal_schedule_slot.dart';
import 'package:canil_gcm/features/health/domain/nutrition_plan.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_mutation_controller.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_pending_intent.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_read_controller.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_today_screen.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_planned_meal_form_sheet.dart';

final _actor = RecordedBy(uid: 'u1', name: 'Silva', internalRole: 'condutor');

NutritionPlan _plan() => NutritionPlan(
  id: 'plan-1',
  dogId: 'dog-a',
  foodType: 'Ração operacional',
  amountGramsPerDay: 600,
  mealsPerDay: 2,
  mealSchedule: [
    MealScheduleSlot(
      id: 'slot-am',
      period: MealPeriodWire.parseCanonical('morning'),
      scheduledTime: ScheduledTimeOfDay('07:00'),
      targetGrams: 300,
    ),
    MealScheduleSlot(
      id: 'slot-pm',
      period: MealPeriodWire.parseCanonical('night'),
      scheduledTime: ScheduledTimeOfDay('18:30'),
      targetGrams: 300,
    ),
  ],
  validFrom: DateTime.utc(2026, 1, 1),
  timezone: NutritionPlan.defaultTimezone,
  recordedBy: _actor,
  status: NutritionPlanStatus.active,
  schemaVersion: 1,
  revision: 1,
);

MealLog _completedMeal() => MealLog(
  id: 'mo1-completed',
  dogId: 'dog-a',
  period: MealPeriodWire.parseCanonical('morning'),
  offeredGrams: 300,
  consumedGrams: 300,
  acceptance: MealAcceptanceWire.parse('full'),
  fedAt: DateTime.now().toUtc(),
  recordedBy: _actor,
  schemaVersion: 1,
  revision: 1,
  planId: 'plan-1',
  plannedMealId: 'slot-am',
  mealOccurrenceId: 'mo1-completed',
);

final class _PlanReader implements NutritionCanonicalPlanReader {
  _PlanReader(this.batch);
  NutritionSourceBatch<NutritionPlan> batch;
  @override
  Future<NutritionSourceBatch<NutritionPlan>> loadPlans(String dogId) async =>
      batch;
}

final class _MealReader implements NutritionCanonicalMealReader {
  _MealReader(this.batch);
  NutritionSourceBatch<MealLog> batch;
  @override
  Future<NutritionSourceBatch<MealLog>> loadMeals(
    String dogId, {
    DateTime? from,
    DateTime? to,
  }) async => batch;
}

final class _Gateway implements HealthNutritionMutationGateway {
  final commands = <CreatePlannedMealLogCommand>[];
  HealthNutritionMutationResult result = const CreateMealLogSuccess(
    dogId: 'dog-a',
    mealId: 'mo1-new',
    revision: 1,
    wasNoOp: false,
    operationId: 'op-ui',
    mealOccurrenceId: 'mo1-new',
  );
  Completer<void>? gate;

  @override
  Future<HealthNutritionMutationResult> createPlannedMealLog(
    CreatePlannedMealLogCommand command,
  ) async {
    commands.add(command);
    await gate?.future;
    return result;
  }

  @override
  Future<HealthNutritionMutationResult> createAdhocMealLog(
    CreateAdhocMealLogCommand command,
  ) async => throw UnimplementedError();

  @override
  Future<HealthNutritionMutationResult> createSupplementLog(
    CreateSupplementLogCommand command,
  ) async => throw UnimplementedError();
}

Future<
  ({
    HealthNutritionReadController read,
    HealthNutritionMutationController mutation,
    _Gateway gateway,
    _MealReader meals,
  })
>
_pump(
  WidgetTester tester, {
  bool degraded = false,
  bool completed = false,
  HealthNutritionPendingIntentHolder? holder,
}) async {
  final planReader = _PlanReader(NutritionSourceBatch.available([_plan()]));
  final mealReader = _MealReader(
    degraded
        ? const NutritionSourceBatch.error(code: 'down', message: 'down')
        : NutritionSourceBatch.available(
            completed ? [_completedMeal()] : const <MealLog>[],
          ),
  );
  final read = HealthNutritionReadController(
    source: CoexistenceNutritionReadSource(
      canonicalPlanReader: planReader,
      canonicalMealReader: mealReader,
    ),
  );
  await read.selectDog('dog-a');
  final gateway = _Gateway();
  var seq = 0;
  final mutation = HealthNutritionMutationController(
    gateway: gateway,
    pendingIntentHolder: holder,
    operationIdFactory: () => 'op-${++seq}',
    onRefreshAfterSuccess: read.refresh,
  );
  addTearDown(read.dispose);
  addTearDown(mutation.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: HealthNutritionTodayScreen(
          controller: read,
          mutationController: mutation,
          dogDisplayName: 'Bono',
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (read: read, mutation: mutation, gateway: gateway, meals: mealReader);
}

Future<void> _openFirstForm(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('Registrar refeição').first,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(find.text('Registrar refeição').first);
  await tester.pumpAndSettle();
  expect(find.text('REGISTRAR REFEIÇÃO'), findsWidgets);
}

void main() {
  testWidgets('CTA only for healthy canonical pending/late', (tester) async {
    await _pump(tester);
    await tester.scrollUntilVisible(
      find.text('Registrar refeição').first,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Registrar refeição'), findsNWidgets(2));
  });

  testWidgets('completed slot has no second create CTA for that slot', (
    tester,
  ) async {
    await _pump(tester, completed: true);
    await tester.scrollUntilVisible(
      find.text('Registrar refeição'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Registrar refeição'), findsOneWidget);
    expect(find.text('Concluída'), findsOneWidget);
  });

  testWidgets('canonical degraded fails closed with zero CTA', (tester) async {
    await _pump(tester, degraded: true);
    expect(find.text('Registrar refeição'), findsNothing);
    expect(find.textContaining('Leitura parcial'), findsOneWidget);
  });

  testWidgets('unknown preserves consumed null and payload intent boundary', (
    tester,
  ) async {
    final host = await _pump(tester);
    await _openFirstForm(tester);
    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, 'REGISTRAR REFEIÇÃO'),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'REGISTRAR REFEIÇÃO'));
    await tester.pumpAndSettle();
    final command = host.gateway.commands.single;
    expect(command.consumedGrams, isNull);
    expect(command.planId, 'plan-1');
    expect(command.plannedMealId, 'slot-am');
    expect(command.operationId, 'op-1');
  });

  testWidgets('refused forces zero and partial bounds validate', (
    tester,
  ) async {
    await _pump(tester);
    await _openFirstForm(tester);
    await tester.tap(find.text('Não informado'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recusou').last);
    await tester.pumpAndSettle();
    final consumed = tester.widget<TextFormField>(
      find.widgetWithText(TextFormField, 'Quantidade consumida (g) — opcional'),
    );
    expect(consumed.controller!.text, '0');
  });

  testWidgets('double tap produces one gateway invocation', (tester) async {
    final host = await _pump(tester);
    host.gateway.gate = Completer<void>();
    await _openFirstForm(tester);
    final submit = find.widgetWithText(FilledButton, 'REGISTRAR REFEIÇÃO');
    await tester.scrollUntilVisible(
      submit,
      250,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(submit);
    await tester.tap(submit);
    await tester.pump();
    expect(host.gateway.commands, hasLength(1));
    host.gateway.gate!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('uncertain close/reopen restores payload and operationId', (
    tester,
  ) async {
    final holder = HealthNutritionPendingIntentHolder();
    final host = await _pump(tester, holder: holder);
    host.gateway.result = const HealthNutritionMutationErrorResult(
      HealthNutritionMutationUnavailable(),
    );
    await _openFirstForm(tester);
    final offered = find.widgetWithText(
      TextFormField,
      'Quantidade oferecida (g)',
    );
    await tester.enterText(offered, '275');
    final submit = find.widgetWithText(FilledButton, 'REGISTRAR REFEIÇÃO');
    await tester.scrollUntilVisible(
      submit,
      250,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(find.textContaining('Não foi possível confirmar'), findsOneWidget);
    final firstOp = host.gateway.commands.single.operationId;
    Navigator.of(tester.element(find.byType(HealthPlannedMealFormSheet))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(HealthPlannedMealFormSheet), findsNothing);
    await _openFirstForm(tester);
    expect(find.text('275'), findsOneWidget);
    await tester.scrollUntilVisible(
      submit,
      250,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(host.gateway.commands, hasLength(2));
    expect(host.gateway.commands.last.operationId, firstOp);
  });
}
