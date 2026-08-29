import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/core/services/authoritative_time/authoritative_time_gateway.dart';
import 'package:canil_gcm/core/services/authoritative_time/authoritative_time_models.dart';
import 'package:canil_gcm/core/services/authoritative_time/authoritative_time_provider.dart';
import 'package:canil_gcm/features/health/domain/health_weight_mutation_gateway.dart';
import 'package:canil_gcm/features/health/presentation/weight/health_weight_controller.dart';

final class _TimeGateway implements AuthoritativeTimeGateway {
  int calls = 0;

  @override
  Future<AuthoritativeTimeRemoteResponse> fetchAuthoritativeTime() async {
    calls += 1;
    final now = DateTime.utc(2026, 8, 4, 12);
    return AuthoritativeTimeRemoteResponse(
      protocolVersion: 1,
      requestId: '00000000-0000-4000-8000-000000000001',
      requestReceivedAtUtc: now,
      serverSentAtUtc: now,
      maxAge: const Duration(minutes: 15),
    );
  }
}

final class _Gateway implements HealthWeightMutationGateway {
  final calls = <CreateHealthWeightCommand>[];
  Object? next;

  @override
  Future<HealthWeightMutationReceipt> createRecord(
    CreateHealthWeightCommand command,
  ) async {
    calls.add(command);
    final value = next;
    if (value is Completer<HealthWeightMutationReceipt>) return value.future;
    if (value is HealthWeightMutationFailure) throw value;
    return value as HealthWeightMutationReceipt;
  }
}

HealthWeightMutationReceipt receipt({bool wasNoOp = false}) =>
    HealthWeightMutationReceipt(
      dogId: 'dog-1',
      entityId: 'weight-1',
      weightKg: 25,
      revision: 1,
      wasNoOp: wasNoOp,
    );

void main() {
  late _Gateway gateway;
  late int id;
  late int refreshes;
  late _TimeGateway timeGateway;
  late HealthWeightController controller;

  setUp(() {
    gateway = _Gateway()..next = receipt();
    id = 0;
    refreshes = 0;
    timeGateway = _TimeGateway();
    controller = HealthWeightController(
      gateway: gateway,
      authoritativeTimeProvider: AuthoritativeTimeProvider(
        gateway: timeGateway,
      ),
      operationIdFactory: () => 'operation-${++id}',
      onRefreshAfterSuccess: () async => refreshes++,
    );
  });

  test('validates finite positive weight up to 100kg', () async {
    for (final weight in <double>[double.nan, 0, -1, 100.1]) {
      final result = await controller.submit(dogId: 'dog-1', weightKg: weight);
      expect(result, isA<HealthWeightSubmissionFailure>());
    }
    expect(gateway.calls, isEmpty);
  });

  test('blocks double submit and treats replay as success', () async {
    final completer = Completer<HealthWeightMutationReceipt>();
    gateway.next = completer;
    final first = controller.submit(dogId: 'dog-1', weightKg: 25);
    await Future<void>.delayed(Duration.zero);
    expect(
      await controller.submit(dogId: 'dog-1', weightKg: 25),
      isA<HealthWeightSubmissionBlocked>(),
    );
    completer.complete(receipt(wasNoOp: true));
    final result = await first as HealthWeightSubmissionSuccess;
    expect(result.receipt.wasNoOp, isTrue);
    expect(gateway.calls, hasLength(1));
    expect(refreshes, 1);
    expect(controller.activeOperationIdForTest, isNull);
  });

  test(
    'transient retry reuses the complete frozen payload and clock',
    () async {
      gateway.next = const HealthWeightMutationFailure(
        HealthWeightMutationErrorCode.unavailable,
        'temporário',
      );
      expect(
        await controller.submit(
          dogId: 'dog-1',
          weightKg: 25.25,
          context: HealthWeightContext.preOp,
          notes: '  jejum confirmado  ',
        ),
        isA<HealthWeightSubmissionFailure>(),
      );
      final frozen = controller.activeCommandForTest!;
      expect(timeGateway.calls, 1);
      gateway.next = receipt();

      expect(
        await controller.submit(
          dogId: 'dog-1',
          weightKg: 25.25,
          context: HealthWeightContext.preOp,
          notes: 'jejum confirmado',
        ),
        isA<HealthWeightSubmissionSuccess>(),
      );
      final retry = gateway.calls.last;
      expect(retry.operationId, frozen.operationId);
      expect(retry.measuredAt, frozen.measuredAt);
      expect(retry.weightKg, frozen.weightKg);
      expect(retry.context, frozen.context);
      expect(retry.notes, frozen.notes);
      expect(timeGateway.calls, 1);
    },
  );

  test('weight change replaces the pending logical operation', () async {
    gateway.next = const HealthWeightMutationFailure(
      HealthWeightMutationErrorCode.deadlineExceeded,
      'temporário',
    );
    await controller.submit(dogId: 'dog-1', weightKg: 25);
    final firstId = controller.activeOperationIdForTest;
    await controller.submit(dogId: 'dog-1', weightKg: 25.1);
    expect(controller.activeOperationIdForTest, isNot(firstId));
  });

  test('context change replaces the pending logical operation', () async {
    gateway.next = const HealthWeightMutationFailure(
      HealthWeightMutationErrorCode.unavailable,
      'temporário',
    );
    await controller.submit(
      dogId: 'dog-1',
      weightKg: 25,
      context: HealthWeightContext.routine,
    );
    final firstId = controller.activeOperationIdForTest;
    await controller.submit(
      dogId: 'dog-1',
      weightKg: 25,
      context: HealthWeightContext.clinical,
    );
    expect(controller.activeOperationIdForTest, isNot(firstId));
  });

  test('notes change replaces the pending logical operation', () async {
    gateway.next = const HealthWeightMutationFailure(
      HealthWeightMutationErrorCode.unavailable,
      'temporário',
    );
    await controller.submit(dogId: 'dog-1', weightKg: 25, notes: 'antes');
    final firstId = controller.activeOperationIdForTest;
    await controller.submit(dogId: 'dog-1', weightKg: 25, notes: 'depois');
    expect(controller.activeOperationIdForTest, isNot(firstId));
  });

  test('cancel discards frozen payload and operationId', () async {
    gateway.next = const HealthWeightMutationFailure(
      HealthWeightMutationErrorCode.deadlineExceeded,
      'temporário',
    );
    await controller.submit(dogId: 'dog-1', weightKg: 25);
    expect(controller.activeCommandForTest, isNotNull);

    controller.discardOperation();

    expect(controller.activeCommandForTest, isNull);
  });

  test('regular success clears the frozen operation', () async {
    expect(
      await controller.submit(dogId: 'dog-1', weightKg: 25),
      isA<HealthWeightSubmissionSuccess>(),
    );
    expect(controller.activeCommandForTest, isNull);
  });

  test('idempotent replay clears the frozen operation', () async {
    gateway.next = receipt(wasNoOp: true);
    final outcome = await controller.submit(dogId: 'dog-1', weightKg: 25);
    expect((outcome as HealthWeightSubmissionSuccess).receipt.wasNoOp, isTrue);
    expect(controller.activeCommandForTest, isNull);
  });

  test('definitive failure clears pending operation', () async {
    gateway.next = const HealthWeightMutationFailure(
      HealthWeightMutationErrorCode.permissionDenied,
      'sem permissão',
    );
    await controller.submit(dogId: 'dog-1', weightKg: 25);
    expect(controller.activeOperationIdForTest, isNull);
  });

  test('dispose is safe and blocks later submissions', () async {
    controller.dispose();
    expect(
      await controller.submit(dogId: 'dog-1', weightKg: 25),
      isA<HealthWeightSubmissionBlocked>(),
    );
    expect(gateway.calls, isEmpty);
  });
}
