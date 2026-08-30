import 'health_v1_enums.dart';

export 'health_v1_enums.dart'
    show ParsedHealthEnum, ParsedHealthEnumState, parseHealthEnum;

// ─────────────────────────────────────────────────────────────────────────────
// Novos enums canônicos para os 9 agregados restantes da Fase 1C.
// Nomes seguem o Domain Model §6 e ADR-005.
// ─────────────────────────────────────────────────────────────────────────────

/// Estágios do ciclo de vida de um ExamProcess (Domain Model §2.3).
/// Os valores canônicos são exatamente os mesmos definidos na Fase 1B;
/// este enum é reaproveitado integralmente (`ExamStage` já existente).
typedef HealthExamStage = ExamStage;

/// Status do protocolo terapêutico (Domain Model §2.4 e §6).
enum TreatmentStatus {
  active,
  paused,
  completed,
  cancelled;

  String get wireName => switch (this) {
    TreatmentStatus.active => 'active',
    TreatmentStatus.paused => 'paused',
    TreatmentStatus.completed => 'completed',
    TreatmentStatus.cancelled => 'cancelled',
  };
}

/// Status de uma dose administrada (Domain Model §2.5 e §6).
enum DoseStatus {
  administered,
  skipped,
  cancelled;

  String get wireName => switch (this) {
    DoseStatus.administered => 'administered',
    DoseStatus.skipped => 'skipped',
    DoseStatus.cancelled => 'cancelled',
  };
}

/// Nível de impacto de uma restrição operacional (Domain Model §2.11, §6).
enum RestrictionLevel {
  absolute,
  partial,
  attention;

  String get wireName => switch (this) {
    RestrictionLevel.absolute => 'absolute',
    RestrictionLevel.partial => 'partial',
    RestrictionLevel.attention => 'attention',
  };
}

/// Categoria clínica de uma restrição (Domain Model §6).
enum RestrictionCategory {
  injury,
  postSurgical,
  medicationEffect,
  behavioral,
  infectious,
  chronic,
  preventivePending,
  other;

  String get wireName => switch (this) {
    RestrictionCategory.injury => 'injury',
    RestrictionCategory.postSurgical => 'post_surgical',
    RestrictionCategory.medicationEffect => 'medication_effect',
    RestrictionCategory.behavioral => 'behavioral',
    RestrictionCategory.infectious => 'infectious',
    RestrictionCategory.chronic => 'chronic',
    RestrictionCategory.preventivePending => 'preventive_pending',
    RestrictionCategory.other => 'other',
  };
}

/// Status persistido do ciclo de vida de uma restrição (Domain Model §2.11).
enum RestrictionStatus {
  active,
  ended,
  cancelled;

  String get wireName => switch (this) {
    RestrictionStatus.active => 'active',
    RestrictionStatus.ended => 'ended',
    RestrictionStatus.cancelled => 'cancelled',
  };
}

/// Status oficial de prontidão (Domain Model §2.14 e ADR-005/Readiness Policy §2).
enum ReadinessStatus {
  operational,
  operationalAttention,
  fitWithRestrictions,
  temporarilyUnfit,
  notEvaluated;

  String get wireName => switch (this) {
    ReadinessStatus.operational => 'operational',
    ReadinessStatus.operationalAttention => 'operational_attention',
    ReadinessStatus.fitWithRestrictions => 'fit_with_restrictions',
    ReadinessStatus.temporarilyUnfit => 'temporarily_unfit',
    ReadinessStatus.notEvaluated => 'not_evaluated',
  };
}

/// Lifecycle persistido de um item de agenda (Domain Model §2.12 e ADR-004 §13).
enum ScheduleLifecycleStatus {
  open,
  completed,
  cancelled;

  String get wireName => switch (this) {
    ScheduleLifecycleStatus.open => 'open',
    ScheduleLifecycleStatus.completed => 'completed',
    ScheduleLifecycleStatus.cancelled => 'cancelled',
  };

  /// Parse defensivo (known / unknown / absent). Nunca lança por valor desconhecido.
  static ParsedHealthEnum<ScheduleLifecycleStatus> parse(Object? value) =>
      parseHealthEnum(
        value,
        ScheduleLifecycleStatus.values,
        (item) => item.wireName,
      );
}

/// Estado temporal derivado de um item de agenda.
/// NÃO é persistido (Domain Model §2.12 e ADR-004 §13).
enum HealthScheduleTemporalStatus {
  scheduled,
  upcoming,
  today,
  pending,
  overdue,
  completed,
  cancelled;

  /// Wire name apenas para diagnóstico/apresentação — nunca persistido.
  String get wireName => switch (this) {
    HealthScheduleTemporalStatus.scheduled => 'scheduled',
    HealthScheduleTemporalStatus.upcoming => 'upcoming',
    HealthScheduleTemporalStatus.today => 'today',
    HealthScheduleTemporalStatus.pending => 'pending',
    HealthScheduleTemporalStatus.overdue => 'overdue',
    HealthScheduleTemporalStatus.completed => 'completed',
    HealthScheduleTemporalStatus.cancelled => 'cancelled',
  };
}

/// Tipo de um item de agenda (Domain Model §6).
enum ScheduleType {
  dose,
  vaccination,
  exam,
  consultation,
  weighing,
  reevaluation,
  deworming,
  bath,
  general;

  String get wireName => switch (this) {
    ScheduleType.dose => 'dose',
    ScheduleType.vaccination => 'vaccination',
    ScheduleType.exam => 'exam',
    ScheduleType.consultation => 'consultation',
    ScheduleType.weighing => 'weighing',
    ScheduleType.reevaluation => 'reevaluation',
    ScheduleType.deworming => 'deworming',
    ScheduleType.bath => 'bath',
    ScheduleType.general => 'general',
  };

  /// Parse defensivo (known / unknown / absent). Nunca lança por valor desconhecido.
  static ParsedHealthEnum<ScheduleType> parse(Object? value) =>
      parseHealthEnum(value, ScheduleType.values, (item) => item.wireName);
}

/// Origem do item de agenda (Domain Model §6).
enum ScheduleSourceType {
  treatmentProtocol,
  clinicalCase,
  examProcess,
  preventive,
  manual;

  String get wireName => switch (this) {
    ScheduleSourceType.treatmentProtocol => 'treatment_protocol',
    ScheduleSourceType.clinicalCase => 'clinical_case',
    ScheduleSourceType.examProcess => 'exam_process',
    ScheduleSourceType.preventive => 'preventive',
    ScheduleSourceType.manual => 'manual',
  };

  /// Parse defensivo (known / unknown / absent). Nunca lança por valor desconhecido.
  static ParsedHealthEnum<ScheduleSourceType> parse(Object? value) =>
      parseHealthEnum(
        value,
        ScheduleSourceType.values,
        (item) => item.wireName,
      );
}

/// Tipo de documento clínico (Domain Model §2.10 e §6).
enum HealthDocumentType {
  prescription,
  report,
  certificate,
  examImage,
  examPdf,
  photo,
  vaccinationCard,
  surgicalReport,
  other;

  String get wireName => switch (this) {
    HealthDocumentType.prescription => 'prescription',
    HealthDocumentType.report => 'report',
    HealthDocumentType.certificate => 'certificate',
    HealthDocumentType.examImage => 'exam_image',
    HealthDocumentType.examPdf => 'exam_pdf',
    HealthDocumentType.photo => 'photo',
    HealthDocumentType.vaccinationCard => 'vaccination_card',
    HealthDocumentType.surgicalReport => 'surgical_report',
    HealthDocumentType.other => 'other',
  };

  /// Parse estrito dos nove tipos canônicos.
  ///
  /// Desconhecido vira [ParsedHealthEnumState.unknown] preservando o raw —
  /// nunca cai em `other`, que esconderia dado malformado. O vocabulário
  /// legado (`laudo`, `certificado`, `documento`, `exame`) NÃO é mapeado
  /// (decisão B0-A.2): mapear exigiria uma regra de derivação que o domínio
  /// não possui.
  static ParsedHealthEnum<HealthDocumentType> parse(Object? value) =>
      parseHealthEnum(
        value,
        HealthDocumentType.values,
        (item) => item.wireName,
      );
}

/// Tipo de um exame (Domain Model §6).
enum ExamType {
  bloodWork,
  imaging,
  biopsy,
  culture,
  parasitology,
  urinalysis,
  cardiology,
  dermatology,
  ophthalmology,
  other;

  String get wireName => switch (this) {
    ExamType.bloodWork => 'blood_work',
    ExamType.imaging => 'imaging',
    ExamType.biopsy => 'biopsy',
    ExamType.culture => 'culture',
    ExamType.parasitology => 'parasitology',
    ExamType.urinalysis => 'urinalysis',
    ExamType.cardiology => 'cardiology',
    ExamType.dermatology => 'dermatology',
    ExamType.ophthalmology => 'ophthalmology',
    ExamType.other => 'other',
  };
}

/// Nível de impacto operacional reportado em ClinicalEvent/ExamProcess
/// (Domain Model §5 "Value Objects compartilhados").
enum OperationalImpactLevel {
  none,
  low,
  medium,
  high,
  critical;

  String get wireName => switch (this) {
    OperationalImpactLevel.none => 'none',
    OperationalImpactLevel.low => 'low',
    OperationalImpactLevel.medium => 'medium',
    OperationalImpactLevel.high => 'high',
    OperationalImpactLevel.critical => 'critical',
  };
}

/// Tipo do registro profissional externo (Domain Model §6).
enum ProfessionalRegistrationType {
  crmv,
  crmvZ,
  crn,
  crf,
  cfmv,
  other;

  String get wireName => switch (this) {
    ProfessionalRegistrationType.crmv => 'CRMV',
    ProfessionalRegistrationType.crmvZ => 'CRMV-Z',
    ProfessionalRegistrationType.crn => 'CRN',
    ProfessionalRegistrationType.crf => 'CRF',
    ProfessionalRegistrationType.cfmv => 'CFMV',
    ProfessionalRegistrationType.other => 'other',
  };

  /// Parse de string wire para enum.
  /// Retorna null se o valor não for reconhecido.
  static ProfessionalRegistrationType? fromWire(String value) {
    final normalized = value.toUpperCase().trim();
    return switch (normalized) {
      'CRMV' || 'CRM' => ProfessionalRegistrationType.crmv,
      'CRMV-Z' || 'CRMVZ' => ProfessionalRegistrationType.crmvZ,
      'CRN' => ProfessionalRegistrationType.crn,
      'CRF' || 'CRFA' => ProfessionalRegistrationType.crf,
      'CFMV' => ProfessionalRegistrationType.cfmv,
      'OTHER' => ProfessionalRegistrationType.other,
      _ => null,
    };
  }
}

/// Via de administração de uma dose (Domain Model §6).
enum DoseRoute {
  oral,
  topical,
  injectableSubcutaneous,
  injectableIntramuscular,
  injectableIntravenous,
  inhalation,
  ophthalmic,
  otic,
  nasal;

  String get wireName => switch (this) {
    DoseRoute.oral => 'oral',
    DoseRoute.topical => 'topical',
    DoseRoute.injectableSubcutaneous => 'injectable_subcutaneous',
    DoseRoute.injectableIntramuscular => 'injectable_intramuscular',
    DoseRoute.injectableIntravenous => 'injectable_intravenous',
    DoseRoute.inhalation => 'inhalation',
    DoseRoute.ophthalmic => 'ophthalmic',
    DoseRoute.otic => 'otic',
    DoseRoute.nasal => 'nasal',
  };
}

/// Unidade de dose (Domain Model §6).
enum DoseUnit {
  mg,
  ml,
  mcg,
  g,
  kg,
  ui,
  comprimido,
  gota,
  scoop,
  other;

  String get wireName => switch (this) {
    DoseUnit.mg => 'mg',
    DoseUnit.ml => 'ml',
    DoseUnit.mcg => 'mcg',
    DoseUnit.g => 'g',
    DoseUnit.kg => 'kg',
    DoseUnit.ui => 'ui',
    DoseUnit.comprimido => 'comprimido',
    DoseUnit.gota => 'gota',
    DoseUnit.scoop => 'scoop',
    DoseUnit.other => 'other',
  };
}

/// Tipo do schedule estruturado de um protocolo (Domain Model §6).
enum ScheduleTypeBlock {
  interval,
  fixedTimes,
  prn;

  String get wireName => switch (this) {
    ScheduleTypeBlock.interval => 'interval',
    ScheduleTypeBlock.fixedTimes => 'fixed_times',
    ScheduleTypeBlock.prn => 'prn',
  };
}

/// Tipo de payload versionado de um ClinicalEvent (Domain Model §6).
enum PayloadType {
  consultationV1,
  incidentV1,
  vaccinationV1,
  examRequestV1,
  examCollectionV1,
  examResultV1,
  examInterpretationV1,
  treatmentStartV1,
  treatmentNoteV1,
  doseNoteV1,
  reevaluationV1,
  dischargeV1,
  reopenV1,
  restrictionIssuedV1,
  restrictionEndedV1,
  surgicalNoteV1,
  generalNoteV1,
  observationV1;

  String get wireName => switch (this) {
    PayloadType.consultationV1 => 'consultation_v1',
    PayloadType.incidentV1 => 'incident_v1',
    PayloadType.vaccinationV1 => 'vaccination_v1',
    PayloadType.examRequestV1 => 'exam_request_v1',
    PayloadType.examCollectionV1 => 'exam_collection_v1',
    PayloadType.examResultV1 => 'exam_result_v1',
    PayloadType.examInterpretationV1 => 'exam_interpretation_v1',
    PayloadType.treatmentStartV1 => 'treatment_start_v1',
    PayloadType.treatmentNoteV1 => 'treatment_note_v1',
    PayloadType.doseNoteV1 => 'dose_note_v1',
    PayloadType.reevaluationV1 => 'reevaluation_v1',
    PayloadType.dischargeV1 => 'discharge_v1',
    PayloadType.reopenV1 => 'reopen_v1',
    PayloadType.restrictionIssuedV1 => 'restriction_issued_v1',
    PayloadType.restrictionEndedV1 => 'restriction_ended_v1',
    PayloadType.surgicalNoteV1 => 'surgical_note_v1',
    PayloadType.generalNoteV1 => 'general_note_v1',
    PayloadType.observationV1 => 'observation_v1',
  };
}

/// Status do VaccinationRecord (Domain Model §7).
enum VaccinationStatus {
  finalised,
  cancelled;

  String get wireName => switch (this) {
    VaccinationStatus.finalised => 'final',
    VaccinationStatus.cancelled => 'cancelled',
  };
}

/// Tipo da timeline (ADR-004 §13).
enum HealthTimelineType {
  consultation,
  vaccination,
  weight,
  meal,
  supplement,
  exam,
  treatment,
  dose,
  incident,
  discharge,
  restriction,
  document,
  observation,
  preventive;

  String get wireName => switch (this) {
    HealthTimelineType.consultation => 'consultation',
    HealthTimelineType.vaccination => 'vaccination',
    HealthTimelineType.weight => 'weight',
    HealthTimelineType.meal => 'meal',
    HealthTimelineType.supplement => 'supplement',
    HealthTimelineType.exam => 'exam',
    HealthTimelineType.treatment => 'treatment',
    HealthTimelineType.dose => 'dose',
    HealthTimelineType.incident => 'incident',
    HealthTimelineType.discharge => 'discharge',
    HealthTimelineType.restriction => 'restriction',
    HealthTimelineType.document => 'document',
    HealthTimelineType.observation => 'observation',
    HealthTimelineType.preventive => 'preventive',
  };
}
