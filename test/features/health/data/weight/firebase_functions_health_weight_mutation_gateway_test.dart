import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/data/weight/firebase_functions_health_weight_mutation_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_weight_mutation_gateway.dart';

void main() {
  test('uses regional callable and exact nested canonical payload', () async {
    String? name;
    Map<String, dynamic>? request;
    final gateway = FirebaseFunctionsHealthWeightMutationGateway(
      invoker: (callable, data) async {
        name = callable;
        request = data;
        return {
          'dogId': 'dog-1',
          'entityId': 'weight-1',
          'weightKg': 26.4,
          'revision': 1,
          'wasNoOp': false,
        };
      },
    );

    final receipt = await gateway.createRecord(
      CreateHealthWeightCommand(
        dogId: 'dog-1',
        operationId: 'operation-1',
        weightKg: 26.4,
        measuredAt: DateTime.parse('2026-08-04T12:30:00-03:00'),
        context: HealthWeightContext.clinical,
        notes: '  retorno  ',
      ),
    );

    expect(HealthWeightCallableContract.region, 'southamerica-east1');
    expect(name, 'healthWeightCreateRecord');
    expect(request, {
      'dogId': 'dog-1',
      'operationId': 'operation-1',
      'payload': {
        'weightKg': 26.4,
        'measuredAt': '2026-08-04T15:30:00.000Z',
        'context': 'clinical',
        'notes': 'retorno',
      },
    });
    expect(receipt.wasNoOp, isFalse);
  });

  test('accepts an idempotent replay receipt', () async {
    final gateway = FirebaseFunctionsHealthWeightMutationGateway(
      invoker: (_, _) async => {
        'dogId': 'dog-1',
        'entityId': 'weight-1',
        'weightKg': 26.4,
        'revision': 1,
        'wasNoOp': true,
      },
    );
    final receipt = await gateway.createRecord(
      CreateHealthWeightCommand(
        dogId: 'dog-1',
        operationId: 'operation-1',
        weightKg: 26.4,
        measuredAt: DateTime.utc(2026, 8, 4),
      ),
    );
    expect(receipt.wasNoOp, isTrue);
  });

  test('omits blank optional fields and rejects malformed response', () async {
    Map<String, dynamic>? request;
    final gateway = FirebaseFunctionsHealthWeightMutationGateway(
      invoker: (_, data) async {
        request = data;
        return {'unexpected': true};
      },
    );
    await expectLater(
      gateway.createRecord(
        CreateHealthWeightCommand(
          dogId: 'dog-1',
          operationId: 'operation-1',
          weightKg: 20,
          measuredAt: DateTime.utc(2026, 8, 4),
          notes: '   ',
        ),
      ),
      throwsA(
        isA<HealthWeightMutationFailure>().having(
          (error) => error.code,
          'code',
          HealthWeightMutationErrorCode.malformedResponse,
        ),
      ),
    );
    expect(request!['payload'], isNot(contains('notes')));
    expect(request!['payload'], isNot(contains('context')));
  });

  test('maps permission and transient callable errors safely', () {
    final denied = mapHealthWeightFunctionsError(
      FirebaseFunctionsException(code: 'permission-denied', message: 'raw'),
    );
    expect(denied.code, HealthWeightMutationErrorCode.permissionDenied);
    expect(denied.message, contains('health.record_routine'));
    expect(denied.message, isNot(contains('raw')));

    for (final code in ['unavailable', 'deadline-exceeded']) {
      expect(
        mapHealthWeightFunctionsError(
          FirebaseFunctionsException(code: code, message: 'raw'),
        ).isTransient,
        isTrue,
      );
    }
  });

  test('maps every required Functions error code', () {
    const expected = {
      'unauthenticated': HealthWeightMutationErrorCode.unauthenticated,
      'permission-denied': HealthWeightMutationErrorCode.permissionDenied,
      'invalid-argument': HealthWeightMutationErrorCode.invalidArgument,
      'not-found': HealthWeightMutationErrorCode.notFound,
      'failed-precondition': HealthWeightMutationErrorCode.failedPrecondition,
      'internal': HealthWeightMutationErrorCode.internal,
      'unavailable': HealthWeightMutationErrorCode.unavailable,
      'deadline-exceeded': HealthWeightMutationErrorCode.deadlineExceeded,
    };
    for (final entry in expected.entries) {
      final failure = mapHealthWeightFunctionsError(
        FirebaseFunctionsException(code: entry.key, message: 'raw detail'),
      );
      expect(failure.code, entry.value);
      expect(failure.message, isNot(contains('raw detail')));
    }
  });
}
