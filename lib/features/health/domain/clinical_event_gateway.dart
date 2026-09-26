import 'clinical_event_read_model.dart';

/// Exceção de domínio lançada ou emitida ao falhar na leitura de eventos clínicos.
class ClinicalEventReadException implements Exception {
  const ClinicalEventReadException(this.message, {this.code, this.cause});

  final String message;
  final String? code;
  final Object? cause;

  @override
  String toString() =>
      'ClinicalEventReadException($code): $message${cause != null ? ' (cause: $cause)' : ''}';
}

/// Gateway de domínio somente-leitura para o prontuário de eventos clínicos e emendas.
///
/// Não expõe capacidade de escrita ou mutação.
/// Não depende do SDK do Firebase na camada de domínio.
abstract interface class ClinicalEventGateway {
  /// Emite a lista cronológica de eventos clínicos de um caso em tempo real.
  ///
  /// Ordenação canônica esperada: `occurred_at DESC`.
  Stream<List<ClinicalEventReadModel>> watchCaseEvents({
    required String dogId,
    required String caseId,
  });

  /// Lê uma única vez a lista cronológica de eventos clínicos de um caso.
  Future<List<ClinicalEventReadModel>> readCaseEvents({
    required String dogId,
    required String caseId,
  });

  /// Emite a lista cronológica de emendas registradas para um evento clínico específico.
  ///
  /// Ordenação canônica esperada: `recorded_at ASC`.
  Stream<List<ClinicalAmendmentReadModel>> watchEventAmendments({
    required String dogId,
    required String caseId,
    required String eventId,
  });

  /// Lê uma única vez as emendas registradas para um evento clínico específico.
  Future<List<ClinicalAmendmentReadModel>> readEventAmendments({
    required String dogId,
    required String caseId,
    required String eventId,
  });

  /// Lê um único evento clínico pelo seu ID documental.
  Future<ClinicalEventReadModel?> readEvent({
    required String dogId,
    required String caseId,
    required String eventId,
  });
}
