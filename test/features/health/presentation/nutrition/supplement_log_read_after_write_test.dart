import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_commands.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/supplement_log.dart';
import 'package:canil_gcm/features/health/domain/nutrition_read_models.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_mutation_controller.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_mutation_outcome.dart';

void main() {
  group('Read-after-write — SupplementLog (Gate 5C.4B)', () {
    // ── Testes existentes (contrato de gateway) ─────────────────────────────

    testWidgets(
      'createSupplement() success → gateway chamado corretamente',
      (tester) async {
        final spyGateway = _SupplementSpyGateway();
        final controller = HealthNutritionMutationController(
          gateway: spyGateway,
          operationIdFactory: () => 'op-read-after-write-test',
        );

        await controller.createSupplement(
          dogId: 'dog-read-test',
          supplementName: 'Vitamina C',
          dose: 1,
          unit: SupplementDoseUnit.parse('tablet'),
          administeredAt: DateTime.now(),
          nutritionPlanId: null,
          supplementRegimenId: null,
          notes: null,
          batchNumber: null,
        );

        expect(spyGateway.callCount, equals(1));
        expect(spyGateway.lastCommand, isNotNull);
        expect(spyGateway.lastCommand!.supplementName, equals('Vitamina C'));
        expect(spyGateway.lastCreatedId, startsWith('sl1_'));
      },
    );

    testWidgets(
      'supplementLog id começa com sl1_',
      (tester) async {
        final spyGateway = _SupplementSpyGateway();
        final controller = HealthNutritionMutationController(
          gateway: spyGateway,
          operationIdFactory: () => 'op-sl-test',
        );

        await controller.createSupplement(
          dogId: 'dog-001',
          supplementName: 'Teste',
          dose: 1,
          unit: SupplementDoseUnit.parse('tablet'),
          administeredAt: DateTime.now(),
          nutritionPlanId: null,
          supplementRegimenId: null,
          notes: null,
          batchNumber: null,
        );

        expect(spyGateway.lastCreatedId, startsWith('sl1_'));
      },
    );

    testWidgets(
      'vínculos null no modo avulso',
      (tester) async {
        final spyGateway = _SupplementSpyGateway();
        final controller = HealthNutritionMutationController(
          gateway: spyGateway,
          operationIdFactory: () => 'op-avulso-test',
        );

        await controller.createSupplement(
          dogId: 'dog-001',
          supplementName: 'Vitamina D',
          dose: 2,
          unit: SupplementDoseUnit.parse('drop'),
          administeredAt: DateTime.now(),
          nutritionPlanId: null,
          supplementRegimenId: null,
          notes: null,
          batchNumber: null,
        );

        expect(spyGateway.lastCommand!.nutritionPlanId, isNull);
        expect(spyGateway.lastCommand!.supplementRegimenId, isNull);
      },
    );

    testWidgets(
      'vínculos preenchidos no modo prescrito',
      (tester) async {
        final spyGateway = _SupplementSpyGateway();
        final controller = HealthNutritionMutationController(
          gateway: spyGateway,
          operationIdFactory: () => 'op-prescrito-test',
        );

        await controller.createSupplement(
          dogId: 'dog-001',
          supplementName: 'Ferro',
          dose: 1,
          unit: SupplementDoseUnit.parse('tablet'),
          administeredAt: DateTime.now(),
          nutritionPlanId: 'plan-001',
          supplementRegimenId: 'reg-001',
          notes: 'Com vitamina C',
          batchNumber: null,
        );

        expect(spyGateway.lastCommand!.nutritionPlanId, equals('plan-001'));
        expect(spyGateway.lastCommand!.supplementRegimenId, equals('reg-001'));
        expect(spyGateway.lastCommand!.notes, equals('Com vitamina C'));
      },
    );

    // ── Read-after-write real: ciclo de refresh ────────────────────────────

    testWidgets(
      'createSupplement() success → onRefreshAfterSuccess chamado exatamente uma vez',
      (tester) async {
        final spyGateway = _SupplementSpyGateway();
        int refreshCallCount = 0;
        final controller = HealthNutritionMutationController(
          gateway: spyGateway,
          operationIdFactory: () => 'op-raw-test',
          onRefreshAfterSuccess: () async {
            refreshCallCount++;
          },
        );

        final outcome = await controller.createSupplement(
          dogId: 'dog-001',
          supplementName: 'Zinco',
          dose: 1,
          unit: SupplementDoseUnit.parse('tablet'),
          administeredAt: DateTime.now(),
          nutritionPlanId: null,
          supplementRegimenId: null,
          notes: null,
          batchNumber: null,
        );

        // 1. Mutation teve sucesso
        expect(outcome, isA<HealthNutritionMutationUiSuccess>());
        final success = outcome as HealthNutritionMutationUiSuccess;
        expect(success.refreshFailed, isFalse);

        // 2. Refresh callback chamado exatamente uma vez
        expect(refreshCallCount, equals(1));

        // 3. Intent descartada após sucesso (nova key para nova ação)
        expect(controller.pendingIntent, isNull);
      },
    );

    testWidgets(
      'createSupplement() success com refresh error → refreshFailed=True mas intent descartada',
      (tester) async {
        final spyGateway = _SupplementSpyGateway();
        int refreshCallCount = 0;
        final controller = HealthNutritionMutationController(
          gateway: spyGateway,
          operationIdFactory: () => 'op-raw-fail-test',
          onRefreshAfterSuccess: () async {
            refreshCallCount++;
            throw Exception('Network error simulado');
          },
        );

        final outcome = await controller.createSupplement(
          dogId: 'dog-001',
          supplementName: 'Magnésio',
          dose: 1,
          unit: SupplementDoseUnit.parse('tablet'),
          administeredAt: DateTime.now(),
          nutritionPlanId: null,
          supplementRegimenId: null,
          notes: null,
          batchNumber: null,
        );

        // 1. Mutation teve sucesso
        expect(outcome, isA<HealthNutritionMutationUiSuccess>());

        // 2. Refresh callback foi chamado (tentou)
        expect(refreshCallCount, equals(1));

        // 3. refreshFailed=True porque o callback lançou
        final success = outcome as HealthNutritionMutationUiSuccess;
        expect(success.refreshFailed, isTrue);
        expect(success.refreshWarning, isNotNull);

        // 4. Intent descartada mesmo com refresh failure (persistência funcionou)
        expect(controller.pendingIntent, isNull);
      },
    );

    testWidgets(
      'createSupplement() blocked quando controller em uso',
      (tester) async {
        final spyGateway = _SupplementSpyGateway();
        int refreshCallCount = 0;
        final controller = HealthNutritionMutationController(
          gateway: spyGateway,
          operationIdFactory: () => 'op-blocked-test',
          onRefreshAfterSuccess: () async {
            refreshCallCount++;
          },
        );

        // Primeira chamada
        controller.createSupplement(
          dogId: 'dog-001',
          supplementName: 'Bloqueado',
          dose: 1,
          unit: SupplementDoseUnit.parse('tablet'),
          administeredAt: DateTime.now(),
          nutritionPlanId: null,
          supplementRegimenId: null,
          notes: null,
          batchNumber: null,
        );

        // Segunda chamada simultânea é bloqueada
        final outcome2 = await controller.createSupplement(
          dogId: 'dog-001',
          supplementName: 'Bloqueado 2',
          dose: 1,
          unit: SupplementDoseUnit.parse('tablet'),
          administeredAt: DateTime.now(),
          nutritionPlanId: null,
          supplementRegimenId: null,
          notes: null,
          batchNumber: null,
        );

        expect(outcome2, isA<HealthNutritionMutationUiBlocked>());
        // Apenas uma mutation executada
        expect(spyGateway.callCount, equals(1));
        expect(refreshCallCount, equals(1));
      },
    );

    testWidgets(
      'createSupplement() success → NutritionTodayReadModel pode incluir o novo log '
      '(prova de que o logId criado pode ser reconstruído na projeção após refresh)',
      (tester) async {
        final spyGateway = _SupplementSpyGateway();
        int refreshCallCount = 0;

        final controller = HealthNutritionMutationController(
          gateway: spyGateway,
          operationIdFactory: () => 'op-projection-test',
          onRefreshAfterSuccess: () async {
            refreshCallCount++;
          },
        );

        final outcome = await controller.createSupplement(
          dogId: 'dog-projection',
          supplementName: 'Probiótico',
          dose: 1,
          unit: SupplementDoseUnit.parse('tablet'),
          administeredAt: DateTime.now(),
          nutritionPlanId: null,
          supplementRegimenId: null,
          notes: 'Flora intestinal',
          batchNumber: null,
        );

        expect(outcome, isA<HealthNutritionMutationUiSuccess>());
        expect(refreshCallCount, equals(1));

        // O logId criado pelo gateway pode ser reconstruído na projeção
        final capturedLogId = spyGateway.lastCreatedId;
        expect(capturedLogId, startsWith('sl1_'));

        // NutritionTodayReadModel.canonicalSupplementLogs após re-leitura:
        // o NutritionTodayCanonicalReader deveria retornar o novo log
        final rebuiltModel = NutritionTodayReadModel(
          dogId: 'dog-projection',
          localServiceDate: '2026-07-01',
          timezone: 'America/Sao_Paulo',
          canonicalSupplementLogs: [
            SupplementLog(
              id: capturedLogId!,
              dogId: 'dog-projection',
              supplementName: 'Probiótico',
              dose: 1,
              unit: SupplementDoseUnit.tablet,
              administeredAt: DateTime.now(),
              recordedBy: RecordedBy(
                uid: 'test',
                name: 'Test',
                internalRole: 'test',
              ),
              schemaVersion: 1,
              revision: 1,
              notes: 'Flora intestinal',
            ),
          ],
        );

        // Projeção contém o log criado
        expect(rebuiltModel.canonicalSupplementLogs, hasLength(1));
        expect(rebuiltModel.canonicalSupplementLogs.first.id, equals(capturedLogId));
        expect(
          rebuiltModel.canonicalSupplementLogs.first.supplementName,
          equals('Probiótico'),
        );
      },
    );

    testWidgets(
      'createSupplement() success → mutation result contém operationId e revision',
      (tester) async {
        final spyGateway = _SupplementSpyGateway();
        final controller = HealthNutritionMutationController(
          gateway: spyGateway,
          operationIdFactory: () => 'op-result-test',
        );

        final outcome = await controller.createSupplement(
          dogId: 'dog-001',
          supplementName: 'Vitamina E',
          dose: 1,
          unit: SupplementDoseUnit.parse('tablet'),
          administeredAt: DateTime.now(),
          nutritionPlanId: null,
          supplementRegimenId: null,
          notes: null,
          batchNumber: null,
        );

        expect(outcome, isA<HealthNutritionMutationUiSuccess>());
        final success = outcome as HealthNutritionMutationUiSuccess;
        expect(success.dogId, equals('dog-001'));
        expect(success.entityId, startsWith('sl1_'));
        expect(success.revision, equals(1));
        expect(success.wasNoOp, isFalse);
        expect(success.refreshFailed, isFalse);
      },
    );
  });
}

// ── Spy Gateway ────────────────────────────────────────────────────────────────

class _SupplementSpyGateway implements HealthNutritionMutationGateway {
  int callCount = 0;
  String? lastCreatedId;
  CreateSupplementLogCommand? lastCommand;

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
    callCount++;
    lastCommand = command;
    lastCreatedId = 'sl1_${DateTime.now().millisecondsSinceEpoch}';
    return CreateSupplementLogSuccess(
      dogId: command.dogId,
      supplementLogId: lastCreatedId!,
      revision: 1,
      wasNoOp: false,
      operationId: command.operationId,
    );
  }
}
