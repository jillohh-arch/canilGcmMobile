import 'package:canil_gcm/features/health/domain/health_restriction_flow_errors.dart';
import 'package:canil_gcm/features/health/domain/health_restriction_lifecycle_gateway.dart';
import 'package:canil_gcm/features/health/presentation/restriction/health_restriction_cancel_controller.dart';
import 'package:flutter_test/flutter_test.dart';

final class _FakeLifecycleGateway implements HealthRestrictionLifecycleGateway {
  HealthRestrictionFlowFailure? failure;
  bool wasNoOp = false;
  int cancelCount = 0;
  int endCount = 0;
  final List<CancelOperationalRestrictionCommand> commands =
      <CancelOperationalRestrictionCommand>[];

  @override
  Future<HealthRestrictionTerminalOutcome> cancel(
    CancelOperationalRestrictionCommand command,
  ) async {
    cancelCount += 1;
    commands.add(command);
    final f = failure;
    if (f != null) return HealthRestrictionTerminalError(f);
    return HealthRestrictionTerminalSuccess(
      HealthRestrictionTerminalResult(
        dogId: command.dogId,
        restrictionId: command.restrictionId,
        status: HealthRestrictionTerminalStatus.cancelled,
        wasNoOp: wasNoOp,
      ),
    );
  }

  @override
  Future<HealthRestrictionTerminalOutcome> end(
    EndOperationalRestrictionCommand command,
  ) async {
    endCount += 1;
    throw StateError('CANCEL controller nunca deve chamar end()');
  }
}

void main() {
  late _FakeLifecycleGateway gateway;
  late HealthRestrictionCancelController controller;

  setUp(() {
    gateway = _FakeLifecycleGateway();
    var seq = 0;
    controller = HealthRestrictionCancelController(
      gateway: gateway,
      operationIdFactory: () => 'cancel-op-${++seq}',
    );
  });

  HealthRestrictionCancelIntent intent({
    String reason = 'Registro criado por engano',
    String restrictionId = 'or_xyz',
  }) => HealthRestrictionCancelIntent(
    dogId: 'dog-1',
    restrictionId: restrictionId,
    cancelReason: reason,
  );

  group('happy path', () {
    test('cancela e expõe resultado terminal', () async {
      final ok = await controller.submit(intent());

      expect(ok, isTrue);
      expect(controller.stage, HealthRestrictionCancelStage.success);
      expect(gateway.cancelCount, 1);
      expect(
        controller.result!.status,
        HealthRestrictionTerminalStatus.cancelled,
      );
      expect(controller.result!.restrictionId, 'or_xyz');
    });

    test('payload carrega razão normalizada', () async {
      await controller.submit(intent(reason: '  Duplicado  '));
      expect(gateway.commands.single.cancelReason, 'Duplicado');
    });

    test('nunca chama end()', () async {
      await controller.submit(intent());
      expect(gateway.endCount, 0);
    });
  });

  group('validação local', () {
    test('razão vazia bloqueia antes da rede', () async {
      for (final reason in ['', '   ', '\t\n']) {
        final fresh = HealthRestrictionCancelController(
          gateway: gateway,
          operationIdFactory: () => 'op',
        );
        final ok = await fresh.submit(intent(reason: reason));
        expect(ok, isFalse, reason: 'reason=[$reason]');
        expect(fresh.failure, isA<HealthRestrictionFlowValidation>());
      }
      expect(gateway.cancelCount, 0, reason: 'nada sai para a rede');
    });
  });

  group('retry e idempotência', () {
    test('mesma intenção preserva operationId', () async {
      gateway.failure = const HealthRestrictionFlowOffline(
        HealthRestrictionFlowStep.restrictionCancel,
      );
      expect(await controller.submit(intent()), isFalse);
      final opId = controller.operationIdForTest;
      expect(opId, isNotNull);

      gateway.failure = null;
      expect(await controller.submit(intent()), isTrue);

      expect(controller.operationIdForTest, opId);
      expect(gateway.commands.map((c) => c.operationId).toSet(), {opId});
    });

    test('resposta perdida: replay devolve mesmo estado terminal', () async {
      gateway.failure = const HealthRestrictionFlowOffline(
        HealthRestrictionFlowStep.restrictionCancel,
      );
      await controller.submit(intent());
      final opId = controller.operationIdForTest;

      // Backend já havia commitado: replay do receipt.
      gateway.failure = null;
      gateway.wasNoOp = true;
      expect(await controller.submit(intent()), isTrue);

      expect(gateway.commands.last.operationId, opId);
      expect(controller.result!.wasNoOp, isTrue);
      expect(
        controller.result!.status,
        HealthRestrictionTerminalStatus.cancelled,
      );
    });

    test('razão alterada gera novo operationId', () async {
      gateway.failure = const HealthRestrictionFlowOffline(
        HealthRestrictionFlowStep.restrictionCancel,
      );
      await controller.submit(intent());
      final first = controller.operationIdForTest;

      gateway.failure = null;
      expect(
        await controller.submit(intent(reason: 'Motivo corrigido')),
        isTrue,
      );
      expect(
        controller.operationIdForTest,
        isNot(first),
        reason: 'payload diferente exige chave nova',
      );
    });

    test('mudança apenas de espaçamento NÃO invalida a chave', () async {
      gateway.failure = const HealthRestrictionFlowOffline(
        HealthRestrictionFlowStep.restrictionCancel,
      );
      await controller.submit(intent(reason: 'Duplicado'));
      final first = controller.operationIdForTest;

      gateway.failure = null;
      await controller.submit(intent(reason: '  Duplicado  '));
      expect(
        controller.operationIdForTest,
        first,
        reason: 'razão normalizada é a mesma intenção',
      );
    });

    test('restrição diferente gera novo operationId', () async {
      gateway.failure = const HealthRestrictionFlowOffline(
        HealthRestrictionFlowStep.restrictionCancel,
      );
      await controller.submit(intent());
      final first = controller.operationIdForTest;

      gateway.failure = null;
      await controller.submit(intent(restrictionId: 'or_outra'));
      expect(controller.operationIdForTest, isNot(first));
    });
  });

  group('erros preservados', () {
    test('conflito terminal permanece erro tipado', () async {
      gateway.failure = const HealthRestrictionFlowConflict(
        HealthRestrictionFlowStep.restrictionCancel,
      );
      expect(await controller.submit(intent()), isFalse);

      expect(controller.failure, isA<HealthRestrictionFlowConflict>());
      expect(controller.stage, HealthRestrictionCancelStage.failure);
      expect(
        controller.result,
        isNull,
        reason: 'conflito nunca vira sucesso ou replay',
      );
    });

    test('permission-denied preservado com etapa correta', () async {
      gateway.failure = const HealthRestrictionFlowPermissionDenied(
        HealthRestrictionFlowStep.restrictionCancel,
      );
      await controller.submit(intent());

      expect(controller.failure, isA<HealthRestrictionFlowPermissionDenied>());
      expect(
        controller.failure!.step,
        HealthRestrictionFlowStep.restrictionCancel,
      );
    });

    test('submit concorrente é bloqueado', () async {
      final a = controller.submit(intent());
      final b = controller.submit(intent());
      final results = await Future.wait([a, b]);

      expect(results.where((r) => r).length, 1);
      expect(gateway.cancelCount, 1);
    });
  });
}
