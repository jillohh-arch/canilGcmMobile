import 'package:canil_gcm/features/health/domain/health_schedule_item.dart';
import 'package:canil_gcm/features/health/domain/health_schedule_mutation_commands.dart';
import 'package:canil_gcm/features/health/domain/health_schedule_mutation_engine.dart';
import 'package:canil_gcm/features/health/domain/health_schedule_mutation_errors.dart';
import 'package:canil_gcm/features/health/domain/health_schedule_mutation_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_schedule_mutation_policy.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/health_v1_transitions_v2.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final actor = RecordedBy(
    uid: 'uid-1',
    name: 'Condutor Teste',
    internalRole: 'condutor',
  );
  final actorB = RecordedBy(
    uid: 'uid-b',
    name: 'Condutor B',
    internalRole: 'condutor',
  );
  final serverNow = DateTime.utc(2026, 7, 17, 15, 0);
  final trusted = HealthScheduleTrustedExecutionContext(
    actor: actor,
    serverNow: serverNow,
  );
  final trustedB = HealthScheduleTrustedExecutionContext(
    actor: actorB,
    serverNow: serverNow.add(const Duration(minutes: 1)),
  );

  HealthScheduleMutationStateSnapshot openSnap({
    String id = 's1',
    ScheduleSourceType source = ScheduleSourceType.manual,
    DateTime? scheduledFor,
    HealthScheduleRevision revision = const HealthScheduleRevision('0'),
    String? lastUpdateOperationId,
    String? lastLifecycleOperationId,
    String? createOperationId,
  }) {
    final item = HealthScheduleItem(
      id: id,
      dogId: 'dog-1',
      scheduleType: ScheduleType.vaccination,
      title: 'V10',
      scheduledFor: scheduledFor ?? serverNow.add(const Duration(days: 1)),
      timezone: 'America/Sao_Paulo',
      lifecycleStatus: ScheduleLifecycleStatus.open,
      sourceType: source,
      createdAt: serverNow.subtract(const Duration(hours: 1)),
      recordedBy: actor,
      schemaVersion: 1,
      sourceId: source == ScheduleSourceType.manual ? null : 'src-9',
    );
    return HealthScheduleMutationStateSnapshot(
      item: item,
      revision: revision,
      lastUpdateOperationId: lastUpdateOperationId,
      lastLifecycleOperationId: lastLifecycleOperationId,
      createOperationId: createOperationId,
    );
  }

  group('transições de lifecycle', () {
    test('open → completed válido preenche completed_* com ator confiável', () {
      final result = HealthScheduleMutationEngine.complete(
        current: openSnap(),
        command: CompleteScheduleItemCommand(
          dogId: 'dog-1',
          scheduleId: 's1',
        ),
        trusted: trusted,
      );

      expect(result.wasNoOp, isFalse);
      expect(result.item.lifecycleStatus, ScheduleLifecycleStatus.completed);
      expect(result.item.completedAt, serverNow);
      expect(result.item.completedBy, actor);
      expect(result.item.cancelledAt, isNull);
      expect(result.item.completedBy!.uid, 'uid-1');
    });

    test('open → cancelled válido exige reason e preenche cancelled_*', () {
      final result = HealthScheduleMutationEngine.cancel(
        current: openSnap(),
        command: CancelScheduleItemCommand(
          dogId: 'dog-1',
          scheduleId: 's1',
          cancelReason: 'Duplicado',
          operationId: 'cancel-1',
        ),
        trusted: trusted,
      );

      expect(result.item.lifecycleStatus, ScheduleLifecycleStatus.cancelled);
      expect(result.item.cancelledAt, serverNow);
      expect(result.item.cancelledBy, actor);
      expect(result.item.cancelReason, 'Duplicado');
      expect(result.snapshot.lastLifecycleOperationId, 'cancel-1');
    });

    test('cancel sem reason é rejeitado no comando', () {
      expect(
        () => CancelScheduleItemCommand(
          dogId: 'dog-1',
          scheduleId: 's1',
          cancelReason: '   ',
          operationId: 'c1',
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('cancel sem operationId é rejeitado no comando', () {
      expect(
        () => CancelScheduleItemCommand(
          dogId: 'dog-1',
          scheduleId: 's1',
          cancelReason: 'x',
          operationId: '  ',
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('terminal completed → open inválido', () {
      final completed = HealthScheduleItemTransitions.transition(
        openSnap().item,
        ScheduleLifecycleStatus.completed,
        completedAt: serverNow,
        completedBy: actor,
      );
      expect(
        HealthScheduleItemTransitions.canTransition(
          completed.lifecycleStatus,
          ScheduleLifecycleStatus.open,
        ),
        isFalse,
      );
    });

    test('completed → cancelled inválido no engine', () {
      final completed = HealthScheduleMutationEngine.complete(
        current: openSnap(),
        command: CompleteScheduleItemCommand(
          dogId: 'dog-1',
          scheduleId: 's1',
        ),
        trusted: trusted,
      );
      expect(
        () => HealthScheduleMutationEngine.cancel(
          current: completed.snapshot,
          command: CancelScheduleItemCommand(
            dogId: 'dog-1',
            scheduleId: 's1',
            cancelReason: 'tarde',
            operationId: 'cancel-late',
          ),
          trusted: trusted,
        ),
        throwsA(isA<HealthScheduleMutationInvalidTransition>()),
      );
    });

    test('cancelled → completed inválido no engine', () {
      final cancelled = HealthScheduleMutationEngine.cancel(
        current: openSnap(),
        command: CancelScheduleItemCommand(
          dogId: 'dog-1',
          scheduleId: 's1',
          cancelReason: 'x',
          operationId: 'cancel-1',
        ),
        trusted: trusted,
      );
      expect(
        () => HealthScheduleMutationEngine.complete(
          current: cancelled.snapshot,
          command: CompleteScheduleItemCommand(
            dogId: 'dog-1',
            scheduleId: 's1',
          ),
          trusted: trusted,
        ),
        throwsA(isA<HealthScheduleMutationInvalidTransition>()),
      );
    });

    test('overdue visual continua open → completed', () {
      final overdueOpen = openSnap(
        scheduledFor: serverNow.subtract(const Duration(days: 3)),
      );
      final result = HealthScheduleMutationEngine.complete(
        current: overdueOpen,
        command: CompleteScheduleItemCommand(
          dogId: 'dog-1',
          scheduleId: 's1',
        ),
        trusted: trusted,
      );
      expect(result.item.lifecycleStatus, ScheduleLifecycleStatus.completed);
    });
  });

  group('idempotência complete', () {
    test('complete no-op não troca completed_at nem completed_by', () {
      final first = HealthScheduleMutationEngine.complete(
        current: openSnap(),
        command: CompleteScheduleItemCommand(
          dogId: 'dog-1',
          scheduleId: 's1',
          operationId: 'comp-1',
        ),
        trusted: trusted,
      );
      final originalAt = first.item.completedAt;
      final originalBy = first.item.completedBy;

      final second = HealthScheduleMutationEngine.complete(
        current: first.snapshot,
        command: CompleteScheduleItemCommand(
          dogId: 'dog-1',
          scheduleId: 's1',
          operationId: 'comp-retry',
        ),
        trusted: trustedB, // outro ator/tempo — não deve sobrescrever
      );

      expect(second.wasNoOp, isTrue);
      expect(second.item.completedAt, originalAt);
      expect(second.item.completedBy, originalBy);
      expect(second.item.completedBy!.uid, 'uid-1');
      expect(identical(second.item, first.item) || second.item.completedAt == first.item.completedAt, isTrue);
    });
  });

  group('idempotência cancel', () {
    test('mesma operationId após cancelled → no-op preserva reason/at/by', () {
      final first = HealthScheduleMutationEngine.cancel(
        current: openSnap(),
        command: CancelScheduleItemCommand(
          dogId: 'dog-1',
          scheduleId: 's1',
          cancelReason: 'original',
          operationId: 'cancel-op-1',
        ),
        trusted: trusted,
      );
      final second = HealthScheduleMutationEngine.cancel(
        current: first.snapshot,
        command: CancelScheduleItemCommand(
          dogId: 'dog-1',
          scheduleId: 's1',
          cancelReason: 'retry-reason-different',
          operationId: 'cancel-op-1',
        ),
        trusted: trustedB,
      );
      expect(second.wasNoOp, isTrue);
      expect(second.item.cancelReason, 'original');
      expect(second.item.cancelledAt, first.item.cancelledAt);
      expect(second.item.cancelledBy, first.item.cancelledBy);
    });

    test('outra operationId após cancelled → alreadyCancelled (não silencia reason)', () {
      final first = HealthScheduleMutationEngine.cancel(
        current: openSnap(),
        command: CancelScheduleItemCommand(
          dogId: 'dog-1',
          scheduleId: 's1',
          cancelReason: 'original',
          operationId: 'cancel-op-1',
        ),
        trusted: trusted,
      );
      expect(
        () => HealthScheduleMutationEngine.cancel(
          current: first.snapshot,
          command: CancelScheduleItemCommand(
            dogId: 'dog-1',
            scheduleId: 's1',
            cancelReason: 'outra-razão',
            operationId: 'cancel-op-2',
          ),
          trusted: trustedB,
        ),
        throwsA(
          isA<HealthScheduleMutationAlreadyCancelled>().having(
            (e) => e.asSuccess,
            'asSuccess',
            isFalse,
          ),
        ),
      );
      // Estado original intacto se chamador não aplicar o throw.
      expect(first.item.cancelReason, 'original');
    });
  });

  group('create manual + idempotency key', () {
    test('create sem operationId é rejeitado no comando', () {
      expect(
        () => CreateManualScheduleItemCommand(
          dogId: 'dog-1',
          scheduleType: ScheduleType.weighing,
          title: 'Pesagem',
          scheduledFor: serverNow.add(const Duration(days: 1)),
          timezone: 'America/Sao_Paulo',
          operationId: '  ',
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('create força manual/open; ator do trusted', () {
      final r = HealthScheduleMutationEngine.createManual(
        command: CreateManualScheduleItemCommand(
          dogId: 'dog-1',
          scheduleType: ScheduleType.weighing,
          title: 'Pesagem mensal',
          scheduledFor: serverNow.add(const Duration(days: 2)),
          timezone: 'America/Sao_Paulo',
          operationId: 'create-op-1',
          notes: 'rotina',
        ),
        trusted: trusted,
        resolvedId: 'new-1',
      );
      expect(r.item.sourceType, ScheduleSourceType.manual);
      expect(r.item.lifecycleStatus, ScheduleLifecycleStatus.open);
      expect(r.item.recordedBy, actor);
      expect(r.snapshot.createOperationId, 'create-op-1');
      expect(r.wasNoOp, isFalse);
    });

    test('retry create com mesma operationId → no-op sem segundo item', () {
      final first = HealthScheduleMutationEngine.createManual(
        command: CreateManualScheduleItemCommand(
          dogId: 'dog-1',
          scheduleType: ScheduleType.bath,
          title: 'Banho',
          scheduledFor: serverNow.add(const Duration(hours: 3)),
          timezone: 'America/Sao_Paulo',
          operationId: 'create-key-9',
        ),
        trusted: trusted,
        resolvedId: 'doc-9',
      );
      final retry = HealthScheduleMutationEngine.createManual(
        command: CreateManualScheduleItemCommand(
          dogId: 'dog-1',
          scheduleType: ScheduleType.bath,
          title: 'Banho outro título no retry',
          scheduledFor: serverNow.add(const Duration(hours: 5)),
          timezone: 'America/Sao_Paulo',
          operationId: 'create-key-9',
        ),
        trusted: trustedB,
        resolvedId: 'doc-OTHER',
        existingByCreateOperationId: first.snapshot,
      );
      expect(retry.wasNoOp, isTrue);
      expect(retry.item.id, 'doc-9');
      expect(retry.item.title, 'Banho');
      expect(retry.item.recordedBy.uid, 'uid-1');
    });
  });

  group('concorrência updateOpen + revision', () {
    test('update com revision atual → permitido e avança revision', () {
      final base = openSnap(revision: HealthScheduleRevision.numeric(3));
      final r = HealthScheduleMutationEngine.updateOpen(
        current: base,
        command: UpdateOpenScheduleItemCommand(
          dogId: 'dog-1',
          scheduleId: 's1',
          expectedRevision: HealthScheduleRevision.numeric(3),
          operationId: 'upd-1',
          title: 'V10 reforço',
        ),
        trusted: trusted,
      );
      expect(r.wasNoOp, isFalse);
      expect(r.item.title, 'V10 reforço');
      expect(r.snapshot.revision, HealthScheduleRevision.numeric(4));
      expect(r.snapshot.lastUpdateOperationId, 'upd-1');
    });

    test('update com revision stale → conflict', () {
      final base = openSnap(revision: HealthScheduleRevision.numeric(5));
      expect(
        () => HealthScheduleMutationEngine.updateOpen(
          current: base,
          command: UpdateOpenScheduleItemCommand(
            dogId: 'dog-1',
            scheduleId: 's1',
            expectedRevision: HealthScheduleRevision.numeric(4),
            operationId: 'upd-stale',
            notes: 'x',
          ),
          trusted: trusted,
        ),
        throwsA(isA<HealthScheduleMutationConflict>()),
      );
    });

    test(
      'duas edições concorrentes open: segunda com revision V1 → conflict',
      () {
        final v1 = openSnap(revision: HealthScheduleRevision.numeric(1));
        final afterA = HealthScheduleMutationEngine.updateOpen(
          current: v1,
          command: UpdateOpenScheduleItemCommand(
            dogId: 'dog-1',
            scheduleId: 's1',
            expectedRevision: HealthScheduleRevision.numeric(1),
            operationId: 'upd-A',
            scheduledFor: serverNow.add(const Duration(days: 5)),
          ),
          trusted: trusted,
        );
        expect(afterA.snapshot.revision, HealthScheduleRevision.numeric(2));
        expect(afterA.item.scheduledFor.day, serverNow.add(const Duration(days: 5)).day);

        // B ainda usa revision 1 e lifecycle open — deve falhar.
        expect(afterA.item.lifecycleStatus, ScheduleLifecycleStatus.open);
        expect(
          () => HealthScheduleMutationEngine.updateOpen(
            current: afterA.snapshot,
            command: UpdateOpenScheduleItemCommand(
              dogId: 'dog-1',
              scheduleId: 's1',
              expectedRevision: HealthScheduleRevision.numeric(1),
              operationId: 'upd-B',
              notes: 'notas de B',
            ),
            trusted: trustedB,
          ),
          throwsA(isA<HealthScheduleMutationConflict>()),
        );
        // A permaneceu sem notes de B.
        expect(afterA.item.notes, isNull);
      },
    );

    test('lifecycle open sozinho não autoriza update stale', () {
      final base = openSnap(revision: HealthScheduleRevision.numeric(10));
      expect(base.item.lifecycleStatus, ScheduleLifecycleStatus.open);
      expect(
        () => HealthScheduleMutationEngine.updateOpen(
          current: base,
          command: UpdateOpenScheduleItemCommand(
            dogId: 'dog-1',
            scheduleId: 's1',
            expectedRevision: HealthScheduleRevision.numeric(0),
            expectedLifecycleStatus: ScheduleLifecycleStatus.open,
            operationId: 'upd-x',
            title: 'hack',
          ),
          trusted: trusted,
        ),
        throwsA(isA<HealthScheduleMutationConflict>()),
      );
    });

    test('retry update mesma operationId → no-op', () {
      final base = openSnap(revision: HealthScheduleRevision.numeric(0));
      final first = HealthScheduleMutationEngine.updateOpen(
        current: base,
        command: UpdateOpenScheduleItemCommand(
          dogId: 'dog-1',
          scheduleId: 's1',
          expectedRevision: HealthScheduleRevision.numeric(0),
          operationId: 'upd-retry',
          notes: 'n1',
        ),
        trusted: trusted,
      );
      final retry = HealthScheduleMutationEngine.updateOpen(
        current: first.snapshot,
        command: UpdateOpenScheduleItemCommand(
          dogId: 'dog-1',
          scheduleId: 's1',
          expectedRevision: HealthScheduleRevision.numeric(0), // stale ok no retry
          operationId: 'upd-retry',
          notes: 'n2',
        ),
        trusted: trustedB,
      );
      expect(retry.wasNoOp, isTrue);
      expect(retry.item.notes, 'n1');
      expect(retry.snapshot.revision, first.snapshot.revision);
    });

    test('source_type e schedule_type imutáveis no update', () {
      final base = openSnap();
      final r = HealthScheduleMutationEngine.updateOpen(
        current: base,
        command: UpdateOpenScheduleItemCommand(
          dogId: 'dog-1',
          scheduleId: 's1',
          expectedRevision: base.revision,
          operationId: 'upd-1',
          title: 'Novo',
        ),
        trusted: trusted,
      );
      expect(r.item.scheduleType, base.item.scheduleType);
      expect(r.item.sourceType, base.item.sourceType);
      expect(r.item.createdAt, base.item.createdAt);
      expect(r.item.recordedBy, base.item.recordedBy);
    });

    test('item automático não permite updateOpen', () {
      final auto = openSnap(source: ScheduleSourceType.treatmentProtocol);
      expect(
        () => HealthScheduleMutationEngine.updateOpen(
          current: auto,
          command: UpdateOpenScheduleItemCommand(
            dogId: 'dog-1',
            scheduleId: 's1',
            expectedRevision: auto.revision,
            operationId: 'upd-auto',
            title: 'hack',
          ),
          trusted: trusted,
        ),
        throwsA(isA<HealthScheduleMutationPermissionDenied>()),
      );
    });

    test('updateOpen sem operationId rejeitado', () {
      expect(
        () => UpdateOpenScheduleItemCommand(
          dogId: 'dog-1',
          scheduleId: 's1',
          expectedRevision: HealthScheduleRevision.numeric(0),
          operationId: '',
          notes: 'x',
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('hard delete proibido pela policy', () {
      expect(HealthScheduleMutationPolicy.allowsHardDelete(), isFalse);
    });
  });

  group('concorrência lifecycle expected', () {
    test('expected cancelled mas item open → conflict em complete', () {
      expect(
        () => HealthScheduleMutationEngine.complete(
          current: openSnap(),
          command: CompleteScheduleItemCommand(
            dogId: 'dog-1',
            scheduleId: 's1',
            expectedLifecycleStatus: ScheduleLifecycleStatus.cancelled,
          ),
          trusted: trusted,
        ),
        throwsA(isA<HealthScheduleMutationConflict>()),
      );
    });

    test('A conclui; B tenta cancel com expected open → invalidTransition', () {
      final afterA = HealthScheduleMutationEngine.complete(
        current: openSnap(),
        command: CompleteScheduleItemCommand(
          dogId: 'dog-1',
          scheduleId: 's1',
        ),
        trusted: trusted,
      );
      expect(
        () => HealthScheduleMutationEngine.cancel(
          current: afterA.snapshot,
          command: CancelScheduleItemCommand(
            dogId: 'dog-1',
            scheduleId: 's1',
            cancelReason: 'B stale',
            operationId: 'cancel-b',
            expectedLifecycleStatus: ScheduleLifecycleStatus.open,
          ),
          trusted: trustedB,
        ),
        throwsA(isA<HealthScheduleMutationInvalidTransition>()),
      );
    });
  });

  group('gateway fail-closed e double-submit', () {
    test('FailClosed recusa writes', () async {
      const gw = FailClosedHealthScheduleMutationGateway();
      final create = await gw.createManual(
        CreateManualScheduleItemCommand(
          dogId: 'dog-1',
          scheduleType: ScheduleType.general,
          title: 'x',
          scheduledFor: serverNow.add(const Duration(days: 1)),
          timezone: 'America/Sao_Paulo',
          operationId: 'c1',
        ),
      );
      expect(
        (create as HealthScheduleMutationErrorResult).failure,
        isA<HealthScheduleMutationWritesNotEnabled>(),
      );
    });

    test('CommandSession bloqueia double-submit', () async {
      final session = HealthScheduleCommandSession();
      var runs = 0;
      final first = session.runExclusive(() async {
        runs++;
        await Future<void>.delayed(const Duration(milliseconds: 30));
        return 'ok';
      });
      final second = await session.runExclusive(() async {
        runs++;
        return 'blocked';
      });
      expect(second, isNull);
      expect(await first, 'ok');
      expect(runs, 1);
    });
  });

  group('matriz de transição estática', () {
    test('apenas open→completed e open→cancelled permitidos', () {
      expect(
        HealthScheduleItemTransitions.canTransition(
          ScheduleLifecycleStatus.open,
          ScheduleLifecycleStatus.completed,
        ),
        isTrue,
      );
      expect(
        HealthScheduleItemTransitions.canTransition(
          ScheduleLifecycleStatus.open,
          ScheduleLifecycleStatus.cancelled,
        ),
        isTrue,
      );
      for (final from in ScheduleLifecycleStatus.values) {
        for (final to in ScheduleLifecycleStatus.values) {
          if (from == ScheduleLifecycleStatus.open &&
              (to == ScheduleLifecycleStatus.completed ||
                  to == ScheduleLifecycleStatus.cancelled)) {
            continue;
          }
          if (from == to) continue;
          expect(
            HealthScheduleItemTransitions.canTransition(from, to),
            isFalse,
            reason: '${from.wireName}→${to.wireName}',
          );
        }
      }
    });
  });
}
