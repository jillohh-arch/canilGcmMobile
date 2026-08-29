enum HealthWeightContext { routine, clinical, preOp, postOp }

extension HealthWeightContextWire on HealthWeightContext {
  String get wireValue => switch (this) {
    HealthWeightContext.routine => 'routine',
    HealthWeightContext.clinical => 'clinical',
    HealthWeightContext.preOp => 'pre_op',
    HealthWeightContext.postOp => 'post_op',
  };

  String get label => switch (this) {
    HealthWeightContext.routine => 'Rotina',
    HealthWeightContext.clinical => 'Clínica',
    HealthWeightContext.preOp => 'Pré-operacional',
    HealthWeightContext.postOp => 'Pós-operacional',
  };
}

final class CreateHealthWeightCommand {
  const CreateHealthWeightCommand({
    required this.dogId,
    required this.operationId,
    required this.weightKg,
    required this.measuredAt,
    this.context,
    this.notes,
  });

  final String dogId;
  final String operationId;
  final double weightKg;
  final DateTime measuredAt;
  final HealthWeightContext? context;
  final String? notes;
}

final class HealthWeightMutationReceipt {
  const HealthWeightMutationReceipt({
    required this.dogId,
    required this.entityId,
    required this.weightKg,
    required this.revision,
    required this.wasNoOp,
  });

  final String dogId;
  final String entityId;
  final double weightKg;
  final int revision;
  final bool wasNoOp;
}

enum HealthWeightMutationErrorCode {
  unauthenticated,
  permissionDenied,
  invalidArgument,
  notFound,
  failedPrecondition,
  unavailable,
  deadlineExceeded,
  malformedResponse,
  internal,
}

final class HealthWeightMutationFailure implements Exception {
  const HealthWeightMutationFailure(this.code, this.message);

  final HealthWeightMutationErrorCode code;
  final String message;

  bool get isTransient =>
      code == HealthWeightMutationErrorCode.unavailable ||
      code == HealthWeightMutationErrorCode.deadlineExceeded;

  @override
  String toString() => 'HealthWeightMutationFailure($code): $message';
}

abstract interface class HealthWeightMutationGateway {
  Future<HealthWeightMutationReceipt> createRecord(
    CreateHealthWeightCommand command,
  );
}
