import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_commands.dart';
import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/meal_schedule_slot.dart';
import 'package:canil_gcm/features/health/domain/nutrition_plan.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_adhoc_meal_form_sheet.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_mutation_controller.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_planned_meal_form_sheet.dart';

final class _Pass02bTestGateway implements HealthNutritionMutationGateway {
  CreatePlannedMealLogCommand? lastPlannedCommand;
  CreateAdhocMealLogCommand? lastAdhocCommand;

  @override
  Future<HealthNutritionMutationResult> createPlannedMealLog(
    CreatePlannedMealLogCommand command,
  ) async {
    lastPlannedCommand = command;
    return const CreateMealLogSuccess(
      dogId: 'dog-1',
      mealId: 'mo-1',
      revision: 1,
      wasNoOp: false,
      operationId: 'op-planned',
      mealOccurrenceId: 'mo-1',
    );
  }

  @override
  Future<HealthNutritionMutationResult> createAdhocMealLog(
    CreateAdhocMealLogCommand command,
  ) async {
    lastAdhocCommand = command;
    return const CreateMealLogSuccess(
      dogId: 'dog-1',
      mealId: 'mo-adhoc',
      revision: 1,
      wasNoOp: false,
      operationId: 'op-adhoc',
      mealOccurrenceId: null,
    );
  }

  @override
  Future<HealthNutritionMutationResult> createSupplementLog(
    CreateSupplementLogCommand command,
  ) async => throw UnimplementedError();
}

NutritionPlan _samplePlan() => NutritionPlan(
  id: 'plan-1',
  dogId: 'dog-1',
  foodType: 'Ração Especial',
  amountGramsPerDay: 500,
  mealsPerDay: 2,
  mealSchedule: [
    MealScheduleSlot(
      id: 'slot-morning',
      period: MealPeriodWire.parseCanonical('morning'),
      scheduledTime: ScheduledTimeOfDay('07:00'),
      targetGrams: 250,
    ),
    MealScheduleSlot(
      id: 'slot-evening',
      period: MealPeriodWire.parseCanonical('evening'),
      scheduledTime: ScheduledTimeOfDay('19:00'),
      targetGrams: 250,
    ),
  ],
  validFrom: DateTime.utc(2026, 1, 1),
  timezone: NutritionPlan.defaultTimezone,
  recordedBy: RecordedBy(uid: 'u1', name: 'Silva', internalRole: 'condutor'),
  status: NutritionPlanStatus.active,
  schemaVersion: 1,
  revision: 1,
);

void main() {
  late _Pass02bTestGateway gateway;
  late HealthNutritionMutationController controller;

  setUp(() {
    gateway = _Pass02bTestGateway();
    controller = HealthNutritionMutationController(
      gateway: gateway,
      operationIdFactory: () => 'op-test',
    );
  });

  tearDown(() {
    controller.dispose();
  });

  Widget buildPlannedApp(MealScheduleSlot slot) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: HealthPlannedMealFormSheet(
            dogDisplayName: 'Thor',
            plan: _samplePlan(),
            slot: slot,
            localServiceDate: '2026-08-14',
            controller: controller,
            onRefreshRequested: () async {},
            clock: () => DateTime.utc(2026, 8, 14, 7, 0),
          ),
        ),
      ),
    );
  }

  Widget buildAdhocApp() {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: HealthAdhocMealFormSheet(
            dogId: 'dog-1',
            dogDisplayName: 'Thor',
            controller: controller,
            onRefreshRequested: () async {},
            clock: () => DateTime.utc(2026, 8, 14, 12, 0),
          ),
        ),
      ),
    );
  }

  group('PASS 02B: 15 Requisitos Obrigatórios', () {
    // 1. planned meal abre com Aceitou tudo
    testWidgets('1. planned meal abre com Aceitou tudo', (tester) async {
      await tester.pumpWidget(buildPlannedApp(_samplePlan().mealSchedule.first));
      await tester.pumpAndSettle();

      final fullChip = tester.widget<ChoiceChip>(
        find.byKey(const Key('planned-meal-acceptance-full')),
      );
      expect(fullChip.selected, isTrue);
    });

    // 2. planned meal abre com Tudo consumido
    testWidgets('2. planned meal abre com Tudo consumido', (tester) async {
      await tester.pumpWidget(buildPlannedApp(_samplePlan().mealSchedule.first));
      await tester.pumpAndSettle();

      final allChip = tester.widget<ChoiceChip>(
        find.byKey(const Key('planned-meal-consumed-Tudo')),
      );
      expect(allChip.selected, isTrue);
    });

    // 3. quantidade consumida inicial = quantidade oferecida
    testWidgets('3. quantidade consumida inicial = quantidade oferecida', (tester) async {
      await tester.pumpWidget(buildPlannedApp(_samplePlan().mealSchedule.first));
      await tester.pumpAndSettle();

      final submitBtn = find.widgetWithText(FilledButton, 'REGISTRAR REFEIÇÃO');
      await tester.ensureVisible(submitBtn);
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      expect(gateway.lastPlannedCommand, isNotNull);
      expect(gateway.lastPlannedCommand!.offeredGrams, equals(250));
      expect(gateway.lastPlannedCommand!.consumedGrams, equals(250));
    });

    // 4. período planejado corresponde ao slot clicado
    // 5. usuário não precisa reselecionar o período planejado
    testWidgets('4 & 5. período planejado corresponde ao slot e não exige reseleção', (tester) async {
      final eveningSlot = _samplePlan().mealSchedule[1];
      await tester.pumpWidget(buildPlannedApp(eveningSlot));
      await tester.pumpAndSettle();

      // Card de contexto exibe o período do slot
      expect(find.textContaining('19:00'), findsOneWidget);
      expect(find.textContaining('250 g planejados'), findsOneWidget);

      // Não há seletores ou dropdowns para reselecionar período
      expect(find.byKey(const Key('planned-meal-period')), findsNothing);

      final submitBtn = find.widgetWithText(FilledButton, 'REGISTRAR REFEIÇÃO');
      await tester.ensureVisible(submitBtn);
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      expect(gateway.lastPlannedCommand!.plannedMealId, equals('slot-evening'));
    });

    // 6. Parcial revela campo numérico
    testWidgets('6. Parcial revela campo numérico', (tester) async {
      await tester.pumpWidget(buildPlannedApp(_samplePlan().mealSchedule.first));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('consumed-field')), findsNothing);

      final partialChip = find.byKey(const Key('planned-meal-consumed-Parcial'));
      await tester.ensureVisible(partialChip);
      await tester.tap(partialChip);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('consumed-field')), findsOneWidget);
    });

    // 7. Tudo esconde campo numérico e usa quantidade oferecida
    testWidgets('7. Tudo esconde campo numérico e usa quantidade oferecida', (tester) async {
      await tester.pumpWidget(buildPlannedApp(_samplePlan().mealSchedule.first));
      await tester.pumpAndSettle();

      // Primeiro muda para Parcial para abrir o campo
      await tester.tap(find.byKey(const Key('planned-meal-consumed-Parcial')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('consumed-field')), findsOneWidget);

      // Volta para Tudo
      await tester.tap(find.byKey(const Key('planned-meal-consumed-Tudo')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('consumed-field')), findsNothing);

      final submitBtn = find.widgetWithText(FilledButton, 'REGISTRAR REFEIÇÃO');
      await tester.ensureVisible(submitBtn);
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      expect(gateway.lastPlannedCommand!.consumedGrams, equals(250));
    });

    // 8. Não medido limpa a quantidade
    testWidgets('8. Não medido limpa a quantidade (consumed null)', (tester) async {
      await tester.pumpWidget(buildPlannedApp(_samplePlan().mealSchedule.first));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('planned-meal-consumed-Não medido')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('consumed-field')), findsNothing);

      final submitBtn = find.widgetWithText(FilledButton, 'REGISTRAR REFEIÇÃO');
      await tester.ensureVisible(submitBtn);
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      expect(gateway.lastPlannedCommand!.consumedGrams, isNull);
    });

    // 9. Recusou preserva a lógica atual (consumed = 0)
    testWidgets('9. Recusou preserva a lógica atual (consumed = 0)', (tester) async {
      await tester.pumpWidget(buildPlannedApp(_samplePlan().mealSchedule.first));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('planned-meal-acceptance-refused')));
      await tester.pumpAndSettle();

      final submitBtn = find.widgetWithText(FilledButton, 'REGISTRAR REFEIÇÃO');
      await tester.ensureVisible(submitBtn);
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      expect(gateway.lastPlannedCommand!.consumedGrams, equals(0));
      expect(gateway.lastPlannedCommand!.acceptance.value, equals(MealAcceptance.refused));
    });

    // 10. Não informado continua selecionável
    testWidgets('10. Não informado continua selecionável', (tester) async {
      await tester.pumpWidget(buildPlannedApp(_samplePlan().mealSchedule.first));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('planned-meal-acceptance-unknown')));
      await tester.pumpAndSettle();

      final unknownChip = tester.widget<ChoiceChip>(
        find.byKey(const Key('planned-meal-acceptance-unknown')),
      );
      expect(unknownChip.selected, isTrue);

      final submitBtn = find.widgetWithText(FilledButton, 'REGISTRAR REFEIÇÃO');
      await tester.ensureVisible(submitBtn);
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      expect(gateway.lastPlannedCommand!.acceptance.value, equals(MealAcceptance.unknown));
    });

    // 11. ad-hoc abre com Aceitou tudo
    testWidgets('11. ad-hoc abre com Aceitou tudo', (tester) async {
      await tester.pumpWidget(buildAdhocApp());
      await tester.pumpAndSettle();

      final fullChip = tester.widget<ChoiceChip>(
        find.byKey(const Key('adhoc-meal-acceptance-full')),
      );
      expect(fullChip.selected, isTrue);
    });

    // 12. ad-hoc abre com Tudo
    testWidgets('12. ad-hoc abre com Tudo', (tester) async {
      await tester.pumpWidget(buildAdhocApp());
      await tester.pumpAndSettle();

      final allChip = tester.widget<ChoiceChip>(
        find.byKey(const Key('adhoc-meal-consumed-Tudo')),
      );
      expect(allChip.selected, isTrue);
    });

    // 13. ad-hoc oferece Manhã / Tarde / Noite / Extra (sem Madrugada na UI)
    testWidgets('13. ad-hoc oferece Manhã / Tarde / Noite / Extra', (tester) async {
      await tester.pumpWidget(buildAdhocApp());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('adhoc-meal-period-morning')), findsOneWidget);
      expect(find.byKey(const Key('adhoc-meal-period-afternoon')), findsOneWidget);
      expect(find.byKey(const Key('adhoc-meal-period-night')), findsOneWidget);
      expect(find.byKey(const Key('adhoc-meal-period-extra')), findsOneWidget);
      expect(find.text('Madrugada'), findsNothing);
    });

    // 14. suplemento não aparece como MealPeriod
    testWidgets('14. suplemento não aparece como MealPeriod', (tester) async {
      await tester.pumpWidget(buildAdhocApp());
      await tester.pumpAndSettle();

      expect(find.text('Suplemento'), findsNothing);
      expect(find.byKey(const Key('adhoc-meal-period-supplement')), findsNothing);
    });

    // 15. payload final continua compatível com o contrato existente
    testWidgets('15. payload final continua compatível com o contrato existente', (tester) async {
      await tester.pumpWidget(buildAdhocApp());
      await tester.pumpAndSettle();

      final offeredFinder = find.widgetWithText(TextFormField, 'Quantidade oferecida (g)');
      await tester.enterText(offeredFinder, '180');

      final submitBtn = find.widgetWithText(FilledButton, 'REGISTRAR REFEIÇÃO AVULSA');
      await tester.ensureVisible(submitBtn);
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      expect(gateway.lastAdhocCommand, isNotNull);
      expect(gateway.lastAdhocCommand!.dogId, equals('dog-1'));
      expect(gateway.lastAdhocCommand!.offeredGrams, equals(180.0));
      expect(gateway.lastAdhocCommand!.consumedGrams, equals(180.0));
      expect(gateway.lastAdhocCommand!.acceptance.value, equals(MealAcceptance.full));
      expect(gateway.lastAdhocCommand!.period.value, isNotNull);
      expect(gateway.lastAdhocCommand!.operationId, equals('op-test'));
    });
  });
}
