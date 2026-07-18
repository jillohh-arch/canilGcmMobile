import 'package:canil_gcm/features/health/domain/health_schedule_item.dart';
import 'package:canil_gcm/features/health/domain/health_schedule_mutation_commands.dart';
import 'package:canil_gcm/features/health/domain/health_schedule_mutation_errors.dart';
import 'package:canil_gcm/features/health/domain/health_schedule_mutation_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_controller.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_mutation_controller.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_mutation_outcome.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_mutation_user_copy.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_query.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_source.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_health_schedule_source.dart';
import 'schedule_test_helpers.dart';

class _SpyGateway implements HealthScheduleMutationGateway {
  final List<Object> commands = [];
  HealthScheduleMutationResult? next;
  int createCalls = 0;
  int updateCalls = 0;
  int completeCalls = 0;
  int cancelCalls = 0;
  Duration delay = Duration.zero;

  @override
  Future<HealthScheduleMutationResult> createManual(
    CreateManualScheduleItemCommand command,
  ) async {
    createCalls++;
    commands.add(command);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return next ??
        const HealthScheduleMutationErrorResult(
          HealthScheduleMutationUnexpected(),
        );
  }

  @override
  Future<HealthScheduleMutationResult> updateOpen(
    UpdateOpenScheduleItemCommand command,
  ) async {
    updateCalls++;
    commands.add(command);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return next ??
        const HealthScheduleMutationErrorResult(
          HealthScheduleMutationUnexpected(),
        );
  }

  @override
  Future<HealthScheduleMutationResult> complete(
    CompleteScheduleItemCommand command,
  ) async {
    completeCalls++;
    commands.add(command);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return next ??
        const HealthScheduleMutationErrorResult(
          HealthScheduleMutationUnexpected(),
        );
  }

  @override
  Future<HealthScheduleMutationResult> cancel(
    CancelScheduleItemCommand command,
  ) async {
    cancelCalls++;
    commands.add(command);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return next ??
        const HealthScheduleMutationErrorResult(
          HealthScheduleMutationUnexpected(),
        );
  }
}

void main() {
  late FakeHealthScheduleSource source;
  late HealthScheduleController schedule;
  late _SpyGateway gateway;
  late HealthScheduleMutationController mutation;
  var idSeq = 0;

  setUp(() {
    source = FakeHealthScheduleSource();
    schedule = HealthScheduleController(
      source: source,
      temporalPolicy: testSchedulePolicy(),
      clock: () => scheduleTestNow,
    );
    gateway = _SpyGateway();
    idSeq = 0;
    mutation = HealthScheduleMutationController(
      gateway: gateway,
      scheduleController: schedule,
      operationIdFactory: () => 'op-${++idSeq}',
    );
  });

  tearDown(() {
    mutation.dispose();
    schedule.dispose();
    source.reset();
  });

  Future<void> loadDog({List<HealthScheduleItem>? items}) async {
    source.enqueuePage(schedulePage(items ?? const <HealthScheduleItem>[]));
    await schedule.setQuery(HealthScheduleQuery(dogId: 'dog-a'));
  }

  HealthScheduleMutationSuccess success({
    String scheduleId = 'sched-1',
    int revision = 1,
    ScheduleLifecycleStatus lifecycle = ScheduleLifecycleStatus.open,
    bool wasNoOp = false,
  }) {
    return HealthScheduleMutationSuccess(
      dogId: 'dog-a',
      scheduleId: scheduleId,
      revision: HealthScheduleRevision.numeric(revision),
      wasNoOp: wasNoOp,
      lifecycleStatus: lifecycle,
      operationId: 'op-x',
    );
  }

  group('create', () {
    test('submit válido + refresh', () async {
      await loadDog();
      gateway.next = success(scheduleId: 'new-1');
      source.enqueuePage(
        schedulePage([
          scheduleItem(
            id: 'new-1',
            title: 'Vacina',
            revision: const HealthScheduleRevision('1'),
          ),
        ]),
      );

      final key = mutation.ensureCreateIdempotencyKey();
      final outcome = await mutation.createManual(
        dogId: 'dog-a',
        scheduleType: ScheduleType.vaccination,
        title: 'Vacina',
        scheduledFor: scheduleTestNow.add(const Duration(days: 1)),
        timezone: 'America/Sao_Paulo',
      );

      expect(outcome, isA<HealthScheduleMutationUiSuccess>());
      final ok = outcome as HealthScheduleMutationUiSuccess;
      expect(ok.refreshFailed, isFalse);
      expect(ok.successMessage, HealthScheduleMutationUserCopy.successCreated);
      expect(gateway.createCalls, 1);
      final cmd = gateway.commands.single as CreateManualScheduleItemCommand;
      expect(cmd.operationId, key);
      expect(mutation.createIdempotencyKeyForTest, isNull);
      expect(source.requests.length, greaterThanOrEqualTo(2));
    });

    test('double submit → uma operação', () async {
      await loadDog();
      gateway.delay = const Duration(milliseconds: 40);
      gateway.next = success();
      source.enqueuePage(schedulePage(const []));
      source.enqueuePage(schedulePage(const []));

      mutation.ensureCreateIdempotencyKey();
      final f1 = mutation.createManual(
        dogId: 'dog-a',
        scheduleType: ScheduleType.general,
        title: 'A',
        scheduledFor: scheduleTestNow,
        timezone: 'America/Sao_Paulo',
      );
      final f2 = mutation.createManual(
        dogId: 'dog-a',
        scheduleType: ScheduleType.general,
        title: 'A',
        scheduledFor: scheduleTestNow,
        timezone: 'America/Sao_Paulo',
      );
      final r1 = await f1;
      final r2 = await f2;
      expect(r1, isA<HealthScheduleMutationUiSuccess>());
      expect(r2, isA<HealthScheduleMutationUiBlocked>());
      expect(gateway.createCalls, 1);
    });

    test('sucesso + refresh failure não é failure de mutação', () async {
      await loadDog(items: [scheduleItem(id: 'keep')]);
      gateway.next = success(scheduleId: 'n1');
      source.enqueueError(const HealthScheduleSourceException('rede caiu'));

      mutation.ensureCreateIdempotencyKey();
      final outcome = await mutation.createManual(
        dogId: 'dog-a',
        scheduleType: ScheduleType.general,
        title: 'X',
        scheduledFor: scheduleTestNow,
        timezone: 'America/Sao_Paulo',
      );

      expect(outcome, isA<HealthScheduleMutationUiSuccess>());
      final ok = outcome as HealthScheduleMutationUiSuccess;
      expect(ok.refreshFailed, isTrue);
      expect(
        ok.refreshWarning,
        HealthScheduleMutationUserCopy.refreshFailedAfterSuccess,
      );
    });

    test('permission denied mapeado', () async {
      await loadDog();
      gateway.next = const HealthScheduleMutationErrorResult(
        HealthScheduleMutationPermissionDenied(),
      );

      mutation.ensureCreateIdempotencyKey();
      final outcome = await mutation.createManual(
        dogId: 'dog-a',
        scheduleType: ScheduleType.general,
        title: 'X',
        scheduledFor: scheduleTestNow,
        timezone: 'America/Sao_Paulo',
      );

      expect(outcome, isA<HealthScheduleMutationUiFailure>());
      final fail = outcome as HealthScheduleMutationUiFailure;
      expect(fail.failure, isA<HealthScheduleMutationPermissionDenied>());
      expect(
        fail.userMessage,
        'Você não tem permissão para realizar esta ação.',
      );
      expect(fail.shouldRefresh, isFalse);
    });

    test('offline mapeado', () async {
      await loadDog();
      gateway.next = const HealthScheduleMutationErrorResult(
        HealthScheduleMutationOffline(),
      );
      mutation.ensureCreateIdempotencyKey();
      final outcome = await mutation.createManual(
        dogId: 'dog-a',
        scheduleType: ScheduleType.general,
        title: 'X',
        scheduledFor: scheduleTestNow,
        timezone: 'America/Sao_Paulo',
      );
      final fail = outcome as HealthScheduleMutationUiFailure;
      expect(fail.failure, isA<HealthScheduleMutationOffline>());
      expect(fail.userMessage, contains('Sem conexão'));
    });

    test('validation mapeado', () async {
      await loadDog();
      gateway.next = const HealthScheduleMutationErrorResult(
        HealthScheduleMutationValidation('título inválido'),
      );
      mutation.ensureCreateIdempotencyKey();
      final outcome = await mutation.createManual(
        dogId: 'dog-a',
        scheduleType: ScheduleType.general,
        title: 'X',
        scheduledFor: scheduleTestNow,
        timezone: 'America/Sao_Paulo',
      );
      final fail = outcome as HealthScheduleMutationUiFailure;
      expect(fail.userMessage, 'título inválido');
    });

    test('idempotencyKey estável em retry da mesma intenção', () async {
      await loadDog();
      final k1 = mutation.ensureCreateIdempotencyKey();
      final k2 = mutation.ensureCreateIdempotencyKey();
      expect(k1, k2);
      expect(k1, 'op-1');

      gateway.next = const HealthScheduleMutationErrorResult(
        HealthScheduleMutationOffline(),
      );
      await mutation.createManual(
        dogId: 'dog-a',
        scheduleType: ScheduleType.general,
        title: 'X',
        scheduledFor: scheduleTestNow,
        timezone: 'America/Sao_Paulo',
      );
      // após falha a key permanece para retry
      expect(mutation.createIdempotencyKeyForTest, k1);

      gateway.next = success();
      source.enqueuePage(schedulePage(const []));
      await mutation.createManual(
        dogId: 'dog-a',
        scheduleType: ScheduleType.general,
        title: 'X',
        scheduledFor: scheduleTestNow,
        timezone: 'America/Sao_Paulo',
      );
      expect(gateway.createCalls, 2);
      final cmds = gateway.commands
          .whereType<CreateManualScheduleItemCommand>();
      expect(cmds.every((c) => c.operationId == k1), isTrue);
      expect(mutation.createIdempotencyKeyForTest, isNull);
    });
  });

  group('update', () {
    test('envia revision e operationId estáveis', () async {
      final item = scheduleItem(
        id: 's1',
        revision: const HealthScheduleRevision('3'),
      );
      await loadDog(items: [item]);
      gateway.next = success(revision: 4);
      source.enqueuePage(
        schedulePage([
          scheduleItem(
            id: 's1',
            title: 'Novo',
            revision: const HealthScheduleRevision('4'),
          ),
        ]),
      );

      mutation.beginUpdateIntent('s1');
      final opId = mutation.ensureUpdateOperationId('s1');
      final outcome = await mutation.updateOpen(
        dogId: 'dog-a',
        scheduleId: 's1',
        expectedRevision: const HealthScheduleRevision('3'),
        title: 'Novo',
      );

      expect(outcome, isA<HealthScheduleMutationUiSuccess>());
      final cmd = gateway.commands.single as UpdateOpenScheduleItemCommand;
      expect(cmd.expectedRevision.token, '3');
      expect(cmd.operationId, opId);
      expect(mutation.updateOperationIdForTest('s1'), isNull);
    });

    test('conflict → shouldRefresh', () async {
      await loadDog(items: [scheduleItem(id: 's1')]);
      gateway.next = const HealthScheduleMutationErrorResult(
        HealthScheduleMutationConflict(),
      );
      final outcome = await mutation.updateOpen(
        dogId: 'dog-a',
        scheduleId: 's1',
        expectedRevision: const HealthScheduleRevision('1'),
        title: 'X',
      );
      final fail = outcome as HealthScheduleMutationUiFailure;
      expect(fail.failure, isA<HealthScheduleMutationConflict>());
      expect(fail.shouldRefresh, isTrue);
      expect(fail.userMessage, contains('outra sessão'));
    });

    test('not-found → shouldRefresh', () async {
      await loadDog();
      gateway.next = const HealthScheduleMutationErrorResult(
        HealthScheduleMutationNotFound(),
      );
      final outcome = await mutation.updateOpen(
        dogId: 'dog-a',
        scheduleId: 'missing',
        expectedRevision: const HealthScheduleRevision('1'),
        title: 'X',
      );
      final fail = outcome as HealthScheduleMutationUiFailure;
      expect(fail.shouldRefresh, isTrue);
    });
  });

  group('complete', () {
    test('sucesso', () async {
      await loadDog(items: [scheduleItem(id: 's1')]);
      gateway.next = success(
        lifecycle: ScheduleLifecycleStatus.completed,
        wasNoOp: false,
      );
      source.enqueuePage(schedulePage(const []));

      final outcome = await mutation.complete(dogId: 'dog-a', scheduleId: 's1');
      expect(outcome, isA<HealthScheduleMutationUiSuccess>());
      expect(
        (outcome as HealthScheduleMutationUiSuccess).successMessage,
        HealthScheduleMutationUserCopy.successCompleted,
      );
    });

    test('replay no-op como sucesso', () async {
      await loadDog(items: [scheduleItem(id: 's1')]);
      gateway.next = success(
        lifecycle: ScheduleLifecycleStatus.completed,
        wasNoOp: true,
      );
      source.enqueuePage(schedulePage(const []));
      final outcome = await mutation.complete(dogId: 'dog-a', scheduleId: 's1');
      expect(outcome, isA<HealthScheduleMutationUiSuccess>());
      expect((outcome as HealthScheduleMutationUiSuccess).wasNoOp, isTrue);
    });

    test('alreadyCompleted → refresh flag', () async {
      await loadDog(items: [scheduleItem(id: 's1')]);
      gateway.next = const HealthScheduleMutationErrorResult(
        HealthScheduleMutationAlreadyCompleted(),
      );
      final outcome = await mutation.complete(dogId: 'dog-a', scheduleId: 's1');
      final fail = outcome as HealthScheduleMutationUiFailure;
      expect(fail.shouldRefresh, isTrue);
      expect(fail.userMessage, 'Este item já foi concluído.');
    });

    test('invalidTransition → refresh', () async {
      await loadDog();
      gateway.next = const HealthScheduleMutationErrorResult(
        HealthScheduleMutationInvalidTransition(),
      );
      final outcome = await mutation.complete(dogId: 'dog-a', scheduleId: 's1');
      expect(
        (outcome as HealthScheduleMutationUiFailure).shouldRefresh,
        isTrue,
      );
    });

    test('double complete → uma op', () async {
      await loadDog(items: [scheduleItem(id: 's1')]);
      gateway.delay = const Duration(milliseconds: 40);
      gateway.next = success(lifecycle: ScheduleLifecycleStatus.completed);
      source.enqueuePage(schedulePage(const []));
      source.enqueuePage(schedulePage(const []));

      final f1 = mutation.complete(dogId: 'dog-a', scheduleId: 's1');
      final f2 = mutation.complete(dogId: 'dog-a', scheduleId: 's1');
      final r1 = await f1;
      final r2 = await f2;
      expect(r1, isA<HealthScheduleMutationUiSuccess>());
      expect(r2, isA<HealthScheduleMutationUiBlocked>());
      expect(gateway.completeCalls, 1);
    });
  });

  group('cancel', () {
    test('reason obrigatório', () async {
      await loadDog(items: [scheduleItem(id: 's1')]);
      final outcome = await mutation.cancel(
        dogId: 'dog-a',
        scheduleId: 's1',
        cancelReason: '   ',
      );
      final fail = outcome as HealthScheduleMutationUiFailure;
      expect(fail.failure, isA<HealthScheduleMutationValidation>());
      expect(gateway.cancelCalls, 0);
    });

    test('sucesso manual', () async {
      await loadDog(items: [scheduleItem(id: 's1')]);
      gateway.next = success(lifecycle: ScheduleLifecycleStatus.cancelled);
      source.enqueuePage(schedulePage(const []));
      final outcome = await mutation.cancel(
        dogId: 'dog-a',
        scheduleId: 's1',
        cancelReason: 'Não necessário',
      );
      expect(outcome, isA<HealthScheduleMutationUiSuccess>());
      final cmd = gateway.commands.single as CancelScheduleItemCommand;
      expect(cmd.cancelReason, 'Não necessário');
    });

    test('alreadyCancelled → refresh', () async {
      await loadDog();
      gateway.next = const HealthScheduleMutationErrorResult(
        HealthScheduleMutationAlreadyCancelled(),
      );
      final outcome = await mutation.cancel(
        dogId: 'dog-a',
        scheduleId: 's1',
        cancelReason: 'x',
      );
      expect(
        (outcome as HealthScheduleMutationUiFailure).shouldRefresh,
        isTrue,
      );
    });

    test('idempotencyConflict', () async {
      await loadDog();
      gateway.next = const HealthScheduleMutationErrorResult(
        HealthScheduleMutationIdempotencyConflict(),
      );
      final outcome = await mutation.cancel(
        dogId: 'dog-a',
        scheduleId: 's1',
        cancelReason: 'motivo',
      );
      final fail = outcome as HealthScheduleMutationUiFailure;
      expect(fail.failure, isA<HealthScheduleMutationIdempotencyConflict>());
      expect(fail.userMessage, contains('Não foi possível confirmar'));
    });

    test('double cancel → uma op', () async {
      await loadDog(items: [scheduleItem(id: 's1')]);
      gateway.delay = const Duration(milliseconds: 40);
      gateway.next = success(lifecycle: ScheduleLifecycleStatus.cancelled);
      source.enqueuePage(schedulePage(const []));
      source.enqueuePage(schedulePage(const []));
      final f1 = mutation.cancel(
        dogId: 'dog-a',
        scheduleId: 's1',
        cancelReason: 'a',
      );
      final f2 = mutation.cancel(
        dogId: 'dog-a',
        scheduleId: 's1',
        cancelReason: 'a',
      );
      expect(await f1, isA<HealthScheduleMutationUiSuccess>());
      expect(await f2, isA<HealthScheduleMutationUiBlocked>());
      expect(gateway.cancelCalls, 1);
    });

    test('complete em andamento bloqueia cancel no mesmo item', () async {
      await loadDog(items: [scheduleItem(id: 's1')]);
      gateway.delay = const Duration(milliseconds: 50);
      gateway.next = success(lifecycle: ScheduleLifecycleStatus.completed);
      source.enqueuePage(schedulePage(const []));

      final fComplete = mutation.complete(dogId: 'dog-a', scheduleId: 's1');
      final fCancel = mutation.cancel(
        dogId: 'dog-a',
        scheduleId: 's1',
        cancelReason: 'nope',
      );
      expect(await fCancel, isA<HealthScheduleMutationUiBlocked>());
      expect(await fComplete, isA<HealthScheduleMutationUiSuccess>());
      expect(gateway.cancelCalls, 0);
      expect(gateway.completeCalls, 1);
    });
  });

  group('error mapping', () {
    test('unauthenticated', () {
      expect(
        HealthScheduleMutationUserCopy.messageFor(
          const HealthScheduleMutationUnauthenticated(),
        ),
        contains('sessão expirou'),
      );
    });

    test('integrity', () {
      expect(
        HealthScheduleMutationUserCopy.messageFor(
          const HealthScheduleMutationIntegrity(),
        ),
        contains('validar os dados'),
      );
    });
  });
}
