import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_commands.dart';
import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/nutrition_plan.dart';
import 'package:canil_gcm/features/health/domain/nutrition_plan_regimen.dart';
import 'package:canil_gcm/features/health/domain/nutrition_read_models.dart';
import 'package:canil_gcm/features/health/domain/supplement_log.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_supplement_form_sheet.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_mutation_controller.dart';

void main() {
  group('HealthSupplementFormSheet — Command Contract (Gate 5C.4B)', () {
    late _SpyGateway spyGateway;
    late HealthNutritionMutationController controller;

    setUp(() {
      spyGateway = _SpyGateway();
      controller = HealthNutritionMutationController(
        gateway: spyGateway,
        operationIdFactory: () => 'op-test-supplement-1',
      );
    });

    tearDown(() {
      controller.dispose();
    });

    Widget buildSheet({
      NutritionActiveCanonicalPlan? activePlan,
      NutritionPlanSupplementRegimen? defaultRegimen,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: HealthSupplementFormSheet(
              dogId: 'dog-001',
              dogDisplayName: 'Bono',
              controller: controller,
              onRefreshRequested: () async {},
              timezone: 'America/Sao_Paulo',
              activePlan: activePlan,
              defaultRegimen: defaultRegimen,
            ),
          ),
        ),
      );
    }

    // ── AVULSO ────────────────────────────────────────────────────────────

    group('Modo Avulso', () {
      testWidgets('submit gera command correto com vínculos null', (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(buildSheet());
        await tester.pumpAndSettle();

        // Preencher campos
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Nome do suplemento'),
          'Vitamina C',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Dose'),
          '2.5',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Observações — opcional'),
          'Tomar com alimento',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Número do lote — opcional'),
          'L12345',
        );

        // Submeter — botão avulso
        await tester.tap(find.text('REGISTRAR SUPLEMENTO AVULSO'));
        await tester.pumpAndSettle();

        // Verificar command capturado
        expect(spyGateway.lastSupplementCommand, isNotNull);
        final cmd = spyGateway.lastSupplementCommand!;

        expect(cmd.dogId, equals('dog-001'));
        expect(cmd.supplementName, equals('Vitamina C'));
        expect(cmd.dose, equals(2.5));
        expect(cmd.nutritionPlanId, isNull); // AVULSO: null
        expect(cmd.supplementRegimenId, isNull); // AVULSO: null
        expect(cmd.notes, equals('Tomar com alimento'));
        expect(cmd.batchNumber, equals('L12345'));
        expect(cmd.operationId, equals('op-test-supplement-1'));
      });

      testWidgets('notes e batch_number são opcionais', (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(buildSheet());
        await tester.pumpAndSettle();

        // Preencher apenas campos obrigatórios
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Nome do suplemento'),
          'Ômega 3',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Dose'),
          '1',
        );
        // Não preencher notes nem batch_number

        await tester.tap(find.text('REGISTRAR SUPLEMENTO AVULSO'));
        await tester.pumpAndSettle();

        final cmd = spyGateway.lastSupplementCommand!;
        expect(cmd.supplementName, equals('Ômega 3'));
        expect(cmd.dose, equals(1.0));
        expect(cmd.notes, isNull);
        expect(cmd.batchNumber, isNull);
        expect(cmd.nutritionPlanId, isNull);
        expect(cmd.supplementRegimenId, isNull);
      });

      testWidgets('nome vazio → não submete', (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(buildSheet());
        await tester.pumpAndSettle();

        // Deixar nome vazio
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Dose'),
          '1',
        );

        await tester.tap(find.text('REGISTRAR SUPLEMENTO AVULSO'));
        await tester.pumpAndSettle();

        expect(spyGateway.lastSupplementCommand, isNull);
      });

      testWidgets('dose inválida → não submete', (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(buildSheet());
        await tester.pumpAndSettle();

        await tester.enterText(
          find.widgetWithText(TextFormField, 'Nome do suplemento'),
          'Vitamina C',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Dose'),
          '0',
        );

        await tester.tap(find.text('REGISTRAR SUPLEMENTO AVULSO'));
        await tester.pumpAndSettle();

        expect(spyGateway.lastSupplementCommand, isNull);
      });
    });

    // ── PRESCRITO ──────────────────────────────────────────────────────────

    group('Modo Prescrito', () {
      final testRegimen = NutritionPlanSupplementRegimen(
        id: 'reg-001',
        name: 'Vitamina B12',
        dose: 1,
        unit: SupplementDoseUnit.tablet,
        frequency: 'diária',
        instructions: 'Via oral',
      );

      late NutritionPlan testPlan;
      late NutritionActiveCanonicalPlan activePlan;

      setUp(() {
        testPlan = NutritionPlan(
          id: 'plan-001',
          dogId: 'dog-001',
          foodType: 'Ração premium',
          amountGramsPerDay: 400,
          mealsPerDay: 3,
          mealSchedule: [],
          validFrom: DateTime.utc(2026, 7, 1),
          timezone: 'America/Sao_Paulo',
          recordedBy: RecordedBy(uid: 'sys', name: 'System', internalRole: 'system'),
          status: NutritionPlanStatus.active,
          schemaVersion: 1,
          revision: 1,
          supplements: [testRegimen],
        );
        activePlan = NutritionActiveCanonicalPlan(testPlan);
      });

      testWidgets('defaultRegimen gera IDs corretos', (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(buildSheet(
          activePlan: activePlan,
          defaultRegimen: testRegimen,
        ));
        await tester.pumpAndSettle();

        // Preencher notes opcional
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Observações — opcional'),
          'Tomar com alimento',
        );

        await tester.tap(find.text('REGISTRAR ADMINISTRAÇÃO DO PLANO'));
        await tester.pumpAndSettle();

        final cmd = spyGateway.lastSupplementCommand!;

        // IDs do plano/regimen corretos
        expect(cmd.nutritionPlanId, equals('plan-001'));
        expect(cmd.supplementRegimenId, equals('reg-001'));
      });

      testWidgets('nome/dose/unit derivados do regimen', (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(buildSheet(
          activePlan: activePlan,
          defaultRegimen: testRegimen,
        ));
        await tester.pumpAndSettle();

        await tester.tap(find.text('REGISTRAR ADMINISTRAÇÃO DO PLANO'));
        await tester.pumpAndSettle();

        final cmd = spyGateway.lastSupplementCommand!;

        // Valores derivados do regimen
        expect(cmd.supplementName, equals('Vitamina B12'));
        expect(cmd.dose, equals(1));
        expect(cmd.unit.value, equals(SupplementDoseUnit.tablet));
      });

      testWidgets('sem pending/completed semantics', (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(buildSheet(activePlan: activePlan));
        await tester.pumpAndSettle();

        // Verificar que não há indicadores de pending/completed
        expect(find.textContaining('pending', skipOffstage: false), findsNothing);
        expect(find.textContaining('completed', skipOffstage: false), findsNothing);
        expect(find.textContaining('concluído', skipOffstage: false), findsNothing);
        expect(find.textContaining('Pendente', skipOffstage: false), findsNothing);
      });

      testWidgets('vínculos preenchidos quando prescrito', (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(buildSheet(
          activePlan: activePlan,
          defaultRegimen: testRegimen,
        ));
        await tester.pumpAndSettle();

        await tester.tap(find.text('REGISTRAR ADMINISTRAÇÃO DO PLANO'));
        await tester.pumpAndSettle();

        final cmd = spyGateway.lastSupplementCommand!;

        // Quando prescrito, os vínculos são preenchidos (não null)
        expect(cmd.nutritionPlanId, isNotNull);
        expect(cmd.supplementRegimenId, isNotNull);
      });
    });
  });
}

// ── Spy Gateway ────────────────────────────────────────────────────────────────

class _SpyGateway implements HealthNutritionMutationGateway {
  CreateSupplementLogCommand? lastSupplementCommand;
  int supplementCallCount = 0;

  @override
  Future<HealthNutritionMutationResult> createAdhocMealLog(
    CreateAdhocMealLogCommand command,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<HealthNutritionMutationResult> createPlannedMealLog(
    CreatePlannedMealLogCommand command,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<HealthNutritionMutationResult> createSupplementLog(
    CreateSupplementLogCommand command,
  ) async {
    supplementCallCount++;
    lastSupplementCommand = command;
    return CreateSupplementLogSuccess(
      dogId: command.dogId,
      supplementLogId: 'sl1_test_$supplementCallCount',
      revision: 1,
      wasNoOp: false,
      operationId: command.operationId,
    );
  }
}
