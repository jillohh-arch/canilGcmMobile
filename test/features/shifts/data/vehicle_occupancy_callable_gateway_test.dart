import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:canil_gcm/features/shifts/data/vehicle_occupancy_callable_gateway.dart';
import 'package:canil_gcm/features/shifts/domain/shift_authorization.dart';

void main() {
  group('VehicleOccupancyCallableGateway', () {
    test('selfRegularizePriorOccupancy envia payload correto e deserializa resposta de sucesso', () async {
      late String calledFunction;
      late Map<String, dynamic> calledData;

      final gateway = VehicleOccupancyCallableGateway(
        invoker: (fn, data) async {
          calledFunction = fn;
          calledData = data;
          return {
            'status': 'SUCCESS',
            'operationId': 'op-1234',
            'vehicleId': 'vh-01',
            'predecessorSessionId': 'sess-100',
            'predecessorGeneration': 2,
            'successorSessionId': 'sess-101',
            'successorGeneration': 3,
            'effectiveCrewId': 'crew-alpha',
            'effectiveDogId': 'dog-ares',
            'transitionedAt': '2026-11-04T00:00:00.000Z',
            'receiptId': 'rcpt-999',
            'f20Outcome': 'ALLOWED',
          };
        },
      );

      final req = SelfRegularizePriorOccupancyRequestDto(
        operationId: 'op-1234',
        vehicleId: 'vh-01',
        expectedSessionId: 'sess-100',
        expectedGeneration: 2,
        incomingCrewId: 'crew-alpha',
        f10ScheduleSnapshotId: 'snap-456',
        k9AssociationIntent: 'K9_ASSOCIATION_REQUESTED',
        dogId: 'dog-ares',
        inspectionEvidence: const VehicleInspectionEvidenceDto(
          checklistConfirmed: true,
          physicalKeysInHand: true,
          vehicleOdometerKm: 12500,
          checklistRef: 'chk-1',
          notes: 'Tudo ok',
        ),
      );

      final response = await gateway.selfRegularizePriorOccupancy(req);

      expect(calledFunction, VehicleOccupancyCallableGateway.fnSelfRegularize);
      expect(calledData['operationId'], 'op-1234');
      expect(calledData['vehicleId'], 'vh-01');
      expect(calledData['expectedSessionId'], 'sess-100');
      expect(calledData['expectedGeneration'], 2);
      expect(calledData['incomingCrewId'], 'crew-alpha');
      expect(calledData['k9AssociationIntent'], 'K9_ASSOCIATION_REQUESTED');
      expect(calledData['dogId'], 'dog-ares');

      expect(response.status, 'SUCCESS');
      expect(response.operationId, 'op-1234');
      expect(response.vehicleId, 'vh-01');
      expect(response.predecessorSessionId, 'sess-100');
      expect(response.predecessorGeneration, 2);
      expect(response.successorSessionId, 'sess-101');
      expect(response.successorGeneration, 3);
      expect(response.effectiveCrewId, 'crew-alpha');
      expect(response.effectiveDogId, 'dog-ares');
      expect(response.f20Outcome, 'ALLOWED');
    });

    test('mapeia erro absolute_restriction_active para absoluteRestriction', () async {
      final gateway = VehicleOccupancyCallableGateway(
        invoker: (fn, data) async {
          throw FirebaseFunctionsException(
            message: 'K9 bloqueado clinicamente',
            code: 'failed-precondition',
            details: {'code': 'absolute_restriction_active'},
          );
        },
      );

      final req = SelfRegularizePriorOccupancyRequestDto(
        operationId: 'op-1',
        vehicleId: 'vh-01',
        expectedSessionId: 'sess-1',
        expectedGeneration: 1,
        incomingCrewId: 'crew-1',
        f10ScheduleSnapshotId: 'snap-1',
        k9AssociationIntent: 'K9_ASSOCIATION_REQUESTED',
        dogId: 'dog-1',
        inspectionEvidence: const VehicleInspectionEvidenceDto(
          checklistConfirmed: true,
          physicalKeysInHand: true,
        ),
      );

      expect(
        () => gateway.selfRegularizePriorOccupancy(req),
        throwsA(
          isA<ShiftAuthorizationFailure>().having(
            (f) => f.kind,
            'kind',
            ShiftAuthorizationFailureKind.absoluteRestriction,
          ),
        ),
      );
    });

    test('mapeia erro partial_acknowledgement_required para acknowledgementRequired', () async {
      final gateway = VehicleOccupancyCallableGateway(
        invoker: (fn, data) async {
          throw FirebaseFunctionsException(
            message: 'K9 apto com restrições',
            code: 'failed-precondition',
            details: {'code': 'partial_acknowledgement_required'},
          );
        },
      );

      final req = SelfRegularizePriorOccupancyRequestDto(
        operationId: 'op-2',
        vehicleId: 'vh-01',
        expectedSessionId: 'sess-1',
        expectedGeneration: 1,
        incomingCrewId: 'crew-1',
        f10ScheduleSnapshotId: 'snap-1',
        k9AssociationIntent: 'K9_ASSOCIATION_REQUESTED',
        dogId: 'dog-1',
        inspectionEvidence: const VehicleInspectionEvidenceDto(
          checklistConfirmed: true,
          physicalKeysInHand: true,
        ),
      );

      expect(
        () => gateway.selfRegularizePriorOccupancy(req),
        throwsA(
          isA<ShiftAuthorizationFailure>().having(
            (f) => f.kind,
            'kind',
            ShiftAuthorizationFailureKind.acknowledgementRequired,
          ),
        ),
      );
    });

    test('mapeia erro restrictions_unavailable para restrictionsUnavailable', () async {
      final gateway = VehicleOccupancyCallableGateway(
        invoker: (fn, data) async {
          throw FirebaseFunctionsException(
            message: 'Cobertura indeterminada',
            code: 'failed-precondition',
            details: {'code': 'restrictions_unavailable'},
          );
        },
      );

      final req = SelfRegularizePriorOccupancyRequestDto(
        operationId: 'op-3',
        vehicleId: 'vh-01',
        expectedSessionId: 'sess-1',
        expectedGeneration: 1,
        incomingCrewId: 'crew-1',
        f10ScheduleSnapshotId: 'snap-1',
        k9AssociationIntent: 'NO_K9_ASSOCIATION',
        inspectionEvidence: const VehicleInspectionEvidenceDto(
          checklistConfirmed: true,
          physicalKeysInHand: true,
        ),
      );

      expect(
        () => gateway.selfRegularizePriorOccupancy(req),
        throwsA(
          isA<ShiftAuthorizationFailure>().having(
            (f) => f.kind,
            'kind',
            ShiftAuthorizationFailureKind.restrictionsUnavailable,
          ),
        ),
      );
    });

    test('mapeia erro idempotency_conflict para idempotencyConflict', () async {
      final gateway = VehicleOccupancyCallableGateway(
        invoker: (fn, data) async {
          throw FirebaseFunctionsException(
            message: 'Geração esperada desatualizada',
            code: 'failed-precondition',
            details: {'code': 'idempotency_conflict'},
          );
        },
      );

      final req = SelfRegularizePriorOccupancyRequestDto(
        operationId: 'op-4',
        vehicleId: 'vh-01',
        expectedSessionId: 'sess-1',
        expectedGeneration: 1,
        incomingCrewId: 'crew-1',
        f10ScheduleSnapshotId: 'snap-1',
        k9AssociationIntent: 'NO_K9_ASSOCIATION',
        inspectionEvidence: const VehicleInspectionEvidenceDto(
          checklistConfirmed: true,
          physicalKeysInHand: true,
        ),
      );

      expect(
        () => gateway.selfRegularizePriorOccupancy(req),
        throwsA(
          isA<ShiftAuthorizationFailure>().having(
            (f) => f.kind,
            'kind',
            ShiftAuthorizationFailureKind.idempotencyConflict,
          ),
        ),
      );
    });

    test('mapeia erro feature_disabled para invalidState', () async {
      final gateway = VehicleOccupancyCallableGateway(
        invoker: (fn, data) async {
          throw FirebaseFunctionsException(
            message: 'Funcionalidade desabilitada',
            code: 'failed-precondition',
            details: {'code': 'feature_disabled'},
          );
        },
      );

      final req = SelfRegularizePriorOccupancyRequestDto(
        operationId: 'op-5',
        vehicleId: 'vh-01',
        expectedSessionId: 'sess-1',
        expectedGeneration: 1,
        incomingCrewId: 'crew-1',
        f10ScheduleSnapshotId: 'snap-1',
        k9AssociationIntent: 'NO_K9_ASSOCIATION',
        inspectionEvidence: const VehicleInspectionEvidenceDto(
          checklistConfirmed: true,
          physicalKeysInHand: true,
        ),
      );

      expect(
        () => gateway.selfRegularizePriorOccupancy(req),
        throwsA(
          isA<ShiftAuthorizationFailure>().having(
            (f) => f.kind,
            'kind',
            ShiftAuthorizationFailureKind.invalidState,
          ),
        ),
      );
    });

    test('mapeia erro unauthenticated para unauthenticated', () async {
      final gateway = VehicleOccupancyCallableGateway(
        invoker: (fn, data) async {
          throw FirebaseFunctionsException(
            message: 'Autenticação obrigatória',
            code: 'unauthenticated',
          );
        },
      );

      final req = SelfRegularizePriorOccupancyRequestDto(
        operationId: 'op-6',
        vehicleId: 'vh-01',
        expectedSessionId: 'sess-1',
        expectedGeneration: 1,
        incomingCrewId: 'crew-1',
        f10ScheduleSnapshotId: 'snap-1',
        k9AssociationIntent: 'NO_K9_ASSOCIATION',
        inspectionEvidence: const VehicleInspectionEvidenceDto(
          checklistConfirmed: true,
          physicalKeysInHand: true,
        ),
      );

      expect(
        () => gateway.selfRegularizePriorOccupancy(req),
        throwsA(
          isA<ShiftAuthorizationFailure>().having(
            (f) => f.kind,
            'kind',
            ShiftAuthorizationFailureKind.unauthenticated,
          ),
        ),
      );
    });

    test('exceptionallyReconcile executa e deserializa com sucesso', () async {
      late String calledFunction;
      late Map<String, dynamic> calledData;

      final gateway = VehicleOccupancyCallableGateway(
        invoker: (fn, data) async {
          calledFunction = fn;
          calledData = data;
          return {
            'status': 'RECONCILED',
            'engagementId': 'eng-100',
            'vehicleId': 'vh-01',
            'reconciledAt': '2026-11-04T00:30:00.000Z',
            'reconciledByRa': '009988',
          };
        },
      );

      final req = ExceptionallyReconcileEngagementRequestDto(
        operationId: 'rec-1',
        engagementId: 'eng-100',
        vehicleId: 'vh-01',
        expectedSessionId: 'sess-1',
        expectedGeneration: 1,
        reason: 'Ocorrência finalizada via CAD',
        evidenceRef: 'CAD-BO-2026-001',
      );

      final res = await gateway.exceptionallyReconcile(req);

      expect(calledFunction, VehicleOccupancyCallableGateway.fnExceptionallyReconcile);
      expect(calledData['engagementId'], 'eng-100');
      expect(calledData['reason'], 'Ocorrência finalizada via CAD');
      expect(res.status, 'RECONCILED');
      expect(res.engagementId, 'eng-100');
      expect(res.vehicleId, 'vh-01');
      expect(res.reconciledByRa, '009988');
    });

    test('startEngagement e endEngagement executam e deserializam com sucesso', () async {
      final gateway = VehicleOccupancyCallableGateway(
        invoker: (fn, data) async {
          if (fn == VehicleOccupancyCallableGateway.fnStartEngagement) {
            return {
              'status': 'STARTED',
              'engagementId': 'eng-200',
              'vehicleId': 'vh-01',
              'occupancySessionId': 'sess-1',
              'generation': 1,
              'startedAt': '2026-11-04T01:00:00.000Z',
            };
          } else if (fn == VehicleOccupancyCallableGateway.fnEndEngagement) {
            return {
              'status': 'ENDED',
              'engagementId': 'eng-200',
              'vehicleId': 'vh-01',
              'endedAt': '2026-11-04T01:30:00.000Z',
            };
          }
          throw Exception('Unknown fn');
        },
      );

      final startReq = StartOperationalEngagementRequestDto(
        operationId: 'op-start-1',
        vehicleId: 'vh-01',
        expectedSessionId: 'sess-1',
        expectedGeneration: 1,
        linkedOccurrenceId: 'occ-99',
      );
      final startRes = await gateway.startEngagement(startReq);
      expect(startRes.status, 'STARTED');
      expect(startRes.engagementId, 'eng-200');
      expect(startRes.generation, 1);

      final endReq = EndOperationalEngagementRequestDto(
        operationId: 'op-end-1',
        engagementId: 'eng-200',
        vehicleId: 'vh-01',
        expectedSessionId: 'sess-1',
        expectedGeneration: 1,
      );
      final endRes = await gateway.endEngagement(endReq);
      expect(endRes.status, 'ENDED');
      expect(endRes.engagementId, 'eng-200');
    });
  });
}
