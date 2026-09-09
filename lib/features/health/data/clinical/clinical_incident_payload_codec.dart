import 'package:canil_gcm/features/health/data/clinical/clinical_consultation_payload_codec.dart'
    show ClinicalCreatedEvent;
import 'package:canil_gcm/features/health/domain/clinical_incident_command.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';

abstract final class ClinicalIncidentPayloadCodec {
  ClinicalIncidentPayloadCodec._();

  static const freshEventRevision = 1;

  static Map<String, dynamic> openCaseRequest(ClinicalIncidentCommand command) {
    assert(command.opensNewCase, 'Open exige caseId nulo.');
    final wire = <String, dynamic>{
      'dogId': command.dogId,
      'operationId': command.operationId,
      'title': _caseTitle(command),
      'openingType': command.openingType.wireName,
      'eventType': command.eventType.wireName,
      'occurredAt': command.occurredAt.toUtc().toIso8601String(),
      'payloadType': command.payloadType.wireName,
      'payloadVersion': 1,
      'content': command.buildContent(),
    };
    final professional = command.professional;
    if (professional != null && !professional.isEmpty) {
      wire['professional'] = professional.toWire();
    }
    return wire;
  }

  static Map<String, dynamic> appendEventRequest(ClinicalIncidentCommand command) {
    final caseId = command.caseId;
    assert(caseId != null, 'Append exige caseId.');
    final wire = <String, dynamic>{
      'dogId': command.dogId,
      'caseId': caseId,
      'operationId': command.operationId,
      'eventType': command.eventType.wireName,
      'occurredAt': command.occurredAt.toUtc().toIso8601String(),
      'payloadType': command.payloadType.wireName,
      'payloadVersion': 1,
      'content': command.buildContent(),
    };
    final professional = command.professional;
    if (professional != null && !professional.isEmpty) {
      wire['professional'] = professional.toWire();
    }
    return wire;
  }

  static Map<String, dynamic> finalizeEventRequest({
    required String dogId,
    required String caseId,
    required String eventId,
    required String operationId,
    int expectedRevision = freshEventRevision,
  }) {
    return <String, dynamic>{
      'dogId': dogId,
      'caseId': caseId,
      'eventId': eventId,
      'operationId': operationId,
      'expectedRevision': expectedRevision,
    };
  }

  static ClinicalCreatedEvent readOpenResponse(Map<String, dynamic> data) {
    final caseId = _str(data, const ['caseId', 'case_id']);
    final eventId = _str(data, const ['openingEventId', 'opening_event_id']);
    if (caseId == null || eventId == null) {
      throw const FormatException(
        'Resposta de healthOpenClinicalCase sem caseId/openingEventId.',
      );
    }
    return ClinicalCreatedEvent(
      dogId: _str(data, const ['dogId', 'dog_id']) ?? '',
      caseId: caseId,
      eventId: eventId,
      wasNoOp: _bool(data, const ['wasNoOp', 'was_no_op']) ?? false,
    );
  }

  static ClinicalCreatedEvent readAppendResponse(Map<String, dynamic> data) {
    final caseId = _str(data, const ['caseId', 'case_id']);
    final eventId = _str(data, const ['eventId', 'event_id']);
    if (caseId == null || eventId == null) {
      throw const FormatException(
        'Resposta de healthAppendClinicalEvent sem caseId/eventId.',
      );
    }
    return ClinicalCreatedEvent(
      dogId: _str(data, const ['dogId', 'dog_id']) ?? '',
      caseId: caseId,
      eventId: eventId,
      wasNoOp: _bool(data, const ['wasNoOp', 'was_no_op']) ?? false,
    );
  }

  static ({bool isFinal, bool wasNoOp}) readFinalizeResponse(
    Map<String, dynamic> data,
  ) {
    final status = _str(data, const ['status']);
    final wasNoOp = _bool(data, const ['wasNoOp', 'was_no_op']) ?? false;
    return (isFinal: status == 'final', wasNoOp: wasNoOp);
  }

  static String _caseTitle(ClinicalIncidentCommand command) {
    final explicit = command.caseTitle?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      return explicit.length > 200 ? explicit.substring(0, 200) : explicit;
    }
    return 'Intercorrência: ${command.category.label}';
  }

  static String? _str(Map<String, dynamic> map, List<String> candidateKeys) {
    for (final key in candidateKeys) {
      final val = map[key];
      if (val is String && val.isNotEmpty) return val;
    }
    return null;
  }

  static bool? _bool(Map<String, dynamic> map, List<String> candidateKeys) {
    for (final key in candidateKeys) {
      final val = map[key];
      if (val is bool) return val;
    }
    return null;
  }
}
