import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/data/schedule/firebase_functions_health_schedule_mutation_gateway.dart';
import 'package:canil_gcm/features/health/data/schedule/health_schedule_callable_names.dart';
import 'package:canil_gcm/features/health/data/schedule/health_schedule_mutation_payload_codec.dart';
import 'package:canil_gcm/features/health/domain/health_schedule_mutation_commands.dart';
import 'package:canil_gcm/features/health/domain/health_schedule_mutation_errors.dart';
import 'package:canil_gcm/features/health/domain/health_schedule_mutation_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_schedule_revision.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';

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

  FirebaseFunctionsHealthScheduleMutationGateway gateway() {
    return FirebaseFunctionsHealthScheduleMutationGateway(
      invoker: (name, data) async {
        calls.add((name: name, data: Map<String, dynamic>.from(data)));
        final err = nextError;
        if (err != null) {
          throw err;
        }
        final r = nextResult;
        if (r == null) {
          throw StateError('nextResult não configurado');
        }
        return Map<String, dynamic>.from(r);
      },
    );
  }

  Map<String, dynamic> receipt({
    String dogId = 'dog-a',
    String scheduleId = 'sched-1',
    int revision = 1,
    bool wasNoOp = false,
    String lifecycle = 'open',
  }) {
    return {
      'dogId': dogId,
      'scheduleId': scheduleId,
      'revision': revision,
      'wasNoOp': wasNoOp,
      'lifecycleStatus': lifecycle,
    };
  }

  group('createManual', () {
    test('nome do callable, payload e ausência de server-owned', () async {
      nextResult = receipt(revision: 1, wasNoOp: false);
      final scheduled = DateTime.utc(2026, 8, 1, 12);
      final cmd = CreateManualScheduleItemCommand(
        dogId: 'dog-a',
        scheduleType: ScheduleType.vaccination,
        title: 'Vacina',
        scheduledFor: scheduled,
        timezone: 'America/Sao_Paulo',
        operationId: 'idem-create-1',
        dueUntil: DateTime.utc(2026, 8, 2, 12),
        notes: 'obs',
        caseId: 'case-should-not-send',
        clientGeneratedId: 'client-id-should-not-send',
      );

      final result = await gateway().createManual(cmd);
      expect(result, isA<HealthScheduleMutationSuccess>());
      final ok = result as HealthScheduleMutationSuccess;
      expect(ok.scheduleId, 'sched-1');
      expect(ok.revision, HealthScheduleRevision.numeric(1));
      expect(ok.wasNoOp, isFalse);
      expect(ok.lifecycleStatus, ScheduleLifecycleStatus.open);
      expect(ok.operationId, 'idem-create-1');

      expect(calls, hasLength(1));
      expect(calls.single.name, HealthScheduleCallableNames.createManual);
      final payload = calls.single.data;
      expect(payload['dogId'], 'dog-a');
      expect(payload['scheduleType'], 'vaccination');
      expect(payload['title'], 'Vacina');
      expect(payload['timezone'], 'America/Sao_Paulo');
      expect(payload['idempotencyKey'], 'idem-create-1');
      expect(payload['scheduledFor'], scheduled.toIso8601String());
      expect(
        payload['dueUntil'],
        DateTime.utc(2026, 8, 2, 12).toIso8601String(),
      );
      expect(payload['notes'], 'obs');
      expect(payload.containsKey('caseId'), isFalse);
      expect(payload.containsKey('case_id'), isFalse);
      expect(payload.containsKey('clientGeneratedId'), isFalse);
      for (final key
          in HealthScheduleMutationPayloadCodec.createServerOwnedKeys) {
        expect(payload.containsKey(key), isFalse, reason: 'server-owned $key');
      }
    });

    test('preserva wasNoOp de replay', () async {
      nextResult = receipt(wasNoOp: true, revision: 1);
      final result = await gateway().createManual(
        CreateManualScheduleItemCommand(
          dogId: 'dog-a',
          scheduleType: ScheduleType.general,
          title: 'x',
          scheduledFor: DateTime.utc(2026, 8, 1),
          timezone: 'America/Sao_Paulo',
          operationId: 'idem-2',
        ),
      );
      expect((result as HealthScheduleMutationSuccess).wasNoOp, isTrue);
    });
  });

  group('updateOpen', () {
    test('serializa expectedRevision, operationId e patch whitelist', () async {
      nextResult = receipt(revision: 4, wasNoOp: false);
      final opId = 'upd-op-exact-42';
      final result = await gateway().updateOpen(
        UpdateOpenScheduleItemCommand(
          dogId: 'dog-a',
          scheduleId: 'sched-1',
          expectedRevision: HealthScheduleRevision.numeric(3),
          operationId: opId,
          title: 'Novo título',
          clearNotes: true,
        ),
      );
      expect(result, isA<HealthScheduleMutationSuccess>());
      expect(
        (result as HealthScheduleMutationSuccess).revision,
        HealthScheduleRevision.numeric(4),
      );
      expect(calls.single.name, HealthScheduleCallableNames.updateOpen);
      final payload = calls.single.data;
      expect(payload['dogId'], 'dog-a');
      expect(payload['scheduleId'], 'sched-1');
      expect(payload['expectedRevision'], 3);
      expect(payload['operationId'], opId);
      final patch = payload['patch'] as Map<String, dynamic>;
      expect(patch.keys.toSet(), {'title', 'clearNotes'});
      expect(patch['title'], 'Novo título');
      expect(patch['clearNotes'], isTrue);
      expect(patch.containsKey('source_type'), isFalse);
      expect(patch.containsKey('lifecycle_status'), isFalse);
      expect(patch.containsKey('revision'), isFalse);
    });

    test('revision inválida localmente falha antes da rede', () async {
      final result = await gateway().updateOpen(
        UpdateOpenScheduleItemCommand(
          dogId: 'dog-a',
          scheduleId: 'sched-1',
          expectedRevision: const HealthScheduleRevision('not-a-number'),
          operationId: 'op-1',
          title: 'x',
        ),
      );
      expect(result, isA<HealthScheduleMutationErrorResult>());
      expect(
        (result as HealthScheduleMutationErrorResult).failure,
        isA<HealthScheduleMutationValidation>(),
      );
      expect(calls, isEmpty);
    });
  });

  group('complete', () {
    test('callable, payload mínimo e wasNoOp', () async {
      nextResult = receipt(revision: 2, wasNoOp: true, lifecycle: 'completed');
      final result = await gateway().complete(
        CompleteScheduleItemCommand(
          dogId: 'dog-a',
          scheduleId: 'sched-1',
          operationId: 'cmp-1',
        ),
      );
      expect(calls.single.name, HealthScheduleCallableNames.complete);
      expect(calls.single.data.keys.toSet(), {
        'dogId',
        'scheduleId',
        'operationId',
      });
      final ok = result as HealthScheduleMutationSuccess;
      expect(ok.wasNoOp, isTrue);
      expect(ok.lifecycleStatus, ScheduleLifecycleStatus.completed);
      expect(ok.operationId, 'cmp-1');
      expect(calls.single.data.containsKey('completed_at'), isFalse);
      expect(calls.single.data.containsKey('completed_by'), isFalse);
      expect(calls.single.data.containsKey('lifecycle_status'), isFalse);
    });
  });

  group('cancel', () {
    test('operationId e reason preservados; cancelled no-op', () async {
      nextResult = receipt(revision: 5, wasNoOp: true, lifecycle: 'cancelled');
      final result = await gateway().cancel(
        CancelScheduleItemCommand(
          dogId: 'dog-a',
          scheduleId: 'sched-1',
          cancelReason: 'Motivo real',
          operationId: 'cancel-op-99',
        ),
      );
      expect(calls.single.name, HealthScheduleCallableNames.cancel);
      expect(calls.single.data['operationId'], 'cancel-op-99');
      expect(calls.single.data['cancelReason'], 'Motivo real');
      expect(calls.single.data.containsKey('cancelled_at'), isFalse);
      expect(calls.single.data.containsKey('cancelled_by'), isFalse);
      final ok = result as HealthScheduleMutationSuccess;
      expect(ok.wasNoOp, isTrue);
      expect(ok.lifecycleStatus, ScheduleLifecycleStatus.cancelled);
      expect(ok.operationId, 'cancel-op-99');
    });
  });

  group('error mapping', () {
    Future<HealthScheduleMutationFailure> failureFor(
      FirebaseFunctionsException e,
    ) async {
      nextError = e;
      final result = await gateway().complete(
        CompleteScheduleItemCommand(
          dogId: 'd',
          scheduleId: 's',
          operationId: 'o',
        ),
      );
      return (result as HealthScheduleMutationErrorResult).failure;
    }

    test('unauthenticated', () async {
      expect(
        await failureFor(
          FirebaseFunctionsException(code: 'unauthenticated', message: 'x'),
        ),
        isA<HealthScheduleMutationUnauthenticated>(),
      );
    });

    test('permission-denied', () async {
      expect(
        await failureFor(
          FirebaseFunctionsException(code: 'permission-denied', message: 'x'),
        ),
        isA<HealthScheduleMutationPermissionDenied>(),
      );
    });

    test('not-found', () async {
      expect(
        await failureFor(
          FirebaseFunctionsException(code: 'not-found', message: 'x'),
        ),
        isA<HealthScheduleMutationNotFound>(),
      );
    });

    test('conflict via details.code', () async {
      final f = await failureFor(
        FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'stale',
          details: {'code': 'conflict'},
        ),
      );
      expect(f, isA<HealthScheduleMutationConflict>());
    });

    test('idempotency-conflict via details', () async {
      final f = await failureFor(
        FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'idem',
          details: {'code': 'idempotency-conflict'},
        ),
      );
      expect(f, isA<HealthScheduleMutationIdempotencyConflict>());
    });

    test('already-completed', () async {
      final f = await failureFor(
        FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'done',
          details: {'code': 'already-completed'},
        ),
      );
      expect(f, isA<HealthScheduleMutationAlreadyCompleted>());
    });

    test('already-cancelled', () async {
      final f = await failureFor(
        FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'canc',
          details: {'code': 'already-cancelled'},
        ),
      );
      expect(f, isA<HealthScheduleMutationAlreadyCancelled>());
    });

    test('invalid-transition', () async {
      final f = await failureFor(
        FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'bad',
          details: {'code': 'invalid-transition'},
        ),
      );
      expect(f, isA<HealthScheduleMutationInvalidTransition>());
    });

    test('validation (invalid-argument)', () async {
      final f = await failureFor(
        FirebaseFunctionsException(
          code: 'invalid-argument',
          message: 'bad field',
        ),
      );
      expect(f, isA<HealthScheduleMutationValidation>());
    });

    test('integrity via details', () async {
      final f = await failureFor(
        FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'broken',
          details: {'code': 'integrity'},
        ),
      );
      expect(f, isA<HealthScheduleMutationIntegrity>());
    });

    test('unexpected / unknown firebase code', () async {
      final f = await failureFor(
        FirebaseFunctionsException(code: 'resource-exhausted', message: 'x'),
      );
      expect(f, isA<HealthScheduleMutationUnexpected>());
    });

    test('erro não Firebase → unexpected tipado', () async {
      nextError = StateError('boom');
      final result = await gateway().cancel(
        CancelScheduleItemCommand(
          dogId: 'd',
          scheduleId: 's',
          cancelReason: 'r',
          operationId: 'o',
        ),
      );
      expect(
        (result as HealthScheduleMutationErrorResult).failure,
        isA<HealthScheduleMutationUnexpected>(),
      );
    });

    test('payload de resposta inválido → integrity', () async {
      nextResult = {'dogId': 'd'}; // incompleto
      final result = await gateway().complete(
        CompleteScheduleItemCommand(dogId: 'd', scheduleId: 's'),
      );
      expect(
        (result as HealthScheduleMutationErrorResult).failure,
        isA<HealthScheduleMutationIntegrity>(),
      );
    });

    test('Firebase exception não atravessa o gateway', () async {
      nextError = FirebaseFunctionsException(code: 'not-found', message: 'x');
      final result = await gateway().updateOpen(
        UpdateOpenScheduleItemCommand(
          dogId: 'd',
          scheduleId: 's',
          expectedRevision: HealthScheduleRevision.numeric(1),
          operationId: 'o',
          title: 't',
        ),
      );
      expect(result, isA<HealthScheduleMutationErrorResult>());
      expect(
        () => throw (result as HealthScheduleMutationErrorResult).failure,
        isNot(throwsA(isA<FirebaseFunctionsException>())),
      );
    });
  });

  group('região canônica', () {
    test('constante southamerica-east1', () {
      expect(HealthScheduleCallableNames.region, 'southamerica-east1');
    });
  });
}
