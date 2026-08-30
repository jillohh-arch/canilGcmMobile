import 'package:canil_gcm/features/health/data/restriction/firebase_functions_health_restriction_lifecycle_gateway.dart';
import 'package:canil_gcm/features/health/data/restriction/health_restriction_flow_callables.dart';
import 'package:canil_gcm/features/health/domain/health_restriction_flow_errors.dart';
import 'package:canil_gcm/features/health/domain/health_restriction_lifecycle_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/domain/health_v1_value_objects.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Invoker {
  _Invoker(this._responder);

  final Future<Map<String, dynamic>> Function(
    String name,
    Map<String, dynamic> data,
  )
  _responder;

  final List<String> names = <String>[];
  final List<Map<String, dynamic>> payloads = <Map<String, dynamic>>[];

  Future<Map<String, dynamic>> call(
    String name,
    Map<String, dynamic> data,
  ) async {
    names.add(name);
    payloads.add(data);
    return _responder(name, data);
  }
}

_Invoker _ok(Map<String, dynamic> response) =>
    _Invoker((_, _) async => response);

_Invoker _throws(Object error) => _Invoker((_, _) async => throw error);

ProfessionalIdentity _professional({String? specialty}) =>
    ProfessionalIdentity(
      name: 'Dr. Carlos Lima',
      registrationType: ProfessionalRegistrationType.crmv,
      registrationNumber: 'SP-54321',
      clinic: 'Hospital Veterinário Central',
      specialty: specialty,
    );

EndOperationalRestrictionCommand _endCommand({
  String operationId = 'op-end-1',
  ProfessionalIdentity? professional,
}) => EndOperationalRestrictionCommand(
  dogId: 'dog-1',
  restrictionId: 'or_xyz',
  operationId: operationId,
  endReason: 'Reavaliação clínica concluída',
  endProfessional: professional ?? _professional(),
  endSourceDocument: const HealthDocumentRef(healthDocumentId: 'hd_release'),
);

const _cancelCommand = CancelOperationalRestrictionCommand(
  dogId: 'dog-1',
  restrictionId: 'or_xyz',
  operationId: 'op-cancel-1',
  cancelReason: 'Registro criado por engano',
);

Map<String, dynamic> _terminal(String status, {bool wasNoOp = false}) =>
    <String, dynamic>{
      'dog_id': 'dog-1',
      'restriction_id': 'or_xyz',
      'status': status,
      'was_no_op': wasNoOp,
    };

void main() {
  group('END payload', () {
    test('callable e payload exatos, professional em snake_case', () async {
      final invoker = _ok(_terminal('ended'));
      final gateway = FirebaseFunctionsHealthRestrictionLifecycleGateway(
        invoker: invoker.call,
      );

      final outcome = await gateway.end(
        _endCommand(professional: _professional(specialty: 'Ortopedia')),
      );

      expect(outcome, isA<HealthRestrictionTerminalSuccess>());
      expect(
        invoker.names.single,
        HealthRestrictionFlowCallables.restrictionEnd,
      );
      expect(invoker.payloads.single, {
        'dogId': 'dog-1',
        'restrictionId': 'or_xyz',
        'operationId': 'op-end-1',
        'endReason': 'Reavaliação clínica concluída',
        'endProfessional': {
          'name': 'Dr. Carlos Lima',
          'registration_type': 'CRMV',
          'registration_number': 'SP-54321',
          'clinic': 'Hospital Veterinário Central',
          'specialty': 'Ortopedia',
        },
        'endSourceDocument': {'health_document_id': 'hd_release'},
      });
    });

    test('specialty omitida quando ausente', () async {
      final invoker = _ok(_terminal('ended'));
      final gateway = FirebaseFunctionsHealthRestrictionLifecycleGateway(
        invoker: invoker.call,
      );
      await gateway.end(_endCommand());

      final professional =
          invoker.payloads.single['endProfessional'] as Map<String, dynamic>;
      expect(professional.containsKey('specialty'), isFalse);
    });

    test('nenhum campo server-owned nem de cancel é enviado', () async {
      final invoker = _ok(_terminal('ended'));
      final gateway = FirebaseFunctionsHealthRestrictionLifecycleGateway(
        invoker: invoker.call,
      );
      await gateway.end(_endCommand());

      for (final forbidden in [
        'status',
        'actualEnd',
        'actual_end',
        'endedBy',
        'ended_by',
        'schemaVersion',
        'schema_version',
        'recordedBy',
        'recorded_by',
        'revision',
        'expectedRevision',
        'cancelReason',
        'cancel_reason',
        'cancelledAt',
        'cancelled_at',
        'cancelledBy',
        'cancelled_by',
        'cancelProfessional',
        'cancelSourceDocument',
      ]) {
        expect(
          invoker.payloads.single.containsKey(forbidden),
          isFalse,
          reason: forbidden,
        );
      }
    });

    test('todos os tipos de registro profissional viajam corretamente', () async {
      for (final type in ProfessionalRegistrationType.values) {
        final invoker = _ok(_terminal('ended'));
        final gateway = FirebaseFunctionsHealthRestrictionLifecycleGateway(
          invoker: invoker.call,
        );
        await gateway.end(
          EndOperationalRestrictionCommand(
            dogId: 'dog-1',
            restrictionId: 'or_xyz',
            operationId: 'op-1',
            endReason: 'motivo',
            endProfessional: ProfessionalIdentity(
              name: 'Prof',
              registrationType: type,
              registrationNumber: '1',
              clinic: 'C',
            ),
            endSourceDocument: const HealthDocumentRef(
              healthDocumentId: 'hd',
            ),
          ),
        );
        final professional =
            invoker.payloads.single['endProfessional'] as Map<String, dynamic>;
        expect(professional['registration_type'], type.wireName);
      }
    });
  });

  group('CANCEL payload', () {
    test('callable e payload mínimo exatos', () async {
      final invoker = _ok(_terminal('cancelled'));
      final gateway = FirebaseFunctionsHealthRestrictionLifecycleGateway(
        invoker: invoker.call,
      );

      final outcome = await gateway.cancel(_cancelCommand);

      expect(outcome, isA<HealthRestrictionTerminalSuccess>());
      expect(
        invoker.names.single,
        HealthRestrictionFlowCallables.restrictionCancel,
      );
      expect(invoker.payloads.single, {
        'dogId': 'dog-1',
        'restrictionId': 'or_xyz',
        'operationId': 'op-cancel-1',
        'cancelReason': 'Registro criado por engano',
      });
      expect(
        invoker.payloads.single.keys.length,
        4,
        reason: 'CANCEL não carrega mais nada',
      );
    });

    test('zero prova clínica: sem professional e sem documento', () async {
      final invoker = _ok(_terminal('cancelled'));
      final gateway = FirebaseFunctionsHealthRestrictionLifecycleGateway(
        invoker: invoker.call,
      );
      await gateway.cancel(_cancelCommand);

      for (final forbidden in [
        'professional',
        'cancelProfessional',
        'cancel_professional',
        'endProfessional',
        'sourceDocument',
        'cancelSourceDocument',
        'cancel_source_document',
        'endSourceDocument',
        'status',
        'cancelledAt',
        'cancelled_at',
        'cancelledBy',
        'cancelled_by',
        'endReason',
        'end_reason',
        'revision',
        'expectedRevision',
      ]) {
        expect(
          invoker.payloads.single.containsKey(forbidden),
          isFalse,
          reason: forbidden,
        );
      }
    });
  });

  group('parse de resposta terminal', () {
    test('END aceita snake e camel mirror', () async {
      for (final response in <Map<String, dynamic>>[
        _terminal('ended', wasNoOp: true),
        {
          'dogId': 'dog-1',
          'restrictionId': 'or_xyz',
          'status': 'ended',
          'wasNoOp': true,
        },
      ]) {
        final gateway = FirebaseFunctionsHealthRestrictionLifecycleGateway(
          invoker: _ok(response).call,
        );
        final outcome = await gateway.end(_endCommand());
        final result = (outcome as HealthRestrictionTerminalSuccess).result;
        expect(result.status, HealthRestrictionTerminalStatus.ended);
        expect(result.restrictionId, 'or_xyz');
        expect(result.dogId, 'dog-1');
        expect(result.wasNoOp, isTrue);
      }
    });

    test('CANCEL parseia cancelled', () async {
      final gateway = FirebaseFunctionsHealthRestrictionLifecycleGateway(
        invoker: _ok(_terminal('cancelled')).call,
      );
      final outcome = await gateway.cancel(_cancelCommand);
      final result = (outcome as HealthRestrictionTerminalSuccess).result;
      expect(result.status, HealthRestrictionTerminalStatus.cancelled);
      expect(result.wasNoOp, isFalse);
    });

    test('END que responde cancelled falha fechado', () async {
      // Divergência de contrato: relatar encerramento sem que ele tenha
      // ocorrido seria pior que falhar.
      final gateway = FirebaseFunctionsHealthRestrictionLifecycleGateway(
        invoker: _ok(_terminal('cancelled')).call,
      );
      final outcome = await gateway.end(_endCommand());
      expect(
        (outcome as HealthRestrictionTerminalError).failure,
        isA<HealthRestrictionFlowIntegrity>(),
      );
    });

    test('CANCEL que responde ended falha fechado', () async {
      final gateway = FirebaseFunctionsHealthRestrictionLifecycleGateway(
        invoker: _ok(_terminal('ended')).call,
      );
      final outcome = await gateway.cancel(_cancelCommand);
      expect(
        (outcome as HealthRestrictionTerminalError).failure,
        isA<HealthRestrictionFlowIntegrity>(),
      );
    });

    test('status active ou desconhecido falha fechado', () async {
      for (final status in ['active', 'encerrada', 'ENDED', '']) {
        final gateway = FirebaseFunctionsHealthRestrictionLifecycleGateway(
          invoker: _ok(_terminal(status)).call,
        );
        final outcome = await gateway.end(_endCommand());
        expect(
          outcome,
          isA<HealthRestrictionTerminalError>(),
          reason: 'status=$status',
        );
      }
    });

    test('resposta malformada falha fechado', () async {
      final cases = <String, Map<String, dynamic>>{
        'restriction_id vazio': {
          'dog_id': 'dog-1',
          'restriction_id': '   ',
          'status': 'ended',
          'was_no_op': false,
        },
        'status ausente': {
          'dog_id': 'dog-1',
          'restriction_id': 'or_xyz',
          'was_no_op': false,
        },
        'was_no_op ausente': {
          'dog_id': 'dog-1',
          'restriction_id': 'or_xyz',
          'status': 'ended',
        },
        'was_no_op não booleano': {
          'dog_id': 'dog-1',
          'restriction_id': 'or_xyz',
          'status': 'ended',
          'was_no_op': 'true',
        },
        'dog_id ausente': {
          'restriction_id': 'or_xyz',
          'status': 'ended',
          'was_no_op': false,
        },
      };

      for (final entry in cases.entries) {
        final gateway = FirebaseFunctionsHealthRestrictionLifecycleGateway(
          invoker: _ok(entry.value).call,
        );
        final outcome = await gateway.end(_endCommand());
        expect(
          (outcome as HealthRestrictionTerminalError).failure,
          isA<HealthRestrictionFlowIntegrity>(),
          reason: entry.key,
        );
      }
    });
  });

  group('mapeamento de erro', () {
    Future<HealthRestrictionFlowFailure> endWith(Object error) async {
      final gateway = FirebaseFunctionsHealthRestrictionLifecycleGateway(
        invoker: _throws(error).call,
      );
      final outcome = await gateway.end(_endCommand());
      return (outcome as HealthRestrictionTerminalError).failure;
    }

    Future<HealthRestrictionFlowFailure> cancelWith(Object error) async {
      final gateway = FirebaseFunctionsHealthRestrictionLifecycleGateway(
        invoker: _throws(error).call,
      );
      final outcome = await gateway.cancel(_cancelCommand);
      return (outcome as HealthRestrictionTerminalError).failure;
    }

    test('todos os códigos do lifecycle backend', () async {
      final expectations = <String, Matcher>{
        'permission-denied': isA<HealthRestrictionFlowPermissionDenied>(),
        'invalid-argument': isA<HealthRestrictionFlowValidation>(),
        'not-found': isA<HealthRestrictionFlowNotFound>(),
        'conflict': isA<HealthRestrictionFlowConflict>(),
        'idempotency-conflict':
            isA<HealthRestrictionFlowIdempotencyConflict>(),
        'integrity': isA<HealthRestrictionFlowIntegrity>(),
        'unavailable': isA<HealthRestrictionFlowOffline>(),
        'unauthenticated': isA<HealthRestrictionFlowUnauthenticated>(),
        'internal': isA<HealthRestrictionFlowUnexpected>(),
        'codigo-novo-desconhecido': isA<HealthRestrictionFlowUnexpected>(),
      };
      for (final entry in expectations.entries) {
        expect(
          await endWith(
            FirebaseFunctionsException(code: entry.key, message: 'x'),
          ),
          entry.value,
          reason: 'END ${entry.key}',
        );
        expect(
          await cancelWith(
            FirebaseFunctionsException(code: entry.key, message: 'x'),
          ),
          entry.value,
          reason: 'CANCEL ${entry.key}',
        );
      }
    });

    test('conflito terminal preserva erro tipado, nunca sucesso', () async {
      final failure = await endWith(
        FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'Restrição já está em estado terminal (ended)',
          details: const {'code': 'conflict'},
        ),
      );
      expect(failure, isA<HealthRestrictionFlowConflict>());
      expect(
        failure.isRetryable,
        isFalse,
        reason: 'repetir não reabre estado terminal',
      );
    });

    test('etapa correta por comando', () async {
      expect(
        (await endWith(
          FirebaseFunctionsException(code: 'unavailable', message: 'x'),
        )).step,
        HealthRestrictionFlowStep.restrictionEnd,
      );
      expect(
        (await cancelWith(
          FirebaseFunctionsException(code: 'unavailable', message: 'x'),
        )).step,
        HealthRestrictionFlowStep.restrictionCancel,
      );
    });

    test('permission-denied diferencia END de CANCEL sem citar capability', () async {
      final endFailure = await endWith(
        FirebaseFunctionsException(
          code: 'permission-denied',
          message: 'missing health.release_restriction',
        ),
      );
      final cancelFailure = await cancelWith(
        FirebaseFunctionsException(
          code: 'permission-denied',
          message: 'missing health.cancel_restriction',
        ),
      );

      expect(endFailure.message, contains('encerrar'));
      expect(cancelFailure.message, contains('cancelar'));
      expect(endFailure.message, isNot(cancelFailure.message));

      for (final failure in [endFailure, cancelFailure]) {
        expect(failure.message, contains('autorização'));
        expect(failure.message, isNot(contains('health.')));
        expect(failure.message, isNot(contains('_restriction')));
      }
    });

    test('erro não-Firebase vira unexpected', () async {
      expect(
        await endWith(StateError('boom')),
        isA<HealthRestrictionFlowUnexpected>(),
      );
    });
  });

  group('nomes de callable', () {
    test('exatos e congelados', () {
      expect(
        HealthRestrictionFlowCallables.restrictionEnd,
        'healthRestrictionEnd',
      );
      expect(
        HealthRestrictionFlowCallables.restrictionCancel,
        'healthRestrictionCancel',
      );
      expect(HealthRestrictionFlowCallables.region, 'southamerica-east1');
    });
  });
}
