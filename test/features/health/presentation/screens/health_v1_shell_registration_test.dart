import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/health/data/coexistence/nutrition/coexistence_nutrition_read_source.dart';
import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_commands.dart';
import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_gateway.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_adhoc_meal_form_sheet.dart';
import 'package:canil_gcm/features/health/presentation/screens/health_type_selector_screen.dart';
import 'package:canil_gcm/features/health/presentation/screens/health_v1_entry_screen.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_block_models.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_dog_context_view.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_section_status.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_source.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_source_metadata.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_view_data.dart';
import 'package:canil_gcm/features/nutrition/presentation/screens/feeding_registration_screen.dart';

final class _FakeMutationGateway implements HealthNutritionMutationGateway {
  @override
  Future<HealthNutritionMutationResult> createPlannedMealLog(
    CreatePlannedMealLogCommand command,
  ) async => throw UnimplementedError();

  @override
  Future<HealthNutritionMutationResult> createAdhocMealLog(
    CreateAdhocMealLogCommand command,
  ) async => CreateMealLogSuccess(
    dogId: command.dogId,
    mealId: 'ml1_test',
    revision: 1,
    wasNoOp: false,
    mealOccurrenceId: null,
    operationId: command.operationId,
  );

  @override
  Future<HealthNutritionMutationResult> createSupplementLog(
    CreateSupplementLogCommand command,
  ) async => throw UnimplementedError();
}

final class _DummySummarySource implements HealthSummarySource {
  @override
  Stream<HealthSummaryViewData?> watchSummary(String dogId) async* {
    yield HealthSummaryViewData(
      dogId: dogId,
      readiness: const HealthSummarySectionData.unavailable(),
      weight: const HealthSummarySectionData.unavailable(),
      vaccination: const HealthSummarySectionData.unavailable(),
      treatments: const HealthSummarySectionData.unavailable(),
      attention: const HealthSummarySectionData.unavailable(),
      nutritionToday: const HealthSummarySectionData.notRecorded(),
      weightTrend: const HealthSummarySectionData.unavailable(),
      recentRecords: const HealthSummarySectionData.unavailable(),
      metadata: HealthSummarySourceMetadata(
        updatedAt: DateTime.now(),
        isFromCache: false,
        isOffline: false,
        isStale: false,
      ),
    );
  }
}

void main() {
  testWidgets(
    'F-01 Real Shell Wiring: HealthV1EntryScreen -> + Registrar -> Nutrição opens HealthAdhocMealFormSheet without placeholder or legacy screen',
    (tester) async {
      final dog = Dog(
        id: 'dog-bono',
        name: 'Bono',
        breed: 'Pastor Alemão',
        dateOfBirth: DateTime(2020, 1, 1),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HealthV1EntryScreen(
              dogId: dog.id,
              dogContextOverride: HealthSummaryDogContextView(
                dogId: 'dog-bono',
                name: 'Bono',
              ),
              source: _DummySummarySource(),
              nutritionMutationGateway: _FakeMutationGateway(),
              nutritionReadSource: CoexistenceNutritionReadSource(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      // Find and tap header button
      final registerButton = find.text('Registrar', skipOffstage: false);
      expect(registerButton, findsOneWidget);
      await tester.tap(registerButton);
      await tester.pumpAndSettle();

      // Verify HealthTypeSelectorScreen is open
      expect(find.byType(HealthTypeSelectorScreen), findsOneWidget);

      // Select Nutrição and tap Continuar
      final nutritionCategory = find.text('Nutrição');
      expect(nutritionCategory, findsOneWidget);
      await tester.tap(nutritionCategory);
      await tester.pumpAndSettle();

      final continueButton = find.text('Continuar');
      expect(continueButton, findsOneWidget);
      await tester.tap(continueButton);
      await tester.pumpAndSettle();

      // F-01 Gate 5C.4B: agora aparece seleção de tipo (Alimentação avulsa / Suplemento)
      // Selecionar "Alimentação avulsa" para manter compatibilidade com o teste original.
      expect(find.text('Alimentação avulsa'), findsOneWidget);
      await tester.tap(find.text('Alimentação avulsa'));
      await tester.pumpAndSettle();

      // CRITICAL ASSERTION 1: HealthAdhocMealFormSheet is displayed
      expect(find.byType(HealthAdhocMealFormSheet), findsOneWidget);

      // CRITICAL ASSERTION 2: Legacy screen is NOT present
      expect(find.byType(FeedingRegistrationScreen), findsNothing);

      // CRITICAL ASSERTION 3: Placeholder toast string is NOT present
      expect(
        find.textContaining('Registro Health v1 em breve'),
        findsNothing,
      );
    },
  );
}
