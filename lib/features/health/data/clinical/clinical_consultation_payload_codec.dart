import 'package:canil_gcm/features/health/domain/clinical_consultation_command.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';

/// Serializa comandos de Consulta para os contratos exatos dos callables
/// clínicos, e lê de volta as respostas.
///
/// Chaves derivadas do source em `142b374`, nunca inferidas:
/// - `parseOpenCaseInput` / `parseAppendEventInput` / `parseEventMutationInput`;
/// - `openCaseResponse` / `appendEventResponse` / `eventMutationResponse`.
///
/// `status` NÃO é enviado: é server-managed
/// (`CLINICAL_EVENT_INITIAL_STATUS = "draft"`), e um campo server-managed no
/// payload é rejeitado por `rejectServerManagedInjection`.
abstract final class ClinicalConsultationPayloadCodec {
  ClinicalConsultationPayloadCodec._();

  /// Revisão de um `ClinicalEvent` recém-criado.
  ///
  /// `clinicalEventDocument` nasce com `revision: 1`, e
  /// `parseExpectedRevision` exige um inteiro `>= 1`. Por isso a finalização
  /// imediata do evento criado sempre usa 1.
  static const freshEventRevision = 1;

  /// Payload de `healthOpenClinicalCase`.
  ///
  /// Open recebe o payload clínico COMPLETO e cria caso + evento de abertura
  /// numa só transação. Nenhum Append é emitido depois: o evento de abertura
  /// já é a consulta.
  static Map<String, dynamic> openCaseRequest(ConsultationCommand command) {
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
    // `attachmentRefs` deliberadamente ausente: o contrato aceita apenas IDs
    // de HealthDocument, e esta entrega não implementa esse upload.
    return wire;
  }

  /// Payload de `healthAppendClinicalEvent`.
  static Map<String, dynamic> appendEventRequest(ConsultationCommand command) {
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

  /// Payload de `healthFinalizeClinicalEvent`.
  ///
  /// `expectedRevision` é obrigatório no contrato; para um evento acabado de
  /// criar vale [freshEventRevision].
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

  /// Lê `openCaseResponse`. Aceita camelCase e snake_case.
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

  /// Lê `appendEventResponse`.
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

  /// Lê `eventMutationResponse` da finalização.
  ///
  /// Só considera finalizado quando o servidor confirma `status = final`.
  static ClinicalFinalizedEvent readFinalizeResponse(
    Map<String, dynamic> data,
  ) {
    final eventId = _str(data, const ['eventId', 'event_id']);
    if (eventId == null) {
      throw const FormatException(
        'Resposta de healthFinalizeClinicalEvent sem eventId.',
      );
    }
    final rawStatus = _str(data, const ['status']);
    final parsed = ClinicalEventStatusWire.parse(rawStatus);
    return ClinicalFinalizedEvent(
      caseId: _str(data, const ['caseId', 'case_id']) ?? '',
      eventId: eventId,
      isFinal: parsed.value == ClinicalEventStatus.finalised,
      revision: _int(data, const ['revision']) ?? 0,
      wasNoOp: _bool(data, const ['wasNoOp', 'was_no_op']) ?? false,
    );
  }

  /// Título do caso na abertura.
  ///
  /// Exigido por `assertText(data.title)`. Usa o título informado quando houver;
  /// senão deriva do motivo da consulta — nunca vazio.
  static String _caseTitle(ConsultationCommand command) {
    final provided = command.caseTitle?.trim();
    if (provided != null && provided.isNotEmpty) return provided;
    return 'Consulta ${command.reason.label}';
  }

  static String? _str(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  static bool? _bool(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value is bool) return value;
    }
    return null;
  }

  static int? _int(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
    }
    return null;
  }
}

/// Evento clínico criado em estado `draft`, aguardando finalização.
final class ClinicalCreatedEvent {
  const ClinicalCreatedEvent({
    required this.dogId,
    required this.caseId,
    required this.eventId,
    required this.wasNoOp,
  });

  final String dogId;
  final String caseId;
  final String eventId;

  /// `true` quando o backend respondeu por replay do mesmo `operationId`.
  final bool wasNoOp;
}

/// Resultado confirmado da finalização.
final class ClinicalFinalizedEvent {
  const ClinicalFinalizedEvent({
    required this.caseId,
    required this.eventId,
    required this.isFinal,
    required this.revision,
    required this.wasNoOp,
  });

  final String caseId;
  final String eventId;

  /// Somente `true` se o servidor devolveu `status = final`.
  final bool isFinal;

  final int revision;
  final bool wasNoOp;
}
