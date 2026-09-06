import 'package:flutter/foundation.dart';

import 'health_v1_enums.dart';

/// Ator interno responsável pelo registro ou mutação de um evento clínico.
///
/// Reflete o envelope persistido `{uid, name, internal_role}`.
/// `internalRole` é uma string aberta (vocabulário aberto na leitura),
/// representando atribuição/perfil interno do usuário no sistema K9
/// (valores conhecidos emitidos pelo servidor incluem "admin" e "condutor").
/// NUNCA interpretar esta dimensão como [ClinicalProfessionalReadModel] / veterinário.
@immutable
final class ClinicalActorReadModel {
  const ClinicalActorReadModel({
    required this.uid,
    required this.name,
    required this.internalRole,
    this.rawMap = const <String, dynamic>{},
    this.isDegraded = false,
  });

  final String uid;
  final String name;
  final String internalRole;
  final Map<String, dynamic> rawMap;
  final bool isDegraded;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClinicalActorReadModel &&
          runtimeType == other.runtimeType &&
          uid == other.uid &&
          name == other.name &&
          internalRole == other.internalRole &&
          isDegraded == other.isDegraded;

  @override
  int get hashCode => Object.hash(uid, name, internalRole, isDegraded);

  @override
  String toString() =>
      'ClinicalActorReadModel(uid: $uid, name: $name, internalRole: $internalRole)';
}

/// Identidade profissional externa (ProfessionalIdentity).
///
/// Chaves canônicas persistidas pelo writer clínico:
/// - `name` (obrigatório quando o mapa existe no writer clínico);
/// - `registration_type` (ex: CRMV-SP);
/// - `registration_number` (ex: 12345);
/// - `clinic` (ex: Hospital Veterinário Central).
///
/// Quaisquer chaves adicionais ou não normalizadas (ex: provenientes do ExamProcess)
/// são preservadas com segurança em [rawMap].
/// Dimensão estritamente externa, NUNCA mesclada com [ClinicalActorReadModel].
@immutable
final class ClinicalProfessionalReadModel {
  const ClinicalProfessionalReadModel({
    this.name,
    this.registrationType,
    this.registrationNumber,
    this.clinic,
    this.rawMap = const <String, dynamic>{},
  });

  final String? name;
  final String? registrationType;
  final String? registrationNumber;
  final String? clinic;
  final Map<String, dynamic> rawMap;

  String? get formattedRegistration {
    final t = registrationType?.trim();
    final n = registrationNumber?.trim();
    if (t != null && t.isNotEmpty && n != null && n.isNotEmpty) {
      return '$t $n';
    }
    return t ?? n;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClinicalProfessionalReadModel &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          registrationType == other.registrationType &&
          registrationNumber == other.registrationNumber &&
          clinic == other.clinic;

  @override
  int get hashCode =>
      Object.hash(name, registrationType, registrationNumber, clinic);
}

/// Vocabulário congelado de emendas clínicas (schema §2.3, ADR-002).
enum ClinicalAmendmentType {
  correction,
  addendum,
  complement;

  String get wireName => switch (this) {
    ClinicalAmendmentType.correction => 'correction',
    ClinicalAmendmentType.addendum => 'addendum',
    ClinicalAmendmentType.complement => 'complement',
  };

  String get labelPtBr => switch (this) {
    ClinicalAmendmentType.correction => 'Correção',
    ClinicalAmendmentType.addendum => 'Adendo',
    ClinicalAmendmentType.complement => 'Complemento',
  };

  static ParsedHealthEnum<ClinicalAmendmentType> parse(Object? value) =>
      parseHealthEnum(
        value,
        ClinicalAmendmentType.values,
        (item) => item.wireName,
      );
}

/// Read model canônico e imutável de uma Emenda Clínica (ClinicalAmendment).
///
/// Subcoleção:
/// `dogs/{dogId}/clinical_cases/{caseId}/clinical_events/{eventId}/clinical_amendments/{amendmentId}`
@immutable
final class ClinicalAmendmentReadModel {
  const ClinicalAmendmentReadModel({
    required this.id,
    required this.eventId,
    required this.caseId,
    required this.dogId,
    required this.type,
    required this.reason,
    this.payloadType,
    this.payloadVersion,
    required this.content,
    this.recordedBy,
    this.recordedAt,
    this.schemaVersion,
    this.ordinal,
    this.dataQualityIssues = const <String>[],
    this.rawDoc = const <String, dynamic>{},
  });

  final String id;
  final String eventId;
  final String caseId;
  final String dogId;
  final ParsedHealthEnum<ClinicalAmendmentType> type;
  final String reason;
  final String? payloadType;
  final int? payloadVersion;
  final Map<String, dynamic> content;
  final ClinicalActorReadModel? recordedBy;
  final DateTime? recordedAt;
  final int? schemaVersion;
  final int? ordinal;
  final List<String> dataQualityIssues;
  final Map<String, dynamic> rawDoc;

  bool get hasQualityIssues => dataQualityIssues.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClinicalAmendmentReadModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          eventId == other.eventId &&
          caseId == other.caseId &&
          dogId == other.dogId &&
          type == other.type &&
          reason == other.reason &&
          recordedAt == other.recordedAt;

  @override
  int get hashCode =>
      Object.hash(id, eventId, caseId, dogId, type, reason, recordedAt);
}

/// Read model canônico e imutável de um Evento Clínico (ClinicalEvent).
///
/// Subcoleção:
/// `dogs/{dogId}/clinical_cases/{caseId}/clinical_events/{eventId}`
///
/// Invariantes consumidas:
/// - IDs contextuais preservados.
/// - Ausência de campos não vira false/0/now silenciosamente.
/// - `occurred_at` e `recorded_at` preservam distinção semântica estrita.
/// - `has_amendments` e `amendment_count` preservam null quando ausentes no writer.
/// - Somente leitura: sem métodos de escrita/mutação.
@immutable
final class ClinicalEventReadModel {
  const ClinicalEventReadModel({
    required this.id,
    required this.caseId,
    required this.dogId,
    required this.type,
    required this.status,
    this.occurredAt,
    this.recordedAt,
    this.updatedAt,
    this.recordedBy,
    this.payloadType,
    this.payloadVersion,
    this.schemaVersion,
    this.revision,
    required this.content,
    this.attachmentRefs,
    this.hasAmendments,
    this.amendmentCount,
    this.lastAmendedAt,
    this.finalizedAt,
    this.cancelReason,
    this.cancelledAt,
    this.cancelledBy,
    this.professional,
    this.examId,
    this.dataQualityIssues = const <String>[],
    this.rawDoc = const <String, dynamic>{},
  });

  final String id;
  final String caseId;
  final String dogId;
  final ParsedHealthEnum<ClinicalEventType> type;
  final ParsedHealthEnum<ClinicalEventStatus> status;

  /// Instante em que o fato clínico efetivamente ocorreu.
  /// Preservado como `null` se ausente ou malformado na origem (não defaulted para DateTime.now).
  final DateTime? occurredAt;

  /// Instante em que o fato foi gravado pelo servidor.
  final DateTime? recordedAt;

  /// Metadado temporal da última mutação.
  final DateTime? updatedAt;

  /// Ator autenticado que registrou o evento.
  final ClinicalActorReadModel? recordedBy;

  final String? payloadType;
  final int? payloadVersion;
  final int? schemaVersion;

  /// Concurrency authority (F1.C1). Inteiro >= 1.
  final int? revision;

  /// Conteúdo clínico estruturado do payload.
  final Map<String, dynamic> content;

  /// Referências imutáveis de anexo (HealthDocument IDs — nunca URLs).
  /// - `null`: UNKNOWN / campo ausente no documento persistido;
  /// - `[]`: explicitamente nenhum anexo associado;
  /// - `[ids]`: lista de HealthDocument IDs associados.
  final List<String>? attachmentRefs;

  /// Sinalizador de emendas. `null` se ausente no documento persistido (ex: Exam writer).
  final bool? hasAmendments;

  /// Quantidade de emendas. `null` se ausente no documento persistido.
  final int? amendmentCount;

  /// Instante da última emenda anexada.
  final DateTime? lastAmendedAt;

  /// Instante da finalização do evento (se finalizado).
  final DateTime? finalizedAt;

  /// Motivo do cancelamento (se cancelado).
  final String? cancelReason;

  /// Instante do cancelamento (se cancelado).
  final DateTime? cancelledAt;

  /// Ator autenticado que executou o cancelamento.
  final ClinicalActorReadModel? cancelledBy;

  /// Identidade profissional externa (opcional).
  final ClinicalProfessionalReadModel? professional;

  /// Identificador do exame associado (quando originado por ExamProcess).
  final String? examId;

  /// Lista explícita de inconformidades ou degradações de integridade detectadas no parsing.
  final List<String> dataQualityIssues;

  /// Documento original bruto persistido no Firestore.
  final Map<String, dynamic> rawDoc;

  // ───────────────────────────────────────────────────────────────────────────
  // Getters de conveniência de leitura
  // ───────────────────────────────────────────────────────────────────────────

  bool get isDraft => status.value == ClinicalEventStatus.draft;
  bool get isFinal => status.value == ClinicalEventStatus.finalised;
  bool get isCancelled => status.value == ClinicalEventStatus.cancelled;

  bool get hasQualityIssues => dataQualityIssues.isNotEmpty;

  /// Determina se há indicação factual de emendas existentes.
  /// Se `hasAmendments` for explicitamente false, retorna false.
  /// Se `hasAmendments` for true, retorna true.
  /// Se for nulo mas `amendmentCount` > 0, deduz true.
  /// Se ambos forem ausentes/nulos, retorna null (UNKNOWN).
  bool? get knownHasAmendments {
    if (hasAmendments != null) return hasAmendments;
    if (amendmentCount != null) return amendmentCount! > 0;
    return null;
  }

  /// Fallback explícito e puramente técnico para ordenação cronológica.
  ///
  /// NÃO altera a semântica de exibição de [occurredAt].
  DateTime get occurredAtOrFallback =>
      occurredAt ??
      recordedAt ??
      updatedAt ??
      DateTime.fromMillisecondsSinceEpoch(0);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClinicalEventReadModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          caseId == other.caseId &&
          dogId == other.dogId &&
          type == other.type &&
          status == other.status &&
          revision == other.revision;

  @override
  int get hashCode => Object.hash(id, caseId, dogId, type, status, revision);

  @override
  String toString() =>
      'ClinicalEventReadModel(id: $id, type: ${type.raw}, status: ${status.raw}, occurredAt: $occurredAt)';
}
