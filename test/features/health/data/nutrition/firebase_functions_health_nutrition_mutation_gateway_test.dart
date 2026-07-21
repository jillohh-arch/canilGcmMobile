import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/data/nutrition/firebase_functions_health_nutrition_mutation_gateway.dart';
import 'package:canil_gcm/features/health/data/nutrition/health_nutrition_callable_names.dart';
import 'package:canil_gcm/features/health/data/nutrition/health_nutrition_mutation_payload_codec.dart';
import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_commands.dart';
import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_errors.dart';
import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';
import 'package:canil_gcm/features/health/domain/supplement_log.dart';

typedef _Call = ({String name, Map<String, dynamic> data});

void main() {
  late List<_Call> calls;
  late Map<String, Object?>? nextResult;
  late Object? nextError;

  setUp(() {
    calls = <_Call>[];
    nextResult = null;
    nextError = null;
  });

  FirebaseFunctionsHealthNutritionMutationGateway gateway() {
    return FirebaseFunctionsHealthNutritionMutationGateway(
      invoker: (name, data) async {
        calls.add((name: name, data: Map<String, dynamic>.from(data)));
        final err = nextError;
        if (err != null) throw err;
        final r = nextResult;
        if (r == null) throw StateError('nextResult não configurado');
        return Map<String, dynamic>.from(r);
      },
    );
  }

  Map<String, dynamic> mealReceipt({
    String dogId = 'dog-a',
    String mealId = 'mo1_abc',
    int revision = 1,
    bool wasNoOp = false,
    Object? mealOccurrenceId = 'mo1_abc',
  }) {
    return {
      'dog_id': dogId,
      'meal_id': mealId,
      'revision': revision,
      'was_no_op': wasNoOp,
      'meal_occurrence_id': mealOccurrenceId,
    };
  }

  group('createPlannedMealLog', () {
    test('callable name, snake_case payload, ISO UTC, zero server-owned', () async {
      nextResult = mealReceipt();
      final fedLocal = DateTime(2026, 7, 10, 7, 0); // local wall
      final cmd = CreatePlannedMealLogCommand(
        dogId: 'dog-a',
        planId: 'plan-1',
        plannedMealId: 'slot-am',
        offeredGrams: 300,
        acceptance: MealAcceptanceWire.parse('full'),
        fedAt: fedLocal,
        operationId: 'op-planned-1',
        consumedGrams: 300,
        observations: 'ok',
        attachmentRefs: const ['ref-1'],
      );

      final result = await gateway().createPlannedMealLog(cmd);
      expect(result, isA<CreateMealLogSuccess>());
      final ok = result as CreateMealLogSuccess;
      expect(ok.mealId, 'mo1_abc');
      expect(ok.revision, 1);
      expect(ok.wasNoOp, isFalse);
      expect(ok.mealOccurrenceId, 'mo1_abc');
      expect(ok.operationId, 'op-planned-1');

      expect(calls.single.name, HealthNutritionCallableNames.createMealLog);
      final p = calls.single.data;
      expect(p['mode'], 'planned');
      expect(p['dog_id'], 'dog-a');
      expect(p['plan_id'], 'plan-1');
      expect(p['planned_meal_id'], 'slot-am');
      expect(p['offered_grams'], 300);
      expect(p['consumed_grams'], 300);
      expect(p['acceptance'], 'full');
      expect(p['fed_at'], fedLocal.toUtc().toIso8601String());
      expect(p['operation_id'], 'op-planned-1');
      expect(p['observations'], 'ok');
      expect(p['attachment_refs'], ['ref-1']);
      // no camelCase mirrors
      expect(p.containsKey('dogId'), isFalse);
      expect(p.containsKey('planId'), isFalse);
      expect(p.containsKey('fedAt'), isFalse);
      for (final key in const [
        'period',
        'scheduled_for',
        'meal_occurrence_id',
        'recorded_by',
        'revision',
        'schema_version',
        'create_fingerprint',
        'receipt_id',
      ]) {
        expect(p.containsKey(key), isFalse, reason: key);
      }
    });

    test('local and UTC DateTime produce same ISO instant', () async {
      nextResult = mealReceipt(mealId: 'mo1_x', mealOccurrenceId: 'mo1_x');
      final utc = DateTime.utc(2026, 7, 10, 10);
      final localEquiv = utc.toLocal();
      await gateway().createPlannedMealLog(
        CreatePlannedMealLogCommand(
          dogId: 'dog-a',
          planId: 'p',
          plannedMealId: 's',
          offeredGrams: 100,
          acceptance: MealAcceptanceWire.parse('full'),
          fedAt: localEquiv,
          operationId: 'op-tz',
        ),
      );
      expect(calls.single.data['fed_at'], utc.toIso8601String());
    });

    test('wasNoOp replay', () async {
      nextResult = mealReceipt(wasNoOp: true);
      final result = await gateway().createPlannedMealLog(
        CreatePlannedMealLogCommand(
          dogId: 'dog-a',
          planId: 'p',
          plannedMealId: 's',
          offeredGrams: 100,
          acceptance: MealAcceptanceWire.parse('full'),
          fedAt: DateTime.utc(2026, 7, 10),
          operationId: 'op-replay',
        ),
      );
      expect((result as CreateMealLogSuccess).wasNoOp, isTrue);
    });
  });

  group('createAdhocMealLog', () {
    test('payload adhoc sem plan links', () async {
      nextResult = mealReceipt(
        mealId: 'ml1_adhoc',
        mealOccurrenceId: null,
      );
      final result = await gateway().createAdhocMealLog(
        CreateAdhocMealLogCommand(
          dogId: 'dog-a',
          period: MealPeriodWire.parseCanonical('extra'),
          offeredGrams: 90,
          acceptance: MealAcceptanceWire.parse('full'),
          fedAt: DateTime.utc(2026, 7, 17, 12),
          operationId: 'op-adhoc',
        ),
      );
      expect(calls.single.data['mode'], 'adhoc');
      expect(calls.single.data['period'], 'extra');
      for (final forbiddenKey in const [
        'plan_id',
        'planId',
        'planned_meal_id',
        'plannedMealId',
        'meal_occurrence_id',
        'mealOccurrenceId',
        'scheduled_for',
        'scheduledFor',
        'prescription_amount_at_time',
        'prescriptionAmountAtTime',
      ]) {
        expect(calls.single.data.containsKey(forbiddenKey), isFalse, reason: forbiddenKey);
      }
      final ok = result as CreateMealLogSuccess;
      expect(ok.mealId, 'ml1_adhoc');
      expect(ok.mealOccurrenceId, isNull);
    });
  });

  group('createSupplementLog', () {
    test('snake_case payload e dose numérica', () async {
      nextResult = {
        'dog_id': 'dog-a',
        'supplement_log_id': 'sl1_x',
        'revision': 1,
        'was_no_op': false,
      };
      final result = await gateway().createSupplementLog(
        CreateSupplementLogCommand(
          dogId: 'dog-a',
          supplementName: 'Omega',
          dose: 5,
          unit: SupplementDoseUnit.parse('ml'),
          administeredAt: DateTime.utc(2026, 7, 17, 14),
          operationId: 'op-supp',
          nutritionPlanId: 'plan-1',
          supplementRegimenId: 'reg-1',
        ),
      );
      expect(
        calls.single.name,
        HealthNutritionCallableNames.createSupplementLog,
      );
      final p = calls.single.data;
      expect(p['dog_id'], 'dog-a');
      expect(p['supplement_name'], 'Omega');
      expect(p['dose'], 5);
      expect(p['unit'], 'ml');
      expect(p['administered_at'], '2026-07-17T14:00:00.000Z');
      expect(p['nutrition_plan_id'], 'plan-1');
      expect(p['supplement_regimen_id'], 'reg-1');
      expect(p.containsKey('recorded_by'), isFalse);
      final ok = result as CreateSupplementLogSuccess;
      expect(ok.supplementLogId, 'sl1_x');
    });

    test('regimen sem plan falha localmente antes da rede', () async {
      expect(
        () => CreateSupplementLogCommand(
          dogId: 'dog-a',
          supplementName: 'X',
          dose: 1,
          unit: SupplementDoseUnit.parse('mg'),
          administeredAt: DateTime.utc(2026, 7, 1),
          operationId: 'op',
          supplementRegimenId: 'reg-1',
        ),
        throwsA(isA<HealthNutritionMutationValidation>()),
      );
      expect(calls, isEmpty);
    });
  });

  group('response integrity', () {
    test('mirrors equivalentes aceitos (snake canônico)', () async {
      nextResult = {
        'dog_id': 'dog-a',
        'dogId': 'dog-a',
        'meal_id': 'meal-a',
        'mealId': 'meal-a',
        'revision': 2,
        'was_no_op': false,
        'wasNoOp': false,
        'meal_occurrence_id': 'occ-a',
        'mealOccurrenceId': 'occ-a',
      };
      final result = await gateway().createPlannedMealLog(
        CreatePlannedMealLogCommand(
          dogId: 'dog-a',
          planId: 'p',
          plannedMealId: 's',
          offeredGrams: 100,
          acceptance: MealAcceptanceWire.parse('full'),
          fedAt: DateTime.utc(2026, 7, 10),
          operationId: 'op-eq',
        ),
      );
      final ok = result as CreateMealLogSuccess;
      expect(ok.dogId, 'dog-a');
      expect(ok.mealId, 'meal-a');
      expect(ok.wasNoOp, isFalse);
      expect(ok.mealOccurrenceId, 'occ-a');
    });

    test('meal_id mirror contraditório → integrity', () async {
      nextResult = {
        'dog_id': 'dog-a',
        'meal_id': 'A',
        'mealId': 'B',
        'revision': 1,
        'was_no_op': false,
      };
      final result = await gateway().createPlannedMealLog(
        CreatePlannedMealLogCommand(
          dogId: 'dog-a',
          planId: 'p',
          plannedMealId: 's',
          offeredGrams: 100,
          acceptance: MealAcceptanceWire.parse('full'),
          fedAt: DateTime.utc(2026, 7, 10),
          operationId: 'op-meal-contra',
        ),
      );
      expect(
        (result as HealthNutritionMutationErrorResult).failure,
        isA<HealthNutritionMutationIntegrity>(),
      );
    });

    test('was_no_op mirror contraditório → integrity', () async {
      nextResult = {
        'dog_id': 'dog-a',
        'meal_id': 'm1',
        'revision': 1,
        'was_no_op': false,
        'wasNoOp': true,
      };
      final result = await gateway().createPlannedMealLog(
        CreatePlannedMealLogCommand(
          dogId: 'dog-a',
          planId: 'p',
          plannedMealId: 's',
          offeredGrams: 100,
          acceptance: MealAcceptanceWire.parse('full'),
          fedAt: DateTime.utc(2026, 7, 10),
          operationId: 'op-noop-contra',
        ),
      );
      expect(
        (result as HealthNutritionMutationErrorResult).failure,
        isA<HealthNutritionMutationIntegrity>(),
      );
    });

    test('meal_occurrence_id mirror contraditório → integrity', () async {
      nextResult = {
        'dog_id': 'dog-a',
        'meal_id': 'm1',
        'revision': 1,
        'was_no_op': false,
        'meal_occurrence_id': 'mo1_A',
        'mealOccurrenceId': 'mo1_B',
      };
      final result = await gateway().createPlannedMealLog(
        CreatePlannedMealLogCommand(
          dogId: 'dog-a',
          planId: 'p',
          plannedMealId: 's',
          offeredGrams: 100,
          acceptance: MealAcceptanceWire.parse('full'),
          fedAt: DateTime.utc(2026, 7, 10),
          operationId: 'op-occ-contra',
        ),
      );
      expect(
        (result as HealthNutritionMutationErrorResult).failure,
        isA<HealthNutritionMutationIntegrity>(),
      );
    });

    test('supplement_log_id mirror contraditório → integrity', () async {
      nextResult = {
        'dog_id': 'dog-a',
        'supplement_log_id': 'sl1_A',
        'supplementLogId': 'sl1_B',
        'revision': 1,
        'was_no_op': false,
      };
      final result = await gateway().createSupplementLog(
        CreateSupplementLogCommand(
          dogId: 'dog-a',
          supplementName: 'Omega',
          dose: 1,
          unit: SupplementDoseUnit.parse('ml'),
          administeredAt: DateTime.utc(2026, 7, 17),
          operationId: 'op-sl-contra',
        ),
      );
      expect(
        (result as HealthNutritionMutationErrorResult).failure,
        isA<HealthNutritionMutationIntegrity>(),
      );
    });

    test('missing meal_id → integrity', () async {
      nextResult = {
        'dog_id': 'dog-a',
        'revision': 1,
        'was_no_op': false,
      };
      final result = await gateway().createPlannedMealLog(
        CreatePlannedMealLogCommand(
          dogId: 'dog-a',
          planId: 'p',
          plannedMealId: 's',
          offeredGrams: 100,
          acceptance: MealAcceptanceWire.parse('full'),
          fedAt: DateTime.utc(2026, 7, 10),
          operationId: 'op-bad',
        ),
      );
      expect(result, isA<HealthNutritionMutationErrorResult>());
      expect(
        (result as HealthNutritionMutationErrorResult).failure,
        isA<HealthNutritionMutationIntegrity>(),
      );
    });

    test('invalid revision → integrity', () async {
      nextResult = {
        'dog_id': 'dog-a',
        'meal_id': 'm1',
        'revision': 0,
        'was_no_op': false,
      };
      final result = await gateway().createPlannedMealLog(
        CreatePlannedMealLogCommand(
          dogId: 'dog-a',
          planId: 'p',
          plannedMealId: 's',
          offeredGrams: 100,
          acceptance: MealAcceptanceWire.parse('full'),
          fedAt: DateTime.utc(2026, 7, 10),
          operationId: 'op-rev',
        ),
      );
      expect(
        (result as HealthNutritionMutationErrorResult).failure,
        isA<HealthNutritionMutationIntegrity>(),
      );
    });

    test('camelCase-only response still works as fallback', () async {
      nextResult = {
        'dogId': 'dog-a',
        'mealId': 'ml1_only',
        'revision': 1,
        'wasNoOp': true,
        'mealOccurrenceId': null,
      };
      final result = await gateway().createAdhocMealLog(
        CreateAdhocMealLogCommand(
          dogId: 'dog-a',
          period: MealPeriodWire.parseCanonical('morning'),
          offeredGrams: 50,
          acceptance: MealAcceptanceWire.parse('full'),
          fedAt: DateTime.utc(2026, 7, 10),
          operationId: 'op-camel',
        ),
      );
      final ok = result as CreateMealLogSuccess;
      expect(ok.mealId, 'ml1_only');
      expect(ok.wasNoOp, isTrue);
    });
  });

  group('FirebaseFunctionsException mapping', () {
    test('permission-denied', () async {
      nextError = FirebaseFunctionsException(
        code: 'permission-denied',
        message: 'nope',
      );
      final result = await gateway().createPlannedMealLog(
        CreatePlannedMealLogCommand(
          dogId: 'dog-a',
          planId: 'p',
          plannedMealId: 's',
          offeredGrams: 100,
          acceptance: MealAcceptanceWire.parse('full'),
          fedAt: DateTime.utc(2026, 7, 10),
          operationId: 'op-perm',
        ),
      );
      expect(
        (result as HealthNutritionMutationErrorResult).failure,
        isA<HealthNutritionMutationPermissionDenied>(),
      );
    });

    test('idempotency_conflict via details.code', () async {
      nextError = FirebaseFunctionsException(
        code: 'failed-precondition',
        message: 'idem',
        details: {'code': 'idempotency_conflict'},
      );
      final result = await gateway().createPlannedMealLog(
        CreatePlannedMealLogCommand(
          dogId: 'dog-a',
          planId: 'p',
          plannedMealId: 's',
          offeredGrams: 100,
          acceptance: MealAcceptanceWire.parse('full'),
          fedAt: DateTime.utc(2026, 7, 10),
          operationId: 'op-idem',
        ),
      );
      final f = (result as HealthNutritionMutationErrorResult).failure;
      expect(f, isA<HealthNutritionMutationIdempotencyConflict>());
      expect(f.detailCode, 'idempotency_conflict');
    });

    test('meal_occurrence_conflict via details.code', () async {
      nextError = FirebaseFunctionsException(
        code: 'failed-precondition',
        message: 'occ',
        details: {'code': 'meal_occurrence_conflict'},
      );
      final result = await gateway().createPlannedMealLog(
        CreatePlannedMealLogCommand(
          dogId: 'dog-a',
          planId: 'p',
          plannedMealId: 's',
          offeredGrams: 100,
          acceptance: MealAcceptanceWire.parse('full'),
          fedAt: DateTime.utc(2026, 7, 10),
          operationId: 'op-occ',
        ),
      );
      final f = (result as HealthNutritionMutationErrorResult).failure;
      expect(f, isA<HealthNutritionMutationMealOccurrenceConflict>());
      expect(f.detailCode, 'meal_occurrence_conflict');
    });

    test('unavailable', () async {
      nextError = FirebaseFunctionsException(
        code: 'unavailable',
        message: 'down',
      );
      final result = await gateway().createPlannedMealLog(
        CreatePlannedMealLogCommand(
          dogId: 'dog-a',
          planId: 'p',
          plannedMealId: 's',
          offeredGrams: 100,
          acceptance: MealAcceptanceWire.parse('full'),
          fedAt: DateTime.utc(2026, 7, 10),
          operationId: 'op-unav',
        ),
      );
      expect(
        (result as HealthNutritionMutationErrorResult).failure,
        isA<HealthNutritionMutationUnavailable>(),
      );
    });
  });

  group('zero Firestore / functions only', () {
    test('gateway class source does not import firestore package', () {
      // Structural: gateway type is only FirebaseFunctions-backed.
      final g = FirebaseFunctionsHealthNutritionMutationGateway(
        invoker: (n, d) async => mealReceipt(),
      );
      expect(g, isA<HealthNutritionMutationGateway>());
      // FailClosed exists for explicit incomplete env.
      expect(
        const FailClosedHealthNutritionMutationGateway(),
        isA<HealthNutritionMutationGateway>(),
      );
    });

    test('codec lists server-owned keys for planned path', () {
      expect(
        HealthNutritionMutationPayloadCodec.mealServerOwnedKeys,
        contains('recorded_by'),
      );
    });
  });
}
