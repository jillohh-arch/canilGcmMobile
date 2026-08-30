import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/shifts/data/firebase_functions_shift_authorization_gateway.dart';
import 'package:canil_gcm/features/shifts/domain/shift_authorization.dart';

/// HEALTH-V1-OP-AUTH — Gate C: tradução da decisão do backend no Mobile.
///
/// O que está sob teste é a fronteira semântica: um bloqueio clínico não pode
/// chegar à UI como problema de conexão, e uma falha de verificação não pode
/// chegar como "sem restrição". Antes desta vertical, ambos apareciam como
/// "Falha ao sincronizar turno".
void main() {
  ShiftAuthorizationCommand command({
    ShiftAuthorizedAction action = ShiftAuthorizedAction.startShift,
    String dogId = 'dog-1',
    List<String> acknowledged = const <String>[],
  }) {
    return ShiftAuthorizationCommand(
      action: action,
      dogId: dogId,
      operationId: 'op-1',
      acknowledgedRestrictionIds: acknowledged,
    );
  }

  FirebaseFunctionsShiftAuthorizationGateway gatewayReturning(
    Map<String, dynamic> response, {
    void Function(Map<String, dynamic> payload)? onCall,
  }) {
    return FirebaseFunctionsShiftAuthorizationGateway(
      invoker: (name, data) async {
        onCall?.call(data);
        return response;
      },
    );
  }

  FirebaseFunctionsShiftAuthorizationGateway gatewayThrowing(
    FirebaseFunctionsException error,
  ) {
    return FirebaseFunctionsShiftAuthorizationGateway(
      invoker: (name, data) async => throw error,
    );
  }

  FirebaseFunctionsException functionsError({
    required String code,
    String? appCode,
    List<Map<String, dynamic>> restrictions = const [],
    List<String> pending = const [],
    String? reasonCode,
  }) {
    return FirebaseFunctionsException(
      code: code,
      message: 'mensagem do servidor',
      details: <String, dynamic>{
        'code': ?appCode,
        if (restrictions.isNotEmpty) 'restrictions': restrictions,
        if (pending.isNotEmpty) 'pendingAcknowledgementIds': pending,
        'reasonCode': ?reasonCode,
      },
    );
  }

  Map<String, dynamic> restrictionJson({
    required String id,
    required String level,
    List<String> activities = const [],
    String? expectedEndIso,
    bool isOverdue = false,
  }) {
    return <String, dynamic>{
      'id': id,
      'level': level,
      'category': 'injury',
      'description': 'Restrição registrada por profissional externo.',
      'activitiesRestricted': activities,
      'expectedEndIso': expectedEndIso,
      'isOverdue': isOverdue,
    };
  }

  group('decisões autorizadas', () {
    test('sem restrição é allowed', () async {
      final gateway = gatewayReturning(<String, dynamic>{
        'ok': true,
        'dogId': 'dog-1',
        'decision': 'allowed',
        'restrictions': <Map<String, dynamic>>[],
        'acknowledgementRecorded': false,
        'shiftId': 'shift-1',
        'wasNoOp': false,
      });

      final result = await gateway.execute(command());

      expect(result.outcome, ShiftAuthorizationOutcome.allowed);
      expect(result.shiftId, 'shift-1');
      expect(result.restrictions, isEmpty);
      expect(result.wasNoOp, isFalse);
    });

    test('attention ativa é allowedWithNotice, não bloqueio', () async {
      final gateway = gatewayReturning(<String, dynamic>{
        'dogId': 'dog-1',
        'decision': 'allowed',
        'restrictions': [restrictionJson(id: 'ra-1', level: 'attention')],
        'acknowledgementRecorded': false,
        'shiftId': 'shift-1',
        'wasNoOp': false,
      });

      final result = await gateway.execute(command());

      expect(result.outcome, ShiftAuthorizationOutcome.allowedWithNotice);
      expect(result.noticeRestrictions, hasLength(1));
      expect(result.restrictions.single.level, ShiftRestrictionLevel.attention);
    });

    test('partial com aceite é allowedWithRestrictions e marca ciência', () async {
      final gateway = gatewayReturning(<String, dynamic>{
        'dogId': 'dog-1',
        'decision': 'allowed_with_restrictions',
        'restrictions': [
          restrictionJson(
            id: 'rp-1',
            level: 'partial',
            activities: ['busca', 'guarda'],
          ),
        ],
        'acknowledgementRecorded': true,
        'shiftId': 'shift-1',
        'wasNoOp': false,
      });

      final result = await gateway.execute(
        command(acknowledged: ['rp-1']),
      );

      expect(
        result.outcome,
        ShiftAuthorizationOutcome.allowedWithRestrictions,
      );
      expect(result.acknowledgementRecorded, isTrue);
      expect(
        result.restrictions.single.activitiesRestricted,
        ['busca', 'guarda'],
      );
    });

    test('decisão desconhecida não é presumida benigna', () async {
      final gateway = gatewayReturning(<String, dynamic>{
        'dogId': 'dog-1',
        'decision': 'allowed_probably',
        'restrictions': <Map<String, dynamic>>[],
      });

      await expectLater(
        gateway.execute(command()),
        throwsA(
          isA<ShiftAuthorizationFailure>().having(
            (failure) => failure.kind,
            'kind',
            ShiftAuthorizationFailureKind.internal,
          ),
        ),
      );
    });
  });

  group('negativas — natureza preservada', () {
    test('absolute vira bloqueio clínico, não erro de conexão', () async {
      final gateway = gatewayThrowing(
        functionsError(
          code: 'failed-precondition',
          appCode: 'absolute_restriction_active',
          restrictions: [restrictionJson(id: 'r1', level: 'absolute')],
        ),
      );

      try {
        await gateway.execute(command());
        fail('deveria ter lançado');
      } on ShiftAuthorizationFailure catch (failure) {
        expect(
          failure.kind,
          ShiftAuthorizationFailureKind.absoluteRestriction,
        );
        // A UI usa isso para NÃO oferecer "continuar mesmo assim".
        expect(failure.isClinicalBlock, isTrue);
        expect(failure.restrictions, hasLength(1));
        expect(failure.message, contains('restrição operacional absoluta'));
        // Jamais mensagem de conectividade para bloqueio clínico.
        expect(failure.message.toLowerCase(), isNot(contains('conexão')));
      }
    });

    test('partial exige ciência e expõe os ids pendentes', () async {
      final gateway = gatewayThrowing(
        functionsError(
          code: 'failed-precondition',
          appCode: 'partial_acknowledgement_required',
          restrictions: [
            restrictionJson(id: 'rp-1', level: 'partial', activities: ['busca']),
          ],
          pending: ['rp-1'],
        ),
      );

      try {
        await gateway.execute(command());
        fail('deveria ter lançado');
      } on ShiftAuthorizationFailure catch (failure) {
        expect(
          failure.kind,
          ShiftAuthorizationFailureKind.acknowledgementRequired,
        );
        // Não é bloqueio definitivo: pode prosseguir com ciência.
        expect(failure.isClinicalBlock, isFalse);
        expect(failure.pendingAcknowledgementIds, ['rp-1']);
        expect(failure.partialRestrictions, hasLength(1));
      }
    });

    test(
      'restrictions_unavailable é fail-closed e distinto de rede',
      () async {
        final gateway = gatewayThrowing(
          functionsError(
            code: 'unavailable',
            appCode: 'restrictions_unavailable',
            reasonCode: 'permission_denied',
          ),
        );

        try {
          await gateway.execute(command());
          fail('deveria ter lançado');
        } on ShiftAuthorizationFailure catch (failure) {
          expect(
            failure.kind,
            ShiftAuthorizationFailureKind.restrictionsUnavailable,
          );
          // NÃO é rede, e NÃO é "sem restrição".
          expect(
            failure.kind,
            isNot(ShiftAuthorizationFailureKind.network),
          );
          expect(failure.isClinicalBlock, isFalse);
          expect(failure.reasonCode, 'permission_denied');
          expect(failure.message, contains('não foi realizada'));
        }
      },
    );

    test('unavailable SEM código de aplicação é falha de rede', () async {
      // Indisponibilidade de serviço é legitimamente conectividade.
      final gateway = gatewayThrowing(
        FirebaseFunctionsException(code: 'unavailable', message: 'offline'),
      );

      try {
        await gateway.execute(command());
        fail('deveria ter lançado');
      } on ShiftAuthorizationFailure catch (failure) {
        expect(failure.kind, ShiftAuthorizationFailureKind.network);
        expect(failure.message.toLowerCase(), contains('conexão'));
      }
    });

    test('atividade restrita também é bloqueio clínico', () async {
      final gateway = gatewayThrowing(
        functionsError(
          code: 'failed-precondition',
          appCode: 'activity_restricted',
          restrictions: [
            restrictionJson(id: 'rp-1', level: 'partial', activities: ['busca']),
          ],
        ),
      );

      try {
        await gateway.execute(command());
        fail('deveria ter lançado');
      } on ShiftAuthorizationFailure catch (failure) {
        expect(
          failure.kind,
          ShiftAuthorizationFailureKind.activityRestricted,
        );
        expect(failure.isClinicalBlock, isTrue);
      }
    });

    test('unauthenticated e permission-denied são distinguidos', () async {
      final unauth = gatewayThrowing(
        FirebaseFunctionsException(code: 'unauthenticated', message: 'no auth'),
      );
      await expectLater(
        unauth.execute(command()),
        throwsA(
          isA<ShiftAuthorizationFailure>().having(
            (f) => f.kind,
            'kind',
            ShiftAuthorizationFailureKind.unauthenticated,
          ),
        ),
      );

      final denied = gatewayThrowing(
        FirebaseFunctionsException(code: 'permission-denied', message: 'no'),
      );
      await expectLater(
        denied.execute(command()),
        throwsA(
          isA<ShiftAuthorizationFailure>().having(
            (f) => f.kind,
            'kind',
            ShiftAuthorizationFailureKind.permissionDenied,
          ),
        ),
      );
    });

    test('idempotency_conflict é reportado como conflito', () async {
      final gateway = gatewayThrowing(
        functionsError(
          code: 'failed-precondition',
          appCode: 'idempotency_conflict',
        ),
      );
      await expectLater(
        gateway.execute(command()),
        throwsA(
          isA<ShiftAuthorizationFailure>().having(
            (f) => f.kind,
            'kind',
            ShiftAuthorizationFailureKind.idempotencyConflict,
          ),
        ),
      );
    });
  });

  group('payload enviado ao backend', () {
    test('o cliente não envia decisão clínica alguma', () async {
      Map<String, dynamic>? captured;
      final gateway = gatewayReturning(
        <String, dynamic>{
          'dogId': 'dog-1',
          'decision': 'allowed',
          'restrictions': <Map<String, dynamic>>[],
        },
        onCall: (payload) => captured = payload,
      );

      await gateway.execute(command());

      expect(captured, isNotNull);
      // A-05: nenhum campo capaz de influenciar a decisão clínica.
      for (final forbidden in [
        'restrictionStatus',
        'readinessStatus',
        'override',
        'readiness_status',
        'health_summary',
      ]) {
        expect(
          captured!.containsKey(forbidden),
          isFalse,
          reason: 'payload não pode conter $forbidden',
        );
      }
      expect(captured!['action'], 'start_shift');
      expect(captured!['dogId'], 'dog-1');
      expect(captured!['operationId'], 'op-1');
    });

    test('reenvio com ciência preserva o mesmo operationId', () async {
      final original = command();
      final retry = original.acknowledging(['rp-1']);

      // Mesmo operationId => o backend trata como a MESMA operação e o aceite
      // não abre um segundo turno.
      expect(retry.operationId, original.operationId);
      expect(retry.acknowledgedRestrictionIds, ['rp-1']);
      expect(retry.action, original.action);
      expect(retry.dogId, original.dogId);
      expect(
        retry.toPayload()['acknowledgedRestrictionIds'],
        ['rp-1'],
      );
    });

    test('viatura é serializada quando presente', () async {
      Map<String, dynamic>? captured;
      final gateway = gatewayReturning(
        <String, dynamic>{
          'dogId': 'dog-1',
          'decision': 'allowed',
          'restrictions': <Map<String, dynamic>>[],
        },
        onCall: (payload) => captured = payload,
      );

      await gateway.execute(
        ShiftAuthorizationCommand(
          action: ShiftAuthorizedAction.assumeVehicle,
          dogId: 'dog-1',
          operationId: 'op-av',
          role: 'k9',
          vehicle: const ShiftAuthorizationVehicle(
            id: 'VTR-01',
            label: 'VTR 01',
            crewSize: 3,
          ),
        ),
      );

      final vehicle = captured!['vehicle'] as Map<String, dynamic>;
      expect(vehicle['id'], 'VTR-01');
      expect(vehicle['crewSize'], 3);
      expect(captured!['role'], 'k9');
      expect(captured!['action'], 'assume_vehicle');
    });
  });

  group('parsing defensivo de restrição', () {
    test('nível desconhecido não é rebaixado para attention', () {
      final parsed = ShiftRestrictionInfo.tryParse(
        restrictionJson(id: 'r1', level: 'quarentena_total'),
      );
      expect(parsed, isNotNull);
      // Desconhecido permanece desconhecido — não vira um nível benigno.
      expect(parsed!.level, isNull);
    });

    test('restrição sem id é descartada', () {
      expect(
        ShiftRestrictionInfo.tryParse(<String, dynamic>{'level': 'absolute'}),
        isNull,
      );
    });

    test('expected_end vencido é sinalizado sem encerrar a restrição', () {
      final parsed = ShiftRestrictionInfo.tryParse(
        restrictionJson(
          id: 'r1',
          level: 'absolute',
          expectedEndIso: '2026-01-01T00:00:00.000Z',
          isOverdue: true,
        ),
      );
      expect(parsed!.isOverdue, isTrue);
      expect(parsed.level, ShiftRestrictionLevel.absolute);
      expect(parsed.expectedEnd, DateTime.utc(2026, 1, 1));
    });
  });
}
