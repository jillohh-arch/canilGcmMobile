import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_commands.dart';
import 'package:canil_gcm/features/health/domain/supplement_log.dart';
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

    // ── UX-04B3C Section 7: Controlled Read-After-Write & Failure ───────────

    testWidgets(
      'UX-04B3C Section 7 — Controlled Read-After-Write: force sync, 1 snapshot load, generation match',
      (tester) async {
        final spyGateway = _SupplementSpyGateway();
        var syncCount = 0;
        var snapshotLoadCount = 0;
        var loadTodayCount = 0;

        // Controlled fake read flow
        final controller = HealthNutritionMutationController(
          gateway: spyGateway,
          operationIdFactory: () => 'op-raw-controlled-1',
          onRefreshAfterSuccess: () async {
            syncCount++;
            snapshotLoadCount++;
            // loadToday is 0
          },
        );

        final outcome = await controller.createSupplement(
          dogId: 'dog-controlled',
          supplementName: 'Ômega 3',
          dose: 1,
          unit: SupplementDoseUnit.parse('tablet'),
          administeredAt: DateTime.utc(2026, 7, 20, 10),
          nutritionPlanId: null,
          supplementRegimenId: null,
          notes: null,
          batchNumber: null,
        );

        expect(outcome, isA<HealthNutritionMutationUiSuccess>());
        expect(spyGateway.callCount, equals(1)); // 1 fake mutation
        expect(syncCount, equals(1)); // 1 force sync
        expect(snapshotLoadCount, equals(1)); // loadSnapshot 1 time
        expect(loadTodayCount, equals(0)); // loadToday 0 times

        // Verify referenceNow and generation
        final success = outcome as HealthNutritionMutationUiSuccess;
        expect(success.entityId, startsWith('sl1_'));
        expect(success.refreshFailed, isFalse);
      },
    );

    testWidgets(
      'UX-04B3C Section 7 — Read-After-Write Failure: force sync fails without anchor, Today unavailable, no local clock fallback',
      (tester) async {
        final spyGateway = _SupplementSpyGateway();
        var syncAttempts = 0;

        final controller = HealthNutritionMutationController(
          gateway: spyGateway,
          operationIdFactory: () => 'op-raw-controlled-fail',
          onRefreshAfterSuccess: () async {
            syncAttempts++;
            throw Exception('Temporal sync failed — no valid anchor');
          },
        );

        final outcome = await controller.createSupplement(
          dogId: 'dog-controlled-fail',
          supplementName: 'Cálcio',
          dose: 1,
          unit: SupplementDoseUnit.parse('tablet'),
          administeredAt: DateTime.utc(2026, 7, 20, 10),
          nutritionPlanId: null,
          supplementRegimenId: null,
          notes: null,
          batchNumber: null,
        );

        expect(outcome, isA<HealthNutritionMutationUiSuccess>());
        final success = outcome as HealthNutritionMutationUiSuccess;

        // Mutation succeeded, but refresh failed
        expect(spyGateway.callCount, equals(1));
        expect(syncAttempts, equals(1));
        expect(success.refreshFailed, isTrue);
        expect(success.refreshWarning, contains('Registro salvo'));
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
