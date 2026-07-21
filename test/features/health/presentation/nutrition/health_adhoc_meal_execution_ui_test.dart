import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_commands.dart';
import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_errors.dart';
import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_adhoc_meal_form_sheet.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_mutation_controller.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_mutation_outcome.dart';

final class _SpyAdhocGateway implements HealthNutritionMutationGateway {
  int calls = 0;
  CreateAdhocMealLogCommand? lastCommand;
  HealthNutritionMutationResult Function(CreateAdhocMealLogCommand cmd)?
  handler;

  @override
  Future<HealthNutritionMutationResult> createPlannedMealLog(
    CreatePlannedMealLogCommand command,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<HealthNutritionMutationResult> createAdhocMealLog(
    CreateAdhocMealLogCommand command,
  ) async {
    calls++;
    lastCommand = command;
    if (handler != null) return handler!(command);
    return CreateMealLogSuccess(
      dogId: command.dogId,
      mealId: 'ml1_test123',
      revision: 1,
      wasNoOp: false,
      mealOccurrenceId: null,
      operationId: command.operationId,
    );
  }

  @override
  Future<HealthNutritionMutationResult> createSupplementLog(
    CreateSupplementLogCommand command,
  ) async {
    throw UnimplementedError();
  }
}

void main() {
  late _SpyAdhocGateway gateway;
  late HealthNutritionMutationController controller;
  late int refreshCalls;

  setUp(() {
    gateway = _SpyAdhocGateway();
    controller = HealthNutritionMutationController(
      gateway: gateway,
      operationIdFactory: () => 'op-adhoc-1',
    );
    refreshCalls = 0;
  });

  tearDown(() {
    controller.dispose();
  });

  Widget buildApp(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: child),
      ),
    );
  }

  testWidgets('Happy path: submit adhoc meal log with valid inputs', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      buildApp(
        HealthAdhocMealFormSheet(
          dogId: 'dog-1',
          dogDisplayName: 'Bono',
          controller: controller,
          onRefreshRequested: () async => refreshCalls++,
          clock: () => DateTime.utc(2026, 7, 21, 12, 0),
        ),
      ),
    );

    expect(find.text('REGISTRAR ALIMENTAÇÃO'), findsOneWidget);
    expect(find.text('Registro avulso'), findsOneWidget);

    // Enter offered grams = 150
    final offeredFinder = find.widgetWithText(
      TextFormField,
      'Quantidade oferecida (g)',
    );
    await tester.enterText(offeredFinder, '150');

    // Tap submit button
    final submitFinder = find.widgetWithText(
      FilledButton,
      'REGISTRAR ALIMENTAÇÃO AVULSA',
    );
    await tester.ensureVisible(submitFinder);
    await tester.tap(submitFinder);
    await tester.pumpAndSettle();

    expect(gateway.calls, equals(1));
    expect(gateway.lastCommand, isNotNull);
    expect(gateway.lastCommand!.dogId, equals('dog-1'));
    expect(gateway.lastCommand!.offeredGrams, equals(150.0));
    expect(gateway.lastCommand!.consumedGrams, isNull);
    expect(gateway.lastCommand!.acceptance.value, equals(MealAcceptance.unknown));
    expect(gateway.lastCommand!.attachmentRefs, isEmpty);
    expect(gateway.lastCommand!.operationId, equals('op-adhoc-1'));
  });

  testWidgets('D42 Validation: offered 0 is invalid', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      buildApp(
        HealthAdhocMealFormSheet(
          dogId: 'dog-1',
          dogDisplayName: 'Bono',
          controller: controller,
          onRefreshRequested: () async => refreshCalls++,
          clock: () => DateTime.utc(2026, 7, 21, 12, 0),
        ),
      ),
    );

    final offeredFinder = find.widgetWithText(
      TextFormField,
      'Quantidade oferecida (g)',
    );
    await tester.enterText(offeredFinder, '0');

    final submitFinder = find.widgetWithText(
      FilledButton,
      'REGISTRAR ALIMENTAÇÃO AVULSA',
    );
    await tester.ensureVisible(submitFinder);
    await tester.tap(submitFinder);
    await tester.pumpAndSettle();

    expect(
      find.text('Informe uma quantidade maior que zero.'),
      findsOneWidget,
    );
    expect(gateway.calls, equals(0));
  });

  testWidgets('D42 Validation: consumed > offered is invalid', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      buildApp(
        HealthAdhocMealFormSheet(
          dogId: 'dog-1',
          dogDisplayName: 'Bono',
          controller: controller,
          onRefreshRequested: () async => refreshCalls++,
          clock: () => DateTime.utc(2026, 7, 21, 12, 0),
        ),
      ),
    );

    final offeredFinder = find.widgetWithText(
      TextFormField,
      'Quantidade oferecida (g)',
    );
    await tester.enterText(offeredFinder, '100');

    final consumedFinder = find.widgetWithText(
      TextFormField,
      'Quantidade consumida (g) — opcional',
    );
    await tester.enterText(consumedFinder, '120');

    final submitFinder = find.widgetWithText(
      FilledButton,
      'REGISTRAR ALIMENTAÇÃO AVULSA',
    );
    await tester.ensureVisible(submitFinder);
    await tester.tap(submitFinder);
    await tester.pumpAndSettle();

    expect(
      find.text('O consumo deve ficar entre 0 e a quantidade oferecida.'),
      findsOneWidget,
    );
    expect(gateway.calls, equals(0));
  });

  testWidgets('D42 Validation: refused with consumed != 0 is invalid', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      buildApp(
        HealthAdhocMealFormSheet(
          dogId: 'dog-1',
          dogDisplayName: 'Bono',
          controller: controller,
          onRefreshRequested: () async => refreshCalls++,
          clock: () => DateTime.utc(2026, 7, 21, 12, 0),
        ),
      ),
    );

    final offeredFinder = find.widgetWithText(
      TextFormField,
      'Quantidade oferecida (g)',
    );
    await tester.enterText(offeredFinder, '100');

    // Change acceptance to Recusou
    final dropdownFinder = find.byType(DropdownButtonFormField<MealAcceptance>);
    await tester.tap(dropdownFinder);
    await tester.pumpAndSettle();

    final itemFinder = find.text('Recusou').last;
    await tester.tap(itemFinder);
    await tester.pumpAndSettle();

    // Verify consumed field was automatically populated with 0
    final consumedFinder = find.widgetWithText(
      TextFormField,
      'Quantidade consumida (g) — opcional',
    );
    final formField = tester.widget<TextFormField>(consumedFinder);
    expect(formField.controller?.text, equals('0'));
  });

  testWidgets('Double submit protection: multiple taps result in 1 call', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    gateway.handler = (cmd) {
      return CreateMealLogSuccess(
        dogId: cmd.dogId,
        mealId: 'ml1_delay',
        revision: 1,
        wasNoOp: false,
        mealOccurrenceId: null,
        operationId: cmd.operationId,
      );
    };

    await tester.pumpWidget(
      buildApp(
        HealthAdhocMealFormSheet(
          dogId: 'dog-1',
          dogDisplayName: 'Bono',
          controller: controller,
          onRefreshRequested: () async => refreshCalls++,
          clock: () => DateTime.utc(2026, 7, 21, 12, 0),
        ),
      ),
    );

    final offeredFinder = find.widgetWithText(
      TextFormField,
      'Quantidade oferecida (g)',
    );
    await tester.enterText(offeredFinder, '100');

    final submitFinder = find.widgetWithText(
      FilledButton,
      'REGISTRAR ALIMENTAÇÃO AVULSA',
    );

    await tester.ensureVisible(submitFinder);
    await tester.tap(submitFinder);
    await tester.tap(submitFinder, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(gateway.calls, equals(1));
  });
}
