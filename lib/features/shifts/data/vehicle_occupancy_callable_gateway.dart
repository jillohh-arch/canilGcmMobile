import 'package:cloud_functions/cloud_functions.dart';
import 'package:canil_gcm/features/shifts/domain/shift_authorization.dart';

/// Function signature for invoking callable cloud functions.
typedef VehicleOccupancyCallableInvoker =
    Future<Map<String, dynamic>> Function(
      String functionName,
      Map<String, dynamic> data,
    );

/// Evidence of physical vehicle inspection and key possession.
final class VehicleInspectionEvidenceDto {
  const VehicleInspectionEvidenceDto({
    required this.checklistConfirmed,
    required this.physicalKeysInHand,
    this.vehicleOdometerKm,
    this.checklistRef,
    this.notes,
  });

  final bool checklistConfirmed;
  final bool physicalKeysInHand;
  final int? vehicleOdometerKm;
  final String? checklistRef;
  final String? notes;

  Map<String, dynamic> toJson() => {
    'checklistConfirmed': checklistConfirmed,
    'physicalKeysInHand': physicalKeysInHand,
    if (vehicleOdometerKm != null) 'vehicleOdometerKm': vehicleOdometerKm,
    if (checklistRef != null) 'checklistRef': checklistRef,
    if (notes != null) 'notes': notes,
  };
}

/// Request DTO for self-regularization succession.
final class SelfRegularizePriorOccupancyRequestDto {
  const SelfRegularizePriorOccupancyRequestDto({
    required this.operationId,
    required this.vehicleId,
    required this.expectedSessionId,
    required this.expectedGeneration,
    required this.incomingCrewId,
    required this.f10ScheduleSnapshotId,
    required this.k9AssociationIntent,
    this.dogId,
    this.acknowledgedRestrictionIds = const <String>[],
    required this.inspectionEvidence,
  });

  final String operationId;
  final String vehicleId;
  final String expectedSessionId;
  final int expectedGeneration;
  final String incomingCrewId;
  final String f10ScheduleSnapshotId;
  final String k9AssociationIntent;
  final String? dogId;
  final List<String> acknowledgedRestrictionIds;
  final VehicleInspectionEvidenceDto inspectionEvidence;

  Map<String, dynamic> toJson() => {
    'operationId': operationId,
    'vehicleId': vehicleId,
    'expectedSessionId': expectedSessionId,
    'expectedGeneration': expectedGeneration,
    'incomingCrewId': incomingCrewId,
    'f10ScheduleSnapshotId': f10ScheduleSnapshotId,
    'k9AssociationIntent': k9AssociationIntent,
    if (dogId != null) 'dogId': dogId,
    'acknowledgedRestrictionIds': acknowledgedRestrictionIds,
    'inspectionEvidence': inspectionEvidence.toJson(),
  };
}

/// Response DTO for self-regularization succession.
final class SelfRegularizePriorOccupancyResponseDto {
  const SelfRegularizePriorOccupancyResponseDto({
    required this.status,
    required this.operationId,
    required this.vehicleId,
    required this.predecessorSessionId,
    required this.predecessorGeneration,
    required this.successorSessionId,
    required this.successorGeneration,
    required this.effectiveCrewId,
    this.effectiveDogId,
    required this.transitionedAt,
    required this.receiptId,
    required this.f20Outcome,
  });

  final String status;
  final String operationId;
  final String vehicleId;
  final String predecessorSessionId;
  final int predecessorGeneration;
  final String successorSessionId;
  final int successorGeneration;
  final String effectiveCrewId;
  final String? effectiveDogId;
  final DateTime transitionedAt;
  final String receiptId;
  final String f20Outcome;

  factory SelfRegularizePriorOccupancyResponseDto.fromJson(
    Map<String, dynamic> json,
  ) {
    final status = json['status'] as String? ?? '';
    final operationId = json['operationId'] as String? ?? '';
    final vehicleId = json['vehicleId'] as String? ?? '';
    final predecessorSessionId = json['predecessorSessionId'] as String? ?? '';
    final predecessorGeneration = json['predecessorGeneration'] as int? ?? 0;
    final successorSessionId = json['successorSessionId'] as String? ?? '';
    final successorGeneration = json['successorGeneration'] as int? ?? 0;
    final effectiveCrewId = json['effectiveCrewId'] as String? ?? '';
    final effectiveDogId = json['effectiveDogId'] as String?;
    final transitionedAtRaw = json['transitionedAt'] as String?;
    final receiptId = json['receiptId'] as String? ?? operationId;
    final f20Outcome = json['f20Outcome'] as String? ?? 'NOT_APPLICABLE';

    if (operationId.isEmpty || vehicleId.isEmpty || successorSessionId.isEmpty) {
      throw const ShiftAuthorizationFailure(
        ShiftAuthorizationFailureKind.internal,
        'Resposta do backend inválida ao auto-regularizar viatura.',
      );
    }

    return SelfRegularizePriorOccupancyResponseDto(
      status: status,
      operationId: operationId,
      vehicleId: vehicleId,
      predecessorSessionId: predecessorSessionId,
      predecessorGeneration: predecessorGeneration,
      successorSessionId: successorSessionId,
      successorGeneration: successorGeneration,
      effectiveCrewId: effectiveCrewId,
      effectiveDogId: effectiveDogId,
      transitionedAt: transitionedAtRaw != null
          ? (DateTime.tryParse(transitionedAtRaw) ?? DateTime.now())
          : DateTime.now(),
      receiptId: receiptId,
      f20Outcome: f20Outcome,
    );
  }
}

/// Request DTO for exceptional reconciliation.
final class ExceptionallyReconcileEngagementRequestDto {
  const ExceptionallyReconcileEngagementRequestDto({
    required this.operationId,
    required this.engagementId,
    required this.vehicleId,
    required this.expectedSessionId,
    required this.expectedGeneration,
    required this.reason,
    required this.evidenceRef,
  });

  final String operationId;
  final String engagementId;
  final String vehicleId;
  final String expectedSessionId;
  final int expectedGeneration;
  final String reason;
  final String evidenceRef;

  Map<String, dynamic> toJson() => {
    'operationId': operationId,
    'engagementId': engagementId,
    'vehicleId': vehicleId,
    'expectedSessionId': expectedSessionId,
    'expectedGeneration': expectedGeneration,
    'reason': reason,
    'evidenceRef': evidenceRef,
  };
}

/// Response DTO for exceptional reconciliation.
final class ExceptionallyReconcileEngagementResponseDto {
  const ExceptionallyReconcileEngagementResponseDto({
    required this.status,
    required this.engagementId,
    required this.vehicleId,
    required this.reconciledAt,
    required this.reconciledByRa,
  });

  final String status;
  final String engagementId;
  final String vehicleId;
  final DateTime reconciledAt;
  final String reconciledByRa;

  factory ExceptionallyReconcileEngagementResponseDto.fromJson(
    Map<String, dynamic> json,
  ) {
    final status = json['status'] as String? ?? '';
    final engagementId = json['engagementId'] as String? ?? '';
    final vehicleId = json['vehicleId'] as String? ?? '';
    final reconciledAtRaw = json['reconciledAt'] as String?;
    final reconciledByRa = json['reconciledByRa'] as String? ?? '';

    if (engagementId.isEmpty || vehicleId.isEmpty) {
      throw const ShiftAuthorizationFailure(
        ShiftAuthorizationFailureKind.internal,
        'Resposta do backend inválida ao reconciliar engajamento operacional.',
      );
    }

    return ExceptionallyReconcileEngagementResponseDto(
      status: status,
      engagementId: engagementId,
      vehicleId: vehicleId,
      reconciledAt: reconciledAtRaw != null
          ? (DateTime.tryParse(reconciledAtRaw) ?? DateTime.now())
          : DateTime.now(),
      reconciledByRa: reconciledByRa,
    );
  }
}

/// Request DTO for starting operational engagement.
final class StartOperationalEngagementRequestDto {
  const StartOperationalEngagementRequestDto({
    required this.operationId,
    required this.vehicleId,
    required this.expectedSessionId,
    required this.expectedGeneration,
    this.linkedOccurrenceId,
  });

  final String operationId;
  final String vehicleId;
  final String expectedSessionId;
  final int expectedGeneration;
  final String? linkedOccurrenceId;

  Map<String, dynamic> toJson() => {
    'operationId': operationId,
    'vehicleId': vehicleId,
    'expectedSessionId': expectedSessionId,
    'expectedGeneration': expectedGeneration,
    if (linkedOccurrenceId != null) 'linkedOccurrenceId': linkedOccurrenceId,
  };
}

/// Response DTO for starting operational engagement.
final class StartOperationalEngagementResponseDto {
  const StartOperationalEngagementResponseDto({
    required this.status,
    required this.engagementId,
    required this.vehicleId,
    required this.occupancySessionId,
    required this.generation,
    required this.startedAt,
  });

  final String status;
  final String engagementId;
  final String vehicleId;
  final String occupancySessionId;
  final int generation;
  final DateTime startedAt;

  factory StartOperationalEngagementResponseDto.fromJson(
    Map<String, dynamic> json,
  ) {
    final status = json['status'] as String? ?? '';
    final engagementId = json['engagementId'] as String? ?? '';
    final vehicleId = json['vehicleId'] as String? ?? '';
    final occupancySessionId = json['occupancySessionId'] as String? ?? '';
    final generation = json['generation'] as int? ?? 0;
    final startedAtRaw = json['startedAt'] as String?;

    if (engagementId.isEmpty || vehicleId.isEmpty) {
      throw const ShiftAuthorizationFailure(
        ShiftAuthorizationFailureKind.internal,
        'Resposta inválida ao iniciar engajamento operacional.',
      );
    }

    return StartOperationalEngagementResponseDto(
      status: status,
      engagementId: engagementId,
      vehicleId: vehicleId,
      occupancySessionId: occupancySessionId,
      generation: generation,
      startedAt: startedAtRaw != null
          ? (DateTime.tryParse(startedAtRaw) ?? DateTime.now())
          : DateTime.now(),
    );
  }
}

/// Request DTO for ending operational engagement.
final class EndOperationalEngagementRequestDto {
  const EndOperationalEngagementRequestDto({
    required this.operationId,
    required this.engagementId,
    required this.vehicleId,
    required this.expectedSessionId,
    required this.expectedGeneration,
  });

  final String operationId;
  final String engagementId;
  final String vehicleId;
  final String expectedSessionId;
  final int expectedGeneration;

  Map<String, dynamic> toJson() => {
    'operationId': operationId,
    'engagementId': engagementId,
    'vehicleId': vehicleId,
    'expectedSessionId': expectedSessionId,
    'expectedGeneration': expectedGeneration,
  };
}

/// Response DTO for ending operational engagement.
final class EndOperationalEngagementResponseDto {
  const EndOperationalEngagementResponseDto({
    required this.status,
    required this.engagementId,
    required this.vehicleId,
    required this.endedAt,
  });

  final String status;
  final String engagementId;
  final String vehicleId;
  final DateTime endedAt;

  factory EndOperationalEngagementResponseDto.fromJson(
    Map<String, dynamic> json,
  ) {
    final status = json['status'] as String? ?? '';
    final engagementId = json['engagementId'] as String? ?? '';
    final vehicleId = json['vehicleId'] as String? ?? '';
    final endedAtRaw = json['endedAt'] as String?;

    if (engagementId.isEmpty || vehicleId.isEmpty) {
      throw const ShiftAuthorizationFailure(
        ShiftAuthorizationFailureKind.internal,
        'Resposta inválida ao encerrar engajamento operacional.',
      );
    }

    return EndOperationalEngagementResponseDto(
      status: status,
      engagementId: engagementId,
      vehicleId: vehicleId,
      endedAt: endedAtRaw != null
          ? (DateTime.tryParse(endedAtRaw) ?? DateTime.now())
          : DateTime.now(),
    );
  }
}

/// Typed gateway for vehicle occupancy HTTPS callables.
final class VehicleOccupancyCallableGateway {
  VehicleOccupancyCallableGateway({
    FirebaseFunctions? functions,
    VehicleOccupancyCallableInvoker? invoker,
  }) : _functionsOverride = functions,
       _invokerOverride = invoker;

  static const String region = 'southamerica-east1';
  static const String fnSelfRegularize = 'vehicleOccupancySelfRegularizePriorOccupancy';
  static const String fnExceptionallyReconcile = 'vehicleOccupancyExceptionallyReconcileOperationalEngagement';
  static const String fnStartEngagement = 'vehicleOccupancyStartOperationalEngagement';
  static const String fnEndEngagement = 'vehicleOccupancyEndOperationalEngagement';

  final FirebaseFunctions? _functionsOverride;
  final VehicleOccupancyCallableInvoker? _invokerOverride;
  FirebaseFunctions? _cachedFunctions;

  FirebaseFunctions get _functions => _cachedFunctions ??=
      _functionsOverride ??
      FirebaseFunctions.instanceFor(region: region);

  Future<Map<String, dynamic>> _invoke(
    String functionName,
    Map<String, dynamic> data,
  ) async {
    final override = _invokerOverride;
    if (override != null) return override(functionName, data);
    final result = await _functions.httpsCallable(functionName).call(data);
    if (result.data is! Map) {
      throw const ShiftAuthorizationFailure(
        ShiftAuthorizationFailureKind.internal,
        'Resposta inválida do servidor ao processar ocupação de viatura.',
      );
    }
    return Map<String, dynamic>.from(result.data as Map);
  }

  Future<SelfRegularizePriorOccupancyResponseDto> selfRegularizePriorOccupancy(
    SelfRegularizePriorOccupancyRequestDto request,
  ) async {
    try {
      final raw = await _invoke(fnSelfRegularize, request.toJson());
      return SelfRegularizePriorOccupancyResponseDto.fromJson(raw);
    } on ShiftAuthorizationFailure {
      rethrow;
    } on FirebaseFunctionsException catch (error) {
      throw _mapOccupancyFunctionsError(error);
    } catch (_) {
      throw const ShiftAuthorizationFailure(
        ShiftAuthorizationFailureKind.internal,
        'Não foi possível concluir a auto-regularização da viatura.',
      );
    }
  }

  Future<ExceptionallyReconcileEngagementResponseDto> exceptionallyReconcile(
    ExceptionallyReconcileEngagementRequestDto request,
  ) async {
    try {
      final raw = await _invoke(fnExceptionallyReconcile, request.toJson());
      return ExceptionallyReconcileEngagementResponseDto.fromJson(raw);
    } on ShiftAuthorizationFailure {
      rethrow;
    } on FirebaseFunctionsException catch (error) {
      throw _mapOccupancyFunctionsError(error);
    } catch (_) {
      throw const ShiftAuthorizationFailure(
        ShiftAuthorizationFailureKind.internal,
        'Não foi possível concluir a reconciliação excepcional.',
      );
    }
  }

  Future<StartOperationalEngagementResponseDto> startEngagement(
    StartOperationalEngagementRequestDto request,
  ) async {
    try {
      final raw = await _invoke(fnStartEngagement, request.toJson());
      return StartOperationalEngagementResponseDto.fromJson(raw);
    } on ShiftAuthorizationFailure {
      rethrow;
    } on FirebaseFunctionsException catch (error) {
      throw _mapOccupancyFunctionsError(error);
    } catch (_) {
      throw const ShiftAuthorizationFailure(
        ShiftAuthorizationFailureKind.internal,
        'Não foi possível iniciar o engajamento operacional da viatura.',
      );
    }
  }

  Future<EndOperationalEngagementResponseDto> endEngagement(
    EndOperationalEngagementRequestDto request,
  ) async {
    try {
      final raw = await _invoke(fnEndEngagement, request.toJson());
      return EndOperationalEngagementResponseDto.fromJson(raw);
    } on ShiftAuthorizationFailure {
      rethrow;
    } on FirebaseFunctionsException catch (error) {
      throw _mapOccupancyFunctionsError(error);
    } catch (_) {
      throw const ShiftAuthorizationFailure(
        ShiftAuthorizationFailureKind.internal,
        'Não foi possível finalizar o engajamento operacional da viatura.',
      );
    }
  }

  static ShiftAuthorizationFailure _mapOccupancyFunctionsError(
    FirebaseFunctionsException error,
  ) {
    final details = error.details;
    final detailsMap = details is Map
        ? Map<String, dynamic>.from(details)
        : const <String, dynamic>{};
    final appCode = (detailsMap['code'] as String?)?.trim().toLowerCase();

    switch (appCode) {
      case 'absolute_restriction_active':
        return ShiftAuthorizationFailure(
          ShiftAuthorizationFailureKind.absoluteRestriction,
          error.message ?? 'K9 temporariamente inapto para operação. Restrição absoluta ativa.',
        );
      case 'partial_acknowledgement_required':
        return ShiftAuthorizationFailure(
          ShiftAuthorizationFailureKind.acknowledgementRequired,
          error.message ?? 'K9 apto com restrições. Ciência do condutor obrigatória.',
        );
      case 'restrictions_unavailable':
        return ShiftAuthorizationFailure(
          ShiftAuthorizationFailureKind.restrictionsUnavailable,
          error.message ?? 'Não foi possível validar restrições ou cobertura operacional.',
        );
      case 'invalid_state':
        return ShiftAuthorizationFailure(
          ShiftAuthorizationFailureKind.invalidState,
          error.message ?? 'Estado atual da viatura incompatível com a operação.',
        );
      case 'idempotency_conflict':
        return ShiftAuthorizationFailure(
          ShiftAuthorizationFailureKind.idempotencyConflict,
          error.message ?? 'Conflito de concorrência ou operação já realizada. Atualize os dados.',
        );
      case 'permission_denied':
        return ShiftAuthorizationFailure(
          ShiftAuthorizationFailureKind.permissionDenied,
          error.message ?? 'Operador não autorizado para esta ação.',
        );
      case 'invalid_argument':
        return ShiftAuthorizationFailure(
          ShiftAuthorizationFailureKind.invalidArgument,
          error.message ?? 'Parâmetros inválidos para a operação.',
        );
      case 'feature_disabled':
        return ShiftAuthorizationFailure(
          ShiftAuthorizationFailureKind.invalidState,
          error.message ?? 'Funcionalidade desabilitada temporariamente.',
        );
    }

    return switch (error.code.trim().toLowerCase()) {
      'unauthenticated' => const ShiftAuthorizationFailure(
        ShiftAuthorizationFailureKind.unauthenticated,
        'Sessão expirada. Autentique-se novamente.',
      ),
      'permission-denied' => ShiftAuthorizationFailure(
        ShiftAuthorizationFailureKind.permissionDenied,
        error.message ?? 'Permissão negada.',
      ),
      'not-found' => ShiftAuthorizationFailure(
        ShiftAuthorizationFailureKind.notFound,
        error.message ?? 'Recurso não encontrado.',
      ),
      'invalid-argument' => ShiftAuthorizationFailure(
        ShiftAuthorizationFailureKind.invalidArgument,
        error.message ?? 'Argumento inválido.',
      ),
      'failed-precondition' => ShiftAuthorizationFailure(
        ShiftAuthorizationFailureKind.invalidState,
        error.message ?? 'Condição prévia não atendida.',
      ),
      _ => ShiftAuthorizationFailure(
        ShiftAuthorizationFailureKind.internal,
        error.message ?? 'Erro interno no servidor.',
      ),
    };
  }
}
