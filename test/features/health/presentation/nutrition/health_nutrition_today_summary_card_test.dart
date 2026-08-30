import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/data/coexistence/nutrition/coexistence_nutrition_read_source.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/meal_schedule_slot.dart';
import 'package:canil_gcm/features/health/domain/nutrition_plan.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_read_controller.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_today_screen.dart';

void main() {
  final actor = RecordedBy(uid: 'u1', name: 'A', internalRole: 'admin');
  final refDate = DateTime.utc(2026, 7, 22, 12);

  NutritionPlan canonicalPlan({
    String id = 'plan-1',
    double amountGramsPerDay = 500,
    int mealsPerDay = 3,
  }) {
    return NutritionPlan(
      id: id,
      dogId: 'dog-a',
      foodType: 'Ração Canônica',
      amountGramsPerDay: amountGramsPerDay,
      mealsPerDay: mealsPerDay,
      validFrom: DateTime.utc(2026, 1, 1),
      schemaVersion: 1,
      revision: 1,
      recordedBy: actor,
      status: NutritionPlanStatus.active,
      timezone: 'America/Sao_Paulo',
      mealSchedule: [
        MealScheduleSlot(
          id: 's-m',
          period: MealPeriodWire.parseCanonical('morning'),
          scheduledTime: ScheduledTimeOfDay('07:00'),
          targetGrams: 200,
        ),
      ],
    );
  }

  MealLog mealLog({
    required String id,
    double offered = 200,
    double? consumed,
    String? acceptance,
    String? plannedMealId,
  }) {
    final accStr =
        acceptance ??
        (consumed == null
            ? 'full'
            : (consumed == offered
                  ? 'full'
                  : (consumed == 0 ? 'refused' : 'partial')));
    return MealLog(
      id: id,
      dogId: 'dog-a',
      period: MealPeriodWire.parseCanonical('morning'),
      offeredGrams: offered,
      consumedGrams: consumed,
      acceptance: MealAcceptanceWire.parse(accStr),
      fedAt: refDate,
      recordedBy: actor,
      schemaVersion: 1,
      revision: 1,
      plannedMealId: plannedMealId,
    );
  }

  Future<void> pumpSummary(
    WidgetTester tester, {
    double? planned = 500,
    List<MealLog> meals = const [],
  }) async {
    final source = CoexistenceNutritionReadSource(
      canonicalPlanReader: _MemPlan(
        planned == null
            ? const NutritionSourceBatch.empty()
            : NutritionSourceBatch.available([
                canonicalPlan(amountGramsPerDay: planned),
              ]),
      ),
      canonicalMealReader: _MemMeal(
        meals.isEmpty
            ? const NutritionSourceBatch.empty()
            : NutritionSourceBatch.available(meals),
      ),
    );
    final controller = HealthNutritionReadController(
      source: source,
      clock: () => refDate,
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
  }

  group('UX-04C Human Review — Matriz dos 16 Estados Refinados', () {
    testWidgets(
      '1 & 2. Sem registro mostra "Consumo não registrado" e "Meta diária: 500 g" separadamente',
      (tester) async {
        final source = CoexistenceNutritionReadSource(
          canonicalPlanReader: _MemPlan(
            NutritionSourceBatch.available([
              canonicalPlan(amountGramsPerDay: 500),
            ]),
          ),
          canonicalMealReader: _MemMeal(const NutritionSourceBatch.empty()),
        );
        final controller = HealthNutritionReadController(
          source: source,
          clock: () => refDate,
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

        expect(find.text('Consumo não registrado'), findsOneWidget);
        expect(find.text('Meta diária: 500 g'), findsWidgets);
        expect(find.text('Não registrado de 500 g'), findsNothing);
      },
    );

    testWidgets('sem registro não calcula restante', (tester) async {
      final source = CoexistenceNutritionReadSource(
        canonicalPlanReader: _MemPlan(
          NutritionSourceBatch.available([
            canonicalPlan(amountGramsPerDay: 500),
          ]),
        ),
        canonicalMealReader: _MemMeal(const NutritionSourceBatch.empty()),
      );
      final controller = HealthNutritionReadController(
        source: source,
        clock: () => refDate,
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

      expect(find.text('RESTANTE'), findsOneWidget);
      expect(find.text('Não calculado'), findsOneWidget);
      final summarySemantics = tester.getSemantics(
        find
            .ancestor(
              of: find.text('CONSUMO DE HOJE'),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(summarySemantics.label, contains('Restante não calculado.'));
    });

    testWidgets('D42 separa estado e meta', (tester) async {
      final source = CoexistenceNutritionReadSource(
        canonicalPlanReader: _MemPlan(
          NutritionSourceBatch.available([
            canonicalPlan(amountGramsPerDay: 500),
          ]),
        ),
        canonicalMealReader: _MemMeal(
          NutritionSourceBatch.available([
            mealLog(id: 'm1', offered: 125, consumed: null, acceptance: 'full'),
          ]),
        ),
      );
      final controller = HealthNutritionReadController(
        source: source,
        clock: () => refDate,
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

      expect(find.text('Quantidade consumida não medida'), findsWidgets);
      expect(find.text('Meta diária: 500 g'), findsWidgets);
      expect(find.text('Até 500 g'), findsOneWidget);
      expect(
        find.text('Quantidade consumida não medida de 500 g'),
        findsNothing,
      );
      expect(find.text('Até 500 g pela medição disponível'), findsNothing);
    });

    testWidgets('consumo mensurado apresenta consumido/meta', (tester) async {
      final source = CoexistenceNutritionReadSource(
        canonicalPlanReader: _MemPlan(
          NutritionSourceBatch.available([
            canonicalPlan(amountGramsPerDay: 500),
          ]),
        ),
        canonicalMealReader: _MemMeal(
          NutritionSourceBatch.available([
            mealLog(id: 'm1', offered: 350, consumed: 350),
          ]),
        ),
      );
      final controller = HealthNutritionReadController(
        source: source,
        clock: () => refDate,
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

      expect(find.text('350 g de 500 g'), findsOneWidget);
      expect(find.text('70% da meta diária consumida'), findsOneWidget);
      expect(find.text('150 g'), findsOneWidget);
    });

    testWidgets(
      '10. Zero explicitamente registrado permite restante exato de 500 g',
      (tester) async {
        final source = CoexistenceNutritionReadSource(
          canonicalPlanReader: _MemPlan(
            NutritionSourceBatch.available([
              canonicalPlan(amountGramsPerDay: 500),
            ]),
          ),
          canonicalMealReader: _MemMeal(
            NutritionSourceBatch.available([
              mealLog(
                id: 'm1',
                offered: 200,
                consumed: 0,
                acceptance: 'refused',
              ),
            ]),
          ),
        );
        final controller = HealthNutritionReadController(
          source: source,
          clock: () => refDate,
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

        expect(find.text('0 g de 500 g'), findsOneWidget);
        expect(find.text('500 g'), findsOneWidget);
      },
    );

    testWidgets(
      '11 & 12. Somente um badge operacional aparece e "Plano ativo" NÃO aparece no resumo',
      (tester) async {
        final source = CoexistenceNutritionReadSource(
          canonicalPlanReader: _MemPlan(
            NutritionSourceBatch.available([
              canonicalPlan(amountGramsPerDay: 500),
            ]),
          ),
          canonicalMealReader: _MemMeal(
            NutritionSourceBatch.available([
              mealLog(id: 'm1', offered: 350, consumed: 350),
            ]),
          ),
        );
        final controller = HealthNutritionReadController(
          source: source,
          clock: () => refDate,
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

        expect(find.text('Dentro do plano'), findsOneWidget);
        expect(find.text('Plano ativo'), findsNothing);
      },
    );

    testWidgets('13. Semantics reflete estados desconhecidos e aproximados', (
      tester,
    ) async {
      final source = CoexistenceNutritionReadSource(
        canonicalPlanReader: _MemPlan(
          NutritionSourceBatch.available([
            canonicalPlan(amountGramsPerDay: 500),
          ]),
        ),
        canonicalMealReader: _MemMeal(
          NutritionSourceBatch.available([
            mealLog(id: 'm1', offered: 125, consumed: null, acceptance: 'full'),
          ]),
        ),
      );
      final controller = HealthNutritionReadController(
        source: source,
        clock: () => refDate,
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

      final semanticsFinder = find.ancestor(
        of: find.text('CONSUMO DE HOJE'),
        matching: find.byType(Semantics),
      );
      expect(semanticsFinder, findsWidgets);
      expect(
        tester.getSemantics(semanticsFinder.first).label,
        contains('Restante de até 500 gramas pela medição disponível.'),
      );
    });

    testWidgets(
      '14. Mistura mensurada e não mensurada mostra "250 g mensurados" e "Até 250 g"',
      (tester) async {
        final source = CoexistenceNutritionReadSource(
          canonicalPlanReader: _MemPlan(
            NutritionSourceBatch.available([
              canonicalPlan(amountGramsPerDay: 500),
            ]),
          ),
          canonicalMealReader: _MemMeal(
            NutritionSourceBatch.available([
              mealLog(
                id: 'm1',
                offered: 250,
                consumed: 250,
                acceptance: 'full',
              ),
              mealLog(
                id: 'm2',
                offered: 250,
                consumed: null,
                acceptance: 'full',
              ),
            ]),
          ),
        );
        final controller = HealthNutritionReadController(
          source: source,
          clock: () => refDate,
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
      },
    );

    testWidgets(
      '15. Acima da meta mantém progresso limitado e badge operacional',
      (tester) async {
        final source = CoexistenceNutritionReadSource(
          canonicalPlanReader: _MemPlan(
            NutritionSourceBatch.available([
              canonicalPlan(amountGramsPerDay: 500),
            ]),
          ),
          canonicalMealReader: _MemMeal(
            NutritionSourceBatch.available([
              mealLog(id: 'm1', offered: 550, consumed: 550),
            ]),
          ),
        );
        final controller = HealthNutritionReadController(
          source: source,
          clock: () => refDate,
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

        expect(find.text('Acima da meta'), findsOneWidget);
        expect(
          find.text('110% da meta diária consumida (acima da meta)'),
          findsOneWidget,
        );
        expect(find.text('0 g'), findsOneWidget);
      },
    );

    testWidgets(
      '16. Indicador de progresso usa consumo medido e limita valor em 1',
      (tester) async {
        final source = CoexistenceNutritionReadSource(
          canonicalPlanReader: _MemPlan(
            NutritionSourceBatch.available([
              canonicalPlan(amountGramsPerDay: 500),
            ]),
          ),
          canonicalMealReader: _MemMeal(
            NutritionSourceBatch.available([
              mealLog(id: 'm1', offered: 550, consumed: 550),
            ]),
          ),
        );
        final controller = HealthNutritionReadController(
          source: source,
          clock: () => refDate,
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

        final progress = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        );
        expect(progress.value, 1);
      },
    );

    testWidgets('D42 apresenta restante aproximado', (tester) async {
      await pumpSummary(
        tester,
        meals: [
          mealLog(id: 'm1', offered: 125, consumed: null, acceptance: 'full'),
        ],
      );

      expect(find.text('Até 500 g'), findsOneWidget);
      expect(
        find.text('Cálculo baseado apenas nas quantidades medidas'),
        findsOneWidget,
      );
    });

    testWidgets('meta atingida apresenta badge único e restante zero', (
      tester,
    ) async {
      await pumpSummary(
        tester,
        meals: [mealLog(id: 'm1', offered: 500, consumed: 500)],
      );

      expect(find.text('Meta atingida'), findsOneWidget);
      expect(find.text('500 g de 500 g'), findsOneWidget);
      expect(find.text('0 g'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        1,
      );
    });

    testWidgets('oferecido e consumido permanecem métricas distintas', (
      tester,
    ) async {
      await pumpSummary(
        tester,
        meals: [mealLog(id: 'm1', offered: 500, consumed: 250)],
      );

      expect(find.text('250 g de 500 g'), findsOneWidget);
      expect(find.text('OFERECIDO'), findsOneWidget);
      expect(find.text('CONSUMIDO'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        0.5,
      );
    });

    testWidgets('sem plano mantém consumo medido sem inventar meta', (
      tester,
    ) async {
      await pumpSummary(
        tester,
        planned: null,
        meals: [mealLog(id: 'm1', offered: 100, consumed: 100)],
      );

      expect(find.text('100 g'), findsWidgets);
      expect(find.text('Meta diária não informada'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
    });

    testWidgets('sem registro não cria indicador de progresso', (tester) async {
      await pumpSummary(tester);

      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text('Consumo não registrado'), findsOneWidget);
    });

    testWidgets('medição desconhecida não cria progresso exato', (
      tester,
    ) async {
      await pumpSummary(
        tester,
        meals: [
          mealLog(id: 'm1', offered: 125, consumed: null, acceptance: 'full'),
        ],
      );

      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text('Quantidade consumida não medida'), findsWidgets);
    });

    testWidgets('mistura usa somente a parte mensurada no indicador', (
      tester,
    ) async {
      await pumpSummary(
        tester,
        meals: [
          mealLog(id: 'm1', offered: 250, consumed: 250),
          mealLog(id: 'm2', offered: 250, consumed: null, acceptance: 'full'),
        ],
      );

      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        0.5,
      );
      expect(find.text('Até 250 g'), findsOneWidget);
    });
  });

  group('UX-04C Matriz Responsiva Completa (8 combinações)', () {
    for (final width in [320.0, 360.0, 390.0, 430.0]) {
      for (final textScale in [1.0, 1.5]) {
        final testName = width == 320 && textScale == 1.5
            ? 'responsividade 320 dp / escala 1.5'
            : 'Responsividade $width dp / text scale $textScale sem overflow';
        testWidgets(testName, (tester) async {
          final source = CoexistenceNutritionReadSource(
            canonicalPlanReader: _MemPlan(
              NutritionSourceBatch.available([
                canonicalPlan(amountGramsPerDay: 500),
              ]),
            ),
            canonicalMealReader: _MemMeal(
              NutritionSourceBatch.available([
                mealLog(id: 'm1', offered: 350, consumed: 350),
              ]),
            ),
          );
          final controller = HealthNutritionReadController(
            source: source,
            clock: () => refDate,
          );
          await controller.selectDog('dog-a');
          addTearDown(controller.dispose);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          tester.view.physicalSize = Size(width, 640);
          tester.view.devicePixelRatio = 1;

          await tester.pumpWidget(
            MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(textScale)),
                child: child!,
              ),
              home: Scaffold(
                body: HealthNutritionTodayScreen(
                  controller: controller,
                  dogDisplayName: 'Bono',
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(find.text('CONSUMO DE HOJE'), findsOneWidget);
          expect(find.text('350 g de 500 g'), findsOneWidget);
          expect(find.byType(LinearProgressIndicator), findsOneWidget);
          expect(find.text('OFERECIDO'), findsOneWidget);
          expect(find.text('CONSUMIDO'), findsOneWidget);
          expect(find.text('RESTANTE'), findsOneWidget);
        });
      }
    }
  });
}

final class _MemPlan implements NutritionCanonicalPlanReader {
  _MemPlan(this.batch);
  NutritionSourceBatch<NutritionPlan> batch;
  @override
  Future<NutritionSourceBatch<NutritionPlan>> loadPlans(String dogId) async =>
      batch;
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
