import 'health_v1_enums.dart';
import 'health_v1_enums_ext.dart';
import 'health_v1_models.dart';
import 'health_v1_value_objects.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ExamProcess — agregado próprio com ciclo de vida independente
// (Domain Model §2.3; ADR-001 §"Agregados canônicos").
// ─────────────────────────────────────────────────────────────────────────────

final class ExamProcess {
  ExamProcess({
    required this.id,
    required this.caseId,
    required this.dogId,
    required this.examType,
    required ExamStage stage,
    required this.title,
    required this.createdAt,
    required this.recordedBy,
    required this.schemaVersion,
    DateTime? requestedAt,
    RecordedBy? requestedBy,
    ProfessionalIdentity? requestProfessional,
    String? requestReason,
    ExamUrgency urgency = ExamUrgency.routine,
    String? labName,
    DateTime? collectedAt,
    RecordedBy? collectedBy,
    String? collectionSite,
    String? collectionNotes,
    DateTime? resultedAt,
    RecordedBy? resultReceivedBy,
    HealthDocumentRef? resultDocument,
    String? resultSummary,
    DateTime? interpretedAt,
    RecordedBy? interpretedBy,
    ProfessionalIdentity? interpretationProfessional,
    String? interpretationText,
    HealthDocumentRef? interpretationDocument,
    DateTime? impactAssessedAt,
    RecordedBy? impactAssessedBy,
    OperationalImpact? operationalImpact,
    DateTime? cancelledAt,
    RecordedBy? cancelledBy,
    String? cancelReason,
  }) : stage = stage,
       urgency = urgency,
       requestedAt = requestedAt,
       requestedBy = requestedBy,
       requestProfessional = requestProfessional,
       requestReason = requestReason?.trim(),
       labName = labName?.trim(),
       collectedAt = collectedAt,
       collectedBy = collectedBy,
       collectionSite = collectionSite?.trim(),
       collectionNotes = collectionNotes?.trim(),
       resultedAt = resultedAt,
       resultReceivedBy = resultReceivedBy,
       resultDocument = resultDocument,
       resultSummary = resultSummary?.trim(),
       interpretedAt = interpretedAt,
       interpretedBy = interpretedBy,
       interpretationProfessional = interpretationProfessional,
       interpretationText = interpretationText?.trim(),
       interpretationDocument = interpretationDocument,
       impactAssessedAt = impactAssessedAt,
       impactAssessedBy = impactAssessedBy,
       operationalImpact = operationalImpact,
       cancelledAt = cancelledAt,
       cancelledBy = cancelledBy,
       cancelReason = cancelReason?.trim() {
    if (schemaVersion <= 0) {
      throw const HealthDomainException(
        'invalid_schema_version',
        'schema_version deve ser positivo',
      );
    }
    // Invariante: cancellation metadata é consistente.
    final cancellation = [cancelReason, cancelledAt, cancelledBy];
    final hasAny = cancellation.any((value) => value != null);
    final hasAll = cancellation.every((value) => value != null);
    if (hasAny && !hasAll) {
      throw const HealthDomainException(
        'incomplete_cancellation_metadata',
        'Metadados de cancelamento devem ser completos',
      );
    }
    if (stage == ExamStage.cancelled && !hasAll) {
      throw const HealthDomainException(
        'missing_cancellation_metadata',
        'Exame cancelado exige motivo, instante e autoria',
      );
    }
    if (stage != ExamStage.cancelled && hasAny) {
      throw const HealthDomainException(
        'unexpected_cancellation_metadata',
        'Exame não cancelado não pode ter metadados de cancelamento',
      );
    }
    // Invariantes por estágio (Domain Model §2.3 §"Campos por estágio").
    _requireStageMetadata(
      stage: stage,
      required: requestedAt,
      field: 'requested_at',
    );
    _requireStageMetadata(
      stage: stage,
      required: collectedAt,
      field: 'collected_at',
      stageRequired: ExamStage.collected,
    );
    _requireStageMetadata(
      stage: stage,
      required: resultedAt,
      field: 'resulted_at',
      stageRequired: ExamStage.resulted,
    );
    _requireStageMetadata(
      stage: stage,
      required: interpretedAt,
      field: 'interpreted_at',
      stageRequired: ExamStage.interpreted,
    );
    _requireStageMetadata(
      stage: stage,
      required: impactAssessedAt,
      field: 'impact_assessed_at',
      stageRequired: ExamStage.impactAssessed,
    );
    if (stage == ExamStage.interpreted && interpretationText == null) {
      throw const HealthDomainException(
        'missing_interpretation_text',
        'interpretação exige interpretation_text',
      );
    }
    if (stage == ExamStage.impactAssessed && operationalImpact == null) {
      throw const HealthDomainException(
        'missing_operational_impact',
        'impact_assessed exige operational_impact',
      );
    }
  }

  static void _requireStageMetadata({
    required ExamStage stage,
    required DateTime? required,
    required String field,
    ExamStage? stageRequired,
  }) {
    final minStage = stageRequired ?? ExamStage.requested;
    if (stage.index >= minStage.index && required == null) {
      throw HealthDomainException(
        'missing_stage_field',
        'Estágio ${stage.wireName} exige $field',
      );
    }
  }

  final String id;
  final String caseId;
  final String dogId;
  final ExamType examType;
  final ExamStage stage;
  final ExamUrgency urgency;
  final String title;
  final DateTime createdAt;
  final RecordedBy recordedBy;
  final int schemaVersion;

  final DateTime? requestedAt;
  final RecordedBy? requestedBy;
  final ProfessionalIdentity? requestProfessional;
  final String? requestReason;
  final String? labName;

  final DateTime? collectedAt;
  final RecordedBy? collectedBy;
  final String? collectionSite;
  final String? collectionNotes;

  final DateTime? resultedAt;
  final RecordedBy? resultReceivedBy;
  final HealthDocumentRef? resultDocument;
  final String? resultSummary;

  final DateTime? interpretedAt;
  final RecordedBy? interpretedBy;
  final ProfessionalIdentity? interpretationProfessional;
  final String? interpretationText;
  final HealthDocumentRef? interpretationDocument;

  final DateTime? impactAssessedAt;
  final RecordedBy? impactAssessedBy;
  final OperationalImpact? operationalImpact;

  final DateTime? cancelledAt;
  final RecordedBy? cancelledBy;
  final String? cancelReason;
}

/// Urgência da solicitação de exame — enum canônico simples.
/// Documentação não aprofunda; valores padronizados.
enum ExamUrgency {
  routine,
  urgent,
  stat;

  String get wireName => switch (this) {
    ExamUrgency.routine => 'routine',
    ExamUrgency.urgent => 'urgent',
    ExamUrgency.stat => 'stat',
  };
}
