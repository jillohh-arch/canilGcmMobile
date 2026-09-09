import 'clinical_consultation_gateway.dart';
import 'dose_administration.dart';
import 'treatment_protocol.dart';
import 'treatment_protocol_command.dart';

sealed class TreatmentProtocolResult {
  const TreatmentProtocolResult();
}

final class TreatmentProtocolSuccess extends TreatmentProtocolResult {
  const TreatmentProtocolSuccess(this.protocol);
  final TreatmentProtocol protocol;
}

final class DoseAdministrationSuccess extends TreatmentProtocolResult {
  const DoseAdministrationSuccess(this.dose);
  final DoseAdministration dose;
}

final class TreatmentProtocolFailure extends TreatmentProtocolResult {
  const TreatmentProtocolFailure({
    required this.code,
    required this.message,
    this.cause,
  });

  final String code;
  final String message;
  final Object? cause;

  @override
  String toString() => 'TreatmentProtocolFailure($code: $message)';
}

abstract interface class TreatmentProtocolGateway {
  Future<List<ClinicalCaseOption>> loadUsableCases(String dogId);

  Future<List<TreatmentProtocol>> loadProtocols({
    required String dogId,
    String? caseId,
  });

  Stream<List<TreatmentProtocol>> watchProtocols({
    required String dogId,
    String? caseId,
  });

  Future<List<DoseAdministration>> loadProtocolDoses({
    required String dogId,
    required String protocolId,
  });

  Stream<List<DoseAdministration>> watchProtocolDoses({
    required String dogId,
    required String protocolId,
  });

  Stream<List<Map<String, dynamic>>> watchProtocolSchedules({
    required String dogId,
    required String protocolId,
  });

  Future<TreatmentProtocolResult> createProtocol(
    CreateTreatmentProtocolCommand command,
  );

  Future<TreatmentProtocolResult> pauseProtocol(
    PauseTreatmentProtocolCommand command,
  );

  Future<TreatmentProtocolResult> resumeProtocol(
    ResumeTreatmentProtocolCommand command,
  );

  Future<TreatmentProtocolResult> completeProtocol(
    CompleteTreatmentProtocolCommand command,
  );

  Future<TreatmentProtocolResult> cancelProtocol(
    CancelTreatmentProtocolCommand command,
  );

  Future<TreatmentProtocolResult> administerDose(
    AdministerDoseCommand command,
  );

  Future<TreatmentProtocolResult> skipDose(
    SkipDoseCommand command,
  );
}
