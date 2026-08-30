import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/data/coexistence/nutrition/coexistence_nutrition_read_source.dart';
import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_commands.dart';
import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_errors.dart';
import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/meal_occurrence.dart';
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

MealLog _completedMeal({
  String planId = 'plan-1',
  String idSuffix = 'completed',
}) {
  final fedAt = DateTime.now().toUtc();
  final localServiceDate = LocalServiceDate.fromInstant(
    fedAt,
    timezone: NutritionPlan.defaultTimezone,
  );
  final occurrence = MealOccurrenceId.v1(
    MealOccurrenceKey(
      dogId: 'dog-a',
      planId: planId,
      plannedMealId: 'slot-am',
      localServiceDate: localServiceDate,
    ),
  ).value;
  return MealLog(
    id: 'mo1-$idSuffix-$planId',
    dogId: 'dog-a',
    period: MealPeriodWire.parseCanonical('morning'),
    offeredGrams: 300,
    consumedGrams: 300,
    acceptance: MealAcceptanceWire.parse('full'),
    fedAt: fedAt,
    recordedBy: _actor,
    schemaVersion: 1,
    revision: 1,
    planId: planId,
    plannedMealId: 'slot-am',
    mealOccurrenceId: occurrence,
  );
}

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
  MealLog? mealOverride,
  List<MealLog>? mealOverrides,
  HealthNutritionPendingIntentHolder? holder,
  TextScaler? textScaler,
}) async {
  final planReader = _PlanReader(NutritionSourceBatch.available([_plan()]));
  final mealReader = _MealReader(
    degraded
        ? const NutritionSourceBatch.error(code: 'down', message: 'down')
        : NutritionSourceBatch.available(
            mealOverrides ??
                (mealOverride != null
                ? [mealOverride]
                : completed
                ? [_completedMeal()]
                : const <MealLog>[]),
          ),
  );
  final read = HealthNutritionReadController(
    source: CoexistenceNutritionReadSource(
      canonicalPlanReader: planReader,
      canonicalMealReader: mealReader,
    ),
    clock: () => DateTime.now().toUtc(),
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
        body: MediaQuery(
          data: MediaQueryData(
            size: Size(
              tester.view.physicalSize.width / tester.view.devicePixelRatio,
              tester.view.physicalSize.height / tester.view.devicePixelRatio,
            ),
            textScaler: textScaler ?? TextScaler.noScaling,
          ),
          child: HealthNutritionTodayScreen(
            controller: read,
            mutationController: mutation,
            dogDisplayName: 'Bono',
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (read: read, mutation: mutation, gateway: gateway, meals: mealReader);
}

Future<void> _openFirstForm(WidgetTester tester) async {
  final btn = find.textContaining('Registrar').first;
  await tester.scrollUntilVisible(
    btn,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(btn);
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

  testWidgets('same slot from another plan keeps active-plan CTA', (
    tester,
  ) async {
    await _pump(tester, mealOverride: _completedMeal(planId: 'plan-2'));
    await tester.scrollUntilVisible(
      find.text('Registrar refeição').first,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Registrar refeição'), findsNWidgets(2));
    expect(find.text('Concluída'), findsNothing);
  });

  testWidgets('duplicate occurrence communicates integrity and blocks slot CTA', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(
      tester,
      mealOverrides: [
        _completedMeal(idSuffix: 'duplicate-a'),
        _completedMeal(idSuffix: 'duplicate-b'),
      ],
    );

    expect(find.text('Dados inconsistentes'), findsWidgets);
    expect(
      find.text(
        'Execução duplicada detectada. Ação temporariamente indisponível.',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        'Execução duplicada detectada. Ação temporariamente indisponível.',
      ),
      findsOneWidget,
    );
    expect(find.text('Registrar refeição'), findsOneWidget);
    expect(find.text('Concluída'), findsNothing);
    semantics.dispose();
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
    // PASS 02B: formulário fresco inicia com full + consumed = offered.
    // Para testar que "null" (não medido) é preservado no payload,
    // o usuário precisa explicitamente selecionar "Não medido".
    await tester.tap(find.text('Não informado'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Não medido'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, 'REGISTRAR REFEIÇÃO'),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'REGISTRAR REFEIÇÃO'));
    await tester.pumpAndSettle();
    final command = host.gateway.commands.single;
    // null = "não medido" preservado no payload — a regra de domínio que o teste
    // verificava continua sendo respeitada, só que agora requer interação explícita.
    expect(command.consumedGrams, isNull);
    expect(command.planId, 'plan-1');
    expect(command.plannedMealId, 'slot-am');
    expect(command.operationId, 'op-1');
  });

  testWidgets('refused forces zero and partial bounds validate', (
    tester,
  ) async {
    final host = await _pump(tester);
    await _openFirstForm(tester);
    // PASS 02B: formulário inicia em full + all (consumed = offered).
    // Campo de consumed NÃO está visível no estado inicial.
    // Verificamos ausência antes de qualquer interação.
    expect(find.byKey(const Key('consumed-field')), findsNothing);
    // Scroll até o chip "Parcial".
    final partialChip = find.byKey(const Key('planned-meal-consumed-Parcial'));
    await tester.ensureVisible(partialChip);
    await tester.pumpAndSettle();
    await tester.tap(partialChip);
    await tester.pumpAndSettle();
    // Confirma que o ChoiceChip ficou selected.
    final chipAfterTap = tester.widget<ChoiceChip>(partialChip);
    expect(chipAfterTap.selected, isTrue,
        reason: 'Parcial deve estar selecionado após tap');
    // Campo de consumed deve aparecer (mode=partial, refused=false).
    final consumedFieldFinder = find.byKey(const Key('consumed-field'));
    expect(consumedFieldFinder, findsOneWidget,
        reason: 'Parcial revela o campo de consumed');
    // Tocamos "Recusou" — `_onAcceptanceChanged` força consumed = 0 e esconde.
    final refusedChip = find.byKey(const Key('planned-meal-acceptance-refused'));
    await tester.ensureVisible(refusedChip);
    await tester.pumpAndSettle();
    await tester.tap(refusedChip);
    await tester.pumpAndSettle();
    // Campo escondido após a seleção.
    expect(consumedFieldFinder, findsNothing,
        reason: 'Recusou força modo all, que esconde o campo de consumed');
    // Validação do valor real: Submit e verifica que o gateway recebeu consumed=0.
    final submit = find.widgetWithText(FilledButton, 'REGISTRAR REFEIÇÃO');
    await tester.scrollUntilVisible(
      submit,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(host.gateway.commands.single.consumedGrams, 0);
    expect(host.gateway.commands.single.operationId, 'op-1');
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
    // Altera offered de 300 para 275 (sem usar widgetWithText para evitar ambiguidade).
    final offeredField = find.byType(TextFormField).first;
    await tester.enterText(offeredField, '275');
    await tester.pump();
    // Desfoca o campo para garantir que o valor está no controller.
    await tester.tapAt(tester.getRect(offeredField).center);
    await tester.pumpAndSettle();
    // Toca no botão REGISTRAR (FilledButton.last).
    final submitBtn = find.byType(FilledButton);
    await tester.ensureVisible(submitBtn.last);
    await tester.pumpAndSettle();
    await tester.tap(submitBtn.last);
    await tester.pumpAndSettle();
    // PASS 02B: Unavailable é retry silencioso — formulário continua aberto.
    expect(find.byType(HealthPlannedMealFormSheet), findsOneWidget);
    expect(host.gateway.commands, hasLength(1),
        reason: 'Um comando deve ter sido enviado mesmo com Unavailable');
    final firstOp = host.gateway.commands.single.operationId;
    // Fecha e reabre: a intenção está no holder, o formulário restaura o offered='275'.
    Navigator.of(tester.element(find.byType(HealthPlannedMealFormSheet))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(HealthPlannedMealFormSheet), findsNothing);
    await _openFirstForm(tester);
    expect(find.text('275'), findsOneWidget);
    final submitBtn2 = find.byType(FilledButton);
    await tester.ensureVisible(submitBtn2.last);
    await tester.pumpAndSettle();
    await tester.tap(submitBtn2.last);
    await tester.pumpAndSettle();
    expect(find.byType(HealthPlannedMealFormSheet), findsOneWidget);
    expect(host.gateway.commands, hasLength(2));
    // operationId estável: mesma intenção usa a mesma key no holder.
    expect(host.gateway.commands.last.operationId, firstOp);
  });

  testWidgets('planned meal loading textual: spinner + texto durante submit', (
    tester,
  ) async {
    final host = await _pump(tester);
    // Block gateway to observe loading state
    host.gateway.gate = Completer<void>();

    // Open form
    await _openFirstForm(tester);

    // Fill required field to enable submit
    final offered = find.widgetWithText(
      TextFormField,
      'Quantidade oferecida (g)',
    );
    await tester.enterText(offered, '300');
    await tester.pumpAndSettle();

    // Find submit button
    final submit = find.widgetWithText(FilledButton, 'REGISTRAR REFEIÇÃO');
    await tester.scrollUntilVisible(
      submit,
      250,
      scrollable: find.byType(Scrollable).last,
    );

    // Tap to submit — gateway is blocked so loading state is visible
    await tester.tap(submit);
    await tester.pump();

    // Spinner should be visible
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Loading text should be visible (button text replaced)
    expect(find.text('Registrando refeição…'), findsOneWidget);

    // Button should be disabled
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Registrando refeição…'),
    );
    expect(button.onPressed, isNull);

    // Complete the gateway and settle
    host.gateway.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(HealthPlannedMealFormSheet), findsNothing);
  });

  testWidgets('planned meal em 320px real com text scale 1.3: loading + zero overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mealGate = Completer<HealthNutritionMutationResult>();
    final loadingGateway = _LoadingGateway(mealGate.future);
    final loadingController = HealthNutritionMutationController(
      gateway: loadingGateway,
      operationIdFactory: () => 'op-plan-320',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: HealthPlannedMealFormSheet(
                localServiceDate: '2026-08-01',
                dogDisplayName: 'Bono',
                slot: _plan().mealSchedule.first,
                plan: _plan(),
                controller: loadingController,
                onRefreshRequested: () async {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(loadingController.dispose);

    final offered = find.widgetWithText(TextFormField, 'Quantidade oferecida (g)');
    await tester.enterText(offered, '300');
    await tester.pumpAndSettle();

    final submit = find.widgetWithText(FilledButton, 'REGISTRAR REFEIÇÃO');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pump();

    // CircularProgressIndicator visível
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Texto exato durante loading
    expect(find.text('Registrando refeição…'), findsOneWidget);

    // Botão desabilitado
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Registrando refeição…'),
    );
    expect(button.onPressed, isNull);

    // Somente uma chamada ao gateway
    expect(loadingGateway.plannedCallCount, 1);

    // Zero overflow
    expect(tester.takeException(), isNull);

    mealGate.complete(const CreateMealLogSuccess(
      dogId: 'dog-a',
      mealId: 'mo-320',
      revision: 1,
      wasNoOp: false,
      operationId: 'op-plan-320',
      mealOccurrenceId: 'mo-320',
    ));
    await tester.pumpAndSettle();
  });

  testWidgets('PASS 03B: novo modal planejado abre com Aceitou tudo, Tudo e consumed == offered', (
    tester,
  ) async {
    final plan = _plan();
    final completer = Completer<HealthNutritionMutationResult>();
    final gateway = _LoadingGateway(completer.future);
    final controller = HealthNutritionMutationController(
      gateway: gateway,
      operationIdFactory: () => 'op-1',
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: HealthPlannedMealFormSheet(
              slot: plan.mealSchedule.first,
              plan: plan,
              dogDisplayName: 'Bono',
              localServiceDate: '2026-07-21',
              controller: controller,
              onRefreshRequested: () async {},
              clock: () => DateTime.utc(2026, 7, 21, 12, 0),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Primeira frame útil:
    final fullChip = tester.widget<ChoiceChip>(
      find.byKey(const Key('planned-meal-acceptance-full')),
    );
    expect(fullChip.selected, isTrue);

    final allChip = tester.widget<ChoiceChip>(
      find.byKey(const Key('planned-meal-consumed-Tudo')),
    );
    expect(allChip.selected, isTrue);

    final offeredFinder = find.widgetWithText(
      TextFormField,
      'Quantidade oferecida (g)',
    );
    final offeredField = tester.widget<TextFormField>(offeredFinder);
    expect(offeredField.controller?.text, '300');
  });

  testWidgets('PASS 03B: Tudo -> Parcial com consumed == offered limpa o campo', (
    tester,
  ) async {
    final plan = _plan();
    final completer = Completer<HealthNutritionMutationResult>();
    final gateway = _LoadingGateway(completer.future);
    final controller = HealthNutritionMutationController(
      gateway: gateway,
      operationIdFactory: () => 'op-1',
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: HealthPlannedMealFormSheet(
              slot: plan.mealSchedule.first,
              plan: plan,
              dogDisplayName: 'Bono',
              localServiceDate: '2026-07-21',
              controller: controller,
              onRefreshRequested: () async {},
              clock: () => DateTime.utc(2026, 7, 21, 12, 0),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Toque em Parcial
    await tester.tap(find.byKey(const Key('planned-meal-consumed-Parcial')));
    await tester.pumpAndSettle();

    final consumedFinder = find.byKey(const ValueKey('consumed-field'));
    expect(consumedFinder, findsOneWidget);
    final consumedField = tester.widget<TextFormField>(consumedFinder);
    expect(consumedField.controller?.text, isEmpty);

    // Preenche 180
    await tester.enterText(consumedFinder, '180');
    await tester.pumpAndSettle();

    // Alterna para Tudo e depois volta para Parcial
    await tester.tap(find.byKey(const Key('planned-meal-consumed-Tudo')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('planned-meal-consumed-Parcial')));
    await tester.pumpAndSettle();

    // Como 300 != 180 antes de voltar para Parcial, o valor 300 foi redefinido em Tudo,
    // então ao voltar de Tudo para Parcial o campo é limpo novamente
    final consumedFieldAfter = tester.widget<TextFormField>(consumedFinder);
    expect(consumedFieldAfter.controller?.text, isEmpty);
  });
}

class _LoadingGateway implements HealthNutritionMutationGateway {
  _LoadingGateway(Future<HealthNutritionMutationResult> mealFuture)
      : _mealFuture = mealFuture;

  final Future<HealthNutritionMutationResult> _mealFuture;
  int plannedCallCount = 0;

  @override
  Future<HealthNutritionMutationResult> createAdhocMealLog(
    CreateAdhocMealLogCommand command,
  ) async => throw UnimplementedError();

  @override
  Future<HealthNutritionMutationResult> createPlannedMealLog(
    CreatePlannedMealLogCommand command,
  ) {
    plannedCallCount++;
    return _mealFuture;
  }

  @override
  Future<HealthNutritionMutationResult> createSupplementLog(
    CreateSupplementLogCommand command,
  ) async => throw UnimplementedError();
}
