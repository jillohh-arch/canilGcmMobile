import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_commands.dart';
import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_supplement_form_sheet.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_mutation_controller.dart';

void main() {
  group('HealthSupplementFormSheet — Gate 5C.4B', () {
    // ── UI Structure ───────────────────────────────────────────────────────

    testWidgets('abre com estrutura correta', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: HealthSupplementFormSheet(
                dogId: 'dog-001',
                dogDisplayName: 'Bono',
                controller: _TestController(),
                onRefreshRequested: () async {},
                timezone: 'America/Sao_Paulo',
                activePlan: null,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Título
      expect(find.text('REGISTRAR SUPLEMENTO'), findsOneWidget);

      // Campos obrigatórios
      expect(find.text('Nome do suplemento'), findsOneWidget);
      expect(find.text('Dose'), findsOneWidget);
      expect(find.text('Unidade'), findsOneWidget);

      // Campos opcionais
      expect(find.text('Observações — opcional'), findsOneWidget);
    });

    testWidgets('sem semântica pending/completed', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: HealthSupplementFormSheet(
                dogId: 'dog-001',
                dogDisplayName: 'Bono',
                controller: _TestController(),
                onRefreshRequested: () async {},
                timezone: 'America/Sao_Paulo',
                activePlan: null,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verificar que não há campos de pending/completed
      expect(find.textContaining('pending', skipOffstage: false), findsNothing);
      expect(find.textContaining('completed', skipOffstage: false), findsNothing);
      expect(find.textContaining('concluído', skipOffstage: false), findsNothing);
      expect(find.textContaining('Pendente', skipOffstage: false), findsNothing);
    });

    testWidgets('unidade default é tablet', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: HealthSupplementFormSheet(
                dogId: 'dog-001',
                dogDisplayName: 'Bono',
                controller: _TestController(),
                onRefreshRequested: () async {},
                timezone: 'America/Sao_Paulo',
                activePlan: null,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verificar que tablet/comprimido está selecionado por padrão
      expect(find.text('comprimido'), findsOneWidget);
    });

    testWidgets('mode avulso: campos editáveis', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: HealthSupplementFormSheet(
                dogId: 'dog-001',
                dogDisplayName: 'Bono',
                controller: _TestController(),
                onRefreshRequested: () async {},
                timezone: 'America/Sao_Paulo',
                activePlan: null,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Entrada de texto no campo de nome
      final nameField = find.widgetWithText(TextFormField, 'Nome do suplemento');
      expect(nameField, findsOneWidget);
      await tester.enterText(nameField, 'Vitamina C');

      expect(find.text('Vitamina C'), findsOneWidget);
    });
  });
}

/// Controller minimal para testes de UI.
class _TestController extends HealthNutritionMutationController {
  _TestController() : super(gateway: _NoOpGateway());
}

/// Gateway no-op.
class _NoOpGateway implements HealthNutritionMutationGateway {
  const _NoOpGateway();

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
    return CreateSupplementLogSuccess(
      dogId: command.dogId,
      supplementLogId: 'sl1_test',
      revision: 1,
      wasNoOp: false,
      operationId: command.operationId,
    );
  }
}
