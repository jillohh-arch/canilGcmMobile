import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_commands.dart';
import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_errors.dart';
import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';
import 'package:canil_gcm/features/health/domain/supplement_log.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_mutation_controller.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_mutation_outcome.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_pending_intent.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_pending_intent_session.dart';

class _SpyGateway implements HealthNutritionMutationGateway {
  final List<Object> commands = [];
  HealthNutritionMutationResult? next;
  int plannedCalls = 0;
  int adhocCalls = 0;
  int supplementCalls = 0;
  Duration delay = Duration.zero;

  @override
  Future<HealthNutritionMutationResult> createPlannedMealLog(
    CreatePlannedMealLogCommand command,
  ) async {
    plannedCalls++;
    commands.add(command);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return next ??
        const HealthNutritionMutationErrorResult(
          HealthNutritionMutationUnexpected(),
        );
  }

  @override
  Future<HealthNutritionMutationResult> createAdhocMealLog(
    CreateAdhocMealLogCommand command,
  ) async {
    adhocCalls++;
    commands.add(command);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return next ??
        const HealthNutritionMutationErrorResult(
          HealthNutritionMutationUnexpected(),
        );
  }

  @override
  Future<HealthNutritionMutationResult> createSupplementLog(
    CreateSupplementLogCommand command,
  ) async {
    supplementCalls++;
    commands.add(command);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return next ??
        const HealthNutritionMutationErrorResult(
          HealthNutritionMutationUnexpected(),
        );
  }
}

void main() {
  late _SpyGateway gateway;
  late HealthNutritionPendingIntentHolder holder;
  late HealthNutritionMutationController controller;
  var idSeq = 0;
  var refreshCalls = 0;
  Object? refreshError;

  HealthNutritionMutationController buildController() {
    return HealthNutritionMutationController(
      gateway: gateway,
      pendingIntentHolder: holder,
      operationIdFactory: () => 'op-${++idSeq}',
      onRefreshAfterSuccess: () async {
        refreshCalls++;
        final err = refreshError;
        if (err != null) throw err;
      },
    );
  }

  setUp(() {
    gateway = _SpyGateway();
    holder = HealthNutritionPendingIntentHolder();
    idSeq = 0;
    refreshCalls = 0;
    refreshError = null;
    controller = buildController();
  });

  tearDown(() {
    if (!controller.isDisposedForTest) {
      controller.dispose();
    }
  });

  CreateMealLogSuccess mealOk({
    bool wasNoOp = false,
    String mealId = 'mo1_x',
  }) {
    return CreateMealLogSuccess(
      dogId: 'dog-a',
      mealId: mealId,
      revision: 1,
      wasNoOp: wasNoOp,
      operationId: 'x',
      mealOccurrenceId: mealId,
    );
  }

  group('submit success', () {
    test('planned success + refresh', () async {
      gateway.next = mealOk();
      final outcome = await controller.createPlannedMeal(
        dogId: 'dog-a',
        planId: 'plan-1',
        plannedMealId: 'slot-am',
        offeredGrams: 300,
        acceptance: MealAcceptanceWire.parse('full'),
        fedAt: DateTime.utc(2026, 7, 10, 10),
      );
      expect(outcome, isA<HealthNutritionMutationUiSuccess>());
      final ok = outcome as HealthNutritionMutationUiSuccess;
      expect(ok.wasNoOp, isFalse);
      expect(ok.refreshFailed, isFalse);
      expect(ok.savedAndRefreshed, isTrue);
      expect(ok.successMessage, 'Registro salvo com sucesso');
      expect(gateway.plannedCalls, 1);
      expect(refreshCalls, 1);
      expect(controller.activeOperationIdForTest, isNull);
    });

    test('wasNoOp is success', () async {
      gateway.next = mealOk(wasNoOp: true);
      final outcome = await controller.createPlannedMeal(
        dogId: 'dog-a',
        planId: 'plan-1',
        plannedMealId: 'slot-am',
        offeredGrams: 300,
        acceptance: MealAcceptanceWire.parse('full'),
        fedAt: DateTime.utc(2026, 7, 10, 10),
      );
      final ok = outcome as HealthNutritionMutationUiSuccess;
      expect(ok.wasNoOp, isTrue);
      expect(ok.successMessage, 'Registro salvo com sucesso');
    });

    test('success + refresh failure separated', () async {
      gateway.next = mealOk();
      refreshError = StateError('refresh blew');
      final outcome = await controller.createPlannedMeal(
        dogId: 'dog-a',
        planId: 'plan-1',
        plannedMealId: 'slot-am',
        offeredGrams: 300,
        acceptance: MealAcceptanceWire.parse('full'),
        fedAt: DateTime.utc(2026, 7, 10, 10),
      );
      final ok = outcome as HealthNutritionMutationUiSuccess;
      expect(ok.refreshFailed, isTrue);
      expect(ok.savedButRefreshFailed, isTrue);
      expect(ok.refreshWarning, isNotNull);
    });
  });

  group('double-submit', () {
    test('second tap blocked while submitting', () async {
      gateway.delay = const Duration(milliseconds: 50);
      gateway.next = mealOk();
      final f1 = controller.createPlannedMeal(
        dogId: 'dog-a',
        planId: 'plan-1',
        plannedMealId: 'slot-am',
        offeredGrams: 300,
        acceptance: MealAcceptanceWire.parse('full'),
        fedAt: DateTime.utc(2026, 7, 10, 10),
      );
      final f2 = controller.createPlannedMeal(
        dogId: 'dog-a',
        planId: 'plan-1',
        plannedMealId: 'slot-am',
        offeredGrams: 300,
        acceptance: MealAcceptanceWire.parse('full'),
        fedAt: DateTime.utc(2026, 7, 10, 10),
      );
      final r1 = await f1;
      final r2 = await f2;
      expect(r1, isA<HealthNutritionMutationUiSuccess>());
      expect(r2, isA<HealthNutritionMutationUiBlocked>());
      expect(gateway.plannedCalls, 1);
    });
  });

  group('operationId lifecycle', () {
    test('retry after unavailable reuses same operationId', () async {
      gateway.next = const HealthNutritionMutationErrorResult(
        HealthNutritionMutationUnavailable(),
      );
      final fedAt = DateTime.utc(2026, 7, 10, 10);
      await controller.createPlannedMeal(
        dogId: 'dog-a',
        planId: 'plan-1',
        plannedMealId: 'slot-am',
        offeredGrams: 300,
        acceptance: MealAcceptanceWire.parse('full'),
        fedAt: fedAt,
      );
      final key1 = (gateway.commands.single as CreatePlannedMealLogCommand)
          .operationId;
      expect(controller.activeOperationIdForTest, key1);

      gateway.next = mealOk();
      await controller.createPlannedMeal(
        dogId: 'dog-a',
        planId: 'plan-1',
        plannedMealId: 'slot-am',
        offeredGrams: 300,
        acceptance: MealAcceptanceWire.parse('full'),
        fedAt: fedAt,
      );
      final key2 =
          (gateway.commands[1] as CreatePlannedMealLogCommand).operationId;
      expect(key2, key1);
      expect(idSeq, 1); // only one factory call
    });

    test(
      'payload change after error → blocked until discard; then new key',
      () async {
        gateway.next = const HealthNutritionMutationErrorResult(
          HealthNutritionMutationValidation('bad'),
        );
        final fedAt = DateTime.utc(2026, 7, 10, 10);
        await controller.createPlannedMeal(
          dogId: 'dog-a',
          planId: 'plan-1',
          plannedMealId: 'slot-am',
          offeredGrams: 300,
          acceptance: MealAcceptanceWire.parse('full'),
          fedAt: fedAt,
        );
        final key1 = (gateway.commands.single as CreatePlannedMealLogCommand)
            .operationId;

        // Sem discard: intenção incompatível não sobrescreve
        final blocked = await controller.createPlannedMeal(
          dogId: 'dog-a',
          planId: 'plan-1',
          plannedMealId: 'slot-am',
          offeredGrams: 250,
          acceptance: MealAcceptanceWire.parse('full'),
          fedAt: fedAt,
        );
        expect(blocked, isA<HealthNutritionMutationUiFailure>());
        expect(
          (blocked as HealthNutritionMutationUiFailure).failure.detailCode,
          'pending_intent_incompatible',
        );
        expect(gateway.plannedCalls, 1);
        expect(holder.value?.operationId, key1);

        controller.discardIntent();
        gateway.next = mealOk();
        await controller.createPlannedMeal(
          dogId: 'dog-a',
          planId: 'plan-1',
          plannedMealId: 'slot-am',
          offeredGrams: 250,
          acceptance: MealAcceptanceWire.parse('full'),
          fedAt: fedAt,
        );
        final key2 =
            (gateway.commands[1] as CreatePlannedMealLogCommand).operationId;
        expect(key2, isNot(key1));
      },
    );

    test('fedAt preserved on retry (not replaced by now)', () async {
      gateway.next = const HealthNutritionMutationErrorResult(
        HealthNutritionMutationNetwork(),
      );
      final fedAt = DateTime.utc(2026, 7, 10, 10, 30, 0);
      await controller.createPlannedMeal(
        dogId: 'dog-a',
        planId: 'plan-1',
        plannedMealId: 'slot-am',
        offeredGrams: 300,
        acceptance: MealAcceptanceWire.parse('full'),
        fedAt: fedAt,
      );
      gateway.next = mealOk();
      await controller.createPlannedMeal(
        dogId: 'dog-a',
        planId: 'plan-1',
        plannedMealId: 'slot-am',
        offeredGrams: 300,
        acceptance: MealAcceptanceWire.parse('full'),
        fedAt: fedAt,
      );
      final cmd = gateway.commands[1] as CreatePlannedMealLogCommand;
      expect(cmd.fedAt.toUtc(), fedAt);
    });
  });

  group('failures', () {
    test('permission failure', () async {
      gateway.next = const HealthNutritionMutationErrorResult(
        HealthNutritionMutationPermissionDenied(),
      );
      final outcome = await controller.createPlannedMeal(
        dogId: 'dog-a',
        planId: 'plan-1',
        plannedMealId: 'slot-am',
        offeredGrams: 300,
        acceptance: MealAcceptanceWire.parse('full'),
        fedAt: DateTime.utc(2026, 7, 10),
      );
      expect(outcome, isA<HealthNutritionMutationUiFailure>());
      expect(
        (outcome as HealthNutritionMutationUiFailure).failure,
        isA<HealthNutritionMutationPermissionDenied>(),
      );
      // key preserved for same intent
      expect(controller.activeOperationIdForTest, isNotNull);
    });

    test('occurrence conflict', () async {
      gateway.next = const HealthNutritionMutationErrorResult(
        HealthNutritionMutationMealOccurrenceConflict(),
      );
      final outcome = await controller.createPlannedMeal(
        dogId: 'dog-a',
        planId: 'plan-1',
        plannedMealId: 'slot-am',
        offeredGrams: 300,
        acceptance: MealAcceptanceWire.parse('full'),
        fedAt: DateTime.utc(2026, 7, 10),
      );
      final f = (outcome as HealthNutritionMutationUiFailure).failure;
      expect(f, isA<HealthNutritionMutationMealOccurrenceConflict>());
      expect(f.detailCode, 'meal_occurrence_conflict');
    });
  });

  group('dispose', () {
    test('after dispose returns blocked', () async {
      controller.dispose();
      final outcome = await controller.createPlannedMeal(
        dogId: 'dog-a',
        planId: 'plan-1',
        plannedMealId: 'slot-am',
        offeredGrams: 300,
        acceptance: MealAcceptanceWire.parse('full'),
        fedAt: DateTime.utc(2026, 7, 10),
      );
      expect(outcome, isA<HealthNutritionMutationUiBlocked>());
      expect(gateway.plannedCalls, 0);
    });
  });

  group('pending intent lifecycle (uncertain + dispose technical)', () {
    test(
      'supplement unavailable → dispose controller → recreate → same operationId',
      () async {
        gateway.next = const HealthNutritionMutationErrorResult(
          HealthNutritionMutationUnavailable(),
        );
        final administered = DateTime.utc(2026, 7, 17, 14);
        await controller.createSupplement(
          dogId: 'dog-a',
          supplementName: 'Omega',
          dose: 5,
          unit: SupplementDoseUnit.parse('ml'),
          administeredAt: administered,
        );
        final keyA =
            (gateway.commands.single as CreateSupplementLogCommand).operationId;
        expect(holder.value?.operationId, keyA);

        // dispose técnico — NÃO limpa holder
        controller.dispose();
        expect(holder.value?.operationId, keyA);

        final restored = buildController();
        gateway.next = CreateSupplementLogSuccess(
          dogId: 'dog-a',
          supplementLogId: 'sl1_x',
          revision: 1,
          wasNoOp: false,
          operationId: keyA,
        );
        await restored.createSupplement(
          dogId: 'dog-a',
          supplementName: 'Omega',
          dose: 5,
          unit: SupplementDoseUnit.parse('ml'),
          administeredAt: administered,
        );
        final keyRetry =
            (gateway.commands[1] as CreateSupplementLogCommand).operationId;
        expect(keyRetry, keyA);
        expect(idSeq, 1); // sem nova factory call
        restored.dispose();
      },
    );

    test(
      'adhoc unavailable → dispose → recreate → same operationId',
      () async {
        gateway.next = const HealthNutritionMutationErrorResult(
          HealthNutritionMutationNetwork(),
        );
        final fedAt = DateTime.utc(2026, 7, 17, 12);
        await controller.createAdhocMeal(
          dogId: 'dog-a',
          period: MealPeriodWire.parseCanonical('extra'),
          offeredGrams: 90,
          acceptance: MealAcceptanceWire.parse('full'),
          fedAt: fedAt,
        );
        final keyA =
            (gateway.commands.single as CreateAdhocMealLogCommand).operationId;
        controller.dispose();
        expect(holder.value?.operationId, keyA);

        final restored = buildController();
        gateway.next = CreateMealLogSuccess(
          dogId: 'dog-a',
          mealId: 'ml1_x',
          revision: 1,
          wasNoOp: false,
          operationId: keyA,
          mealOccurrenceId: null,
        );
        await restored.createAdhocMeal(
          dogId: 'dog-a',
          period: MealPeriodWire.parseCanonical('extra'),
          offeredGrams: 90,
          acceptance: MealAcceptanceWire.parse('full'),
          fedAt: fedAt,
        );
        final keyRetry =
            (gateway.commands[1] as CreateAdhocMealLogCommand).operationId;
        expect(keyRetry, keyA);
        restored.dispose();
      },
    );

    test(
      'explicit discardIntent após unavailable → nova key em nova intenção igual',
      () async {
        gateway.next = const HealthNutritionMutationErrorResult(
          HealthNutritionMutationUnavailable(),
        );
        final administered = DateTime.utc(2026, 7, 17, 14);
        await controller.createSupplement(
          dogId: 'dog-a',
          supplementName: 'Omega',
          dose: 5,
          unit: SupplementDoseUnit.parse('ml'),
          administeredAt: administered,
        );
        final keyA =
            (gateway.commands.single as CreateSupplementLogCommand).operationId;

        controller.discardIntent();
        expect(holder.value, isNull);

        gateway.next = CreateSupplementLogSuccess(
          dogId: 'dog-a',
          supplementLogId: 'sl1_new',
          revision: 1,
          wasNoOp: false,
          operationId: 'x',
        );
        await controller.createSupplement(
          dogId: 'dog-a',
          supplementName: 'Omega',
          dose: 5,
          unit: SupplementDoseUnit.parse('ml'),
          administeredAt: administered,
        );
        final keyB =
            (gateway.commands[1] as CreateSupplementLogCommand).operationId;
        expect(keyB, isNot(keyA));
        expect(keyB, 'op-2');
      },
    );

    test('success finaliza intenção; próximo submit gera nova key', () async {
      gateway.next = mealOk();
      final fedAt = DateTime.utc(2026, 7, 10, 10);
      await controller.createPlannedMeal(
        dogId: 'dog-a',
        planId: 'plan-1',
        plannedMealId: 'slot-am',
        offeredGrams: 300,
        acceptance: MealAcceptanceWire.parse('full'),
        fedAt: fedAt,
      );
      final keyA =
          (gateway.commands.single as CreatePlannedMealLogCommand).operationId;
      expect(holder.value, isNull);

      gateway.next = mealOk(mealId: 'mo1_y');
      await controller.createPlannedMeal(
        dogId: 'dog-a',
        planId: 'plan-1',
        plannedMealId: 'slot-am',
        offeredGrams: 300,
        acceptance: MealAcceptanceWire.parse('full'),
        fedAt: fedAt,
      );
      final keyB =
          (gateway.commands[1] as CreatePlannedMealLogCommand).operationId;
      expect(keyB, isNot(keyA));
    });

    test('dispose técnico não limpa pending intent no holder', () async {
      gateway.next = const HealthNutritionMutationErrorResult(
        HealthNutritionMutationUnavailable(),
      );
      await controller.createAdhocMeal(
        dogId: 'dog-a',
        period: MealPeriodWire.parseCanonical('night'),
        offeredGrams: 40,
        acceptance: MealAcceptanceWire.parse('full'),
        fedAt: DateTime.utc(2026, 7, 10),
      );
      final key = holder.value!.operationId;
      controller.dispose();
      expect(controller.isDisposedForTest, isTrue);
      expect(holder.value?.operationId, key);
    });
  });

  group('no default refresh callback', () {
    test('null onRefresh does not invent failure', () async {
      final c = HealthNutritionMutationController(
        gateway: gateway,
        pendingIntentHolder: HealthNutritionPendingIntentHolder(),
        operationIdFactory: () => 'op-only',
        onRefreshAfterSuccess: null,
      );
      gateway.next = mealOk();
      final outcome = await c.createAdhocMeal(
        dogId: 'dog-a',
        period: MealPeriodWire.parseCanonical('extra'),
        offeredGrams: 50,
        acceptance: MealAcceptanceWire.parse('full'),
        fedAt: DateTime.utc(2026, 7, 10),
      );
      final ok = outcome as HealthNutritionMutationUiSuccess;
      expect(ok.refreshFailed, isFalse);
      c.dispose();
    });
  });

  group('session owner / dog isolation', () {
    test(
      'entry remount with session holder restores same key after unavailable',
      () async {
        final session = HealthNutritionPendingIntentSession();
        final holderA = session.holderFor('dog-a');
        var seq = 0;
        HealthNutritionMutationController makeCtrl() {
          return HealthNutritionMutationController(
            gateway: gateway,
            pendingIntentHolder: holderA,
            operationIdFactory: () => 'sess-${++seq}',
          );
        }

        var c = makeCtrl();
        gateway.next = const HealthNutritionMutationErrorResult(
          HealthNutritionMutationUnavailable(),
        );
        await c.createAdhocMeal(
          dogId: 'dog-a',
          period: MealPeriodWire.parseCanonical('extra'),
          offeredGrams: 80,
          acceptance: MealAcceptanceWire.parse('full'),
          fedAt: DateTime.utc(2026, 7, 18),
        );
        final keyA =
            (gateway.commands.single as CreateAdhocMealLogCommand).operationId;
        // Simula dispose do HealthV1EntryScreen (ValueKey/navegação técnica)
        c.dispose();
        expect(session.hasPendingForDog('dog-a'), isTrue);

        // Remount com mesmo holder da sessão MainRoot
        c = makeCtrl();
        gateway.next = CreateMealLogSuccess(
          dogId: 'dog-a',
          mealId: 'ml1_x',
          revision: 1,
          wasNoOp: false,
          operationId: keyA,
        );
        await c.createAdhocMeal(
          dogId: 'dog-a',
          period: MealPeriodWire.parseCanonical('extra'),
          offeredGrams: 80,
          acceptance: MealAcceptanceWire.parse('full'),
          fedAt: DateTime.utc(2026, 7, 18),
        );
        expect(
          (gateway.commands[1] as CreateAdhocMealLogCommand).operationId,
          keyA,
        );
        c.dispose();
      },
    );

    test('dog A pending never reused for dog B command', () async {
      final session = HealthNutritionPendingIntentSession();
      final holderA = session.holderFor('dog-a');
      final holderB = session.holderFor('dog-b');
      var seq = 0;

      final ctrlA = HealthNutritionMutationController(
        gateway: gateway,
        pendingIntentHolder: holderA,
        operationIdFactory: () => 'a-${++seq}',
      );
      gateway.next = const HealthNutritionMutationErrorResult(
        HealthNutritionMutationUnavailable(),
      );
      await ctrlA.createSupplement(
        dogId: 'dog-a',
        supplementName: 'Omega',
        dose: 2,
        unit: SupplementDoseUnit.parse('ml'),
        administeredAt: DateTime.utc(2026, 7, 18),
      );
      final keyA =
          (gateway.commands.single as CreateSupplementLogCommand).operationId;
      expect(holderA.value?.operationId, keyA);
      expect(holderB.value, isNull);

      final ctrlB = HealthNutritionMutationController(
        gateway: gateway,
        pendingIntentHolder: holderB,
        operationIdFactory: () => 'b-${++seq}',
      );
      gateway.next = CreateSupplementLogSuccess(
        dogId: 'dog-b',
        supplementLogId: 'sl1_b',
        revision: 1,
        wasNoOp: false,
        operationId: 'x',
      );
      await ctrlB.createSupplement(
        dogId: 'dog-b',
        supplementName: 'Omega',
        dose: 2,
        unit: SupplementDoseUnit.parse('ml'),
        administeredAt: DateTime.utc(2026, 7, 18),
      );
      final keyB =
          (gateway.commands[1] as CreateSupplementLogCommand).operationId;
      expect(keyB, isNot(keyA));
      expect(holderA.value?.operationId, keyA); // A intacta
      ctrlA.dispose();
      ctrlB.dispose();
    });

    test(
      'incompatible intent (adhoc while supplement pending) does not overwrite',
      () async {
        gateway.next = const HealthNutritionMutationErrorResult(
          HealthNutritionMutationUnavailable(),
        );
        await controller.createSupplement(
          dogId: 'dog-a',
          supplementName: 'Omega',
          dose: 1,
          unit: SupplementDoseUnit.parse('mg'),
          administeredAt: DateTime.utc(2026, 7, 18),
        );
        final keyA =
            (gateway.commands.single as CreateSupplementLogCommand).operationId;

        final blocked = await controller.createAdhocMeal(
          dogId: 'dog-a',
          period: MealPeriodWire.parseCanonical('morning'),
          offeredGrams: 50,
          acceptance: MealAcceptanceWire.parse('full'),
          fedAt: DateTime.utc(2026, 7, 18),
        );
        expect(
          (blocked as HealthNutritionMutationUiFailure).failure.detailCode,
          'pending_intent_incompatible',
        );
        expect(holder.value?.operationId, keyA);
        expect(gateway.adhocCalls, 0);
      },
    );

    test(
      'same-kind supplement uncertain: dose change blocked; opA preserved',
      () async {
        gateway.next = const HealthNutritionMutationErrorResult(
          HealthNutritionMutationUnavailable(),
        );
        final at = DateTime.utc(2026, 7, 19, 12);
        await controller.createSupplement(
          dogId: 'dog-a',
          supplementName: 'Omega',
          dose: 5,
          unit: SupplementDoseUnit.parse('ml'),
          administeredAt: at,
        );
        final opA =
            (gateway.commands.single as CreateSupplementLogCommand).operationId;
        expect(holder.value?.operationId, opA);
        expect(idSeq, 1);

        final blocked = await controller.createSupplement(
          dogId: 'dog-a',
          supplementName: 'Omega',
          dose: 10, // same kind, different fingerprint
          unit: SupplementDoseUnit.parse('ml'),
          administeredAt: at,
        );
        expect(blocked, isA<HealthNutritionMutationUiFailure>());
        expect(
          (blocked as HealthNutritionMutationUiFailure).failure.detailCode,
          'pending_intent_incompatible',
        );
        expect(holder.value?.operationId, opA);
        expect(gateway.supplementCalls, 1);
        expect(idSeq, 1); // no opB created

        controller.discardIntent();
        gateway.next = CreateSupplementLogSuccess(
          dogId: 'dog-a',
          supplementLogId: 'sl1_new',
          revision: 1,
          wasNoOp: false,
          operationId: 'x',
        );
        await controller.createSupplement(
          dogId: 'dog-a',
          supplementName: 'Omega',
          dose: 10,
          unit: SupplementDoseUnit.parse('ml'),
          administeredAt: at,
        );
        final opB =
            (gateway.commands[1] as CreateSupplementLogCommand).operationId;
        expect(opB, isNot(opA));
      },
    );

    test(
      'same-kind adhoc uncertain: offeredGrams change blocked; opA preserved',
      () async {
        gateway.next = const HealthNutritionMutationErrorResult(
          HealthNutritionMutationNetwork(),
        );
        final fed = DateTime.utc(2026, 7, 19, 8);
        await controller.createAdhocMeal(
          dogId: 'dog-a',
          period: MealPeriodWire.parseCanonical('extra'),
          offeredGrams: 100,
          acceptance: MealAcceptanceWire.parse('full'),
          fedAt: fed,
        );
        final opA =
            (gateway.commands.single as CreateAdhocMealLogCommand).operationId;

        final blocked = await controller.createAdhocMeal(
          dogId: 'dog-a',
          period: MealPeriodWire.parseCanonical('extra'),
          offeredGrams: 150,
          acceptance: MealAcceptanceWire.parse('full'),
          fedAt: fed,
        );
        expect(
          (blocked as HealthNutritionMutationUiFailure).failure.detailCode,
          'pending_intent_incompatible',
        );
        expect(holder.value?.operationId, opA);
        expect(gateway.adhocCalls, 1);
      },
    );

    test(
      'same-kind planned uncertain: acceptance change blocked; opA preserved',
      () async {
        gateway.next = const HealthNutritionMutationErrorResult(
          HealthNutritionMutationUnavailable(),
        );
        final fed = DateTime.utc(2026, 7, 10, 10);
        await controller.createPlannedMeal(
          dogId: 'dog-a',
          planId: 'plan-1',
          plannedMealId: 'slot-am',
          offeredGrams: 300,
          acceptance: MealAcceptanceWire.parse('full'),
          fedAt: fed,
        );
        final opA =
            (gateway.commands.single as CreatePlannedMealLogCommand).operationId;

        final blocked = await controller.createPlannedMeal(
          dogId: 'dog-a',
          planId: 'plan-1',
          plannedMealId: 'slot-am',
          offeredGrams: 300,
          acceptance: MealAcceptanceWire.parse('partial'),
          consumedGrams: 100,
          fedAt: fed,
        );
        expect(
          (blocked as HealthNutritionMutationUiFailure).failure.detailCode,
          'pending_intent_incompatible',
        );
        expect(holder.value?.operationId, opA);
        expect(gateway.plannedCalls, 1);
      },
    );
  });
}
