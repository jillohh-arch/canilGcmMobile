enum ClinicalCaseStatus {
  open,
  underInvestigation,
  underTreatment,
  monitoring,
  discharged,
  cancelled,
}

enum ClinicalEventStatus { draft, finalised, cancelled }

enum ClinicalCaseOpeningType {
  incident,
  consultation,
  preventive,
  administrative,
}

enum ClinicalEventType {
  consultation,
  incident,
  vaccination,
  examRequest,
  examCollection,
  examResult,
  examInterpretation,
  treatmentStart,
  treatmentNote,
  doseNote,
  reevaluation,
  discharge,
  reopen,
  restrictionIssued,
  restrictionEnded,
  surgicalNote,
  generalNote,
  observation,
}

enum ExamStage {
  requested,
  collected,
  resulted,
  interpreted,
  impactAssessed,
  cancelled,
}

enum MealPeriod { morning, afternoon, evening, night, extra }

/// Aceitação da refeição (MealLog) — Domain Model §2.8 / D9 / D42.
enum MealAcceptance { full, partial, refused, unknown }

enum WeightRecordType { quick, official, legacySimple }

enum WeightAssessmentStatus { valid, invalidated }

enum WeightInformationSource {
  measuredByRecorder,
  reportedByOtherOperator,
  externalDocumentOrService,
}

enum WeightLocation { kennel, veterinaryClinic, pharmacy, other }

enum WeightMeasurementCondition {
  fasting,
  afterFeeding,
  afterActivityOrTraining,
  noSpecificCondition,
  other,
}

enum WeightEquipmentState {
  none,
  collar,
  harnessOrOperationalEquipment,
  notInformed,
}

enum WeightReadingQuality { stable, approximate, notRecorded }

enum WeightBcsSource {
  operatorAssessment,
  veterinaryGuidance,
  reportedByOtherOperator,
}

enum WeightCorrectionReason { dataEntryError, newScaleReading, other }

enum WeightInvalidationReason {
  wrongDog,
  defectiveScale,
  duplicate,
  irrecoverableError,
  other,
}

enum WeightAssessmentOperationType {
  createQuick,
  createOfficial,
  completeAsOfficial,
  correct,
  invalidate,
  addAttachment,
  removeAttachment,
}

enum WeightConfigurationOperationType { setReferenceRange, setWeightGoal }

enum WeightFollowUpOperationType { createFollowUp }

enum ParsedHealthEnumState { known, unknown, absent }

/// Preserva valores desconhecidos sem confundi-los com ausência.
final class ParsedHealthEnum<T extends Enum> {
  const ParsedHealthEnum._({
    required this.state,
    required this.raw,
    this.value,
  });

  factory ParsedHealthEnum._known({required String raw, required T value}) {
    final normalized = raw.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(raw, 'raw', 'known exige raw não vazio');
    }
    return ParsedHealthEnum._(
      state: ParsedHealthEnumState.known,
      raw: normalized,
      value: value,
    );
  }

  factory ParsedHealthEnum.unknown(String raw) {
    final normalized = raw.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(raw, 'raw', 'unknown exige raw não vazio');
    }
    return ParsedHealthEnum._(
      state: ParsedHealthEnumState.unknown,
      raw: normalized,
    );
  }

  const factory ParsedHealthEnum.absent() = _AbsentHealthEnum<T>;

  final ParsedHealthEnumState state;
  final String? raw;
  final T? value;

  bool get isKnown => state == ParsedHealthEnumState.known;
  bool get isUnknown => state == ParsedHealthEnumState.unknown;
  bool get isAbsent => state == ParsedHealthEnumState.absent;

  @override
  bool operator ==(Object other) =>
      other is ParsedHealthEnum<T> &&
      other.state == state &&
      other.raw == raw &&
      other.value == value;

  @override
  int get hashCode => Object.hash(state, raw, value);
}

final class _AbsentHealthEnum<T extends Enum> extends ParsedHealthEnum<T> {
  const _AbsentHealthEnum()
    : super._(state: ParsedHealthEnumState.absent, raw: null);
}

ParsedHealthEnum<T> _parseEnum<T extends Enum>(
  Object? input,
  Iterable<T> values,
  String Function(T value) wireName,
) {
  final raw = input?.toString().trim() ?? '';
  if (raw.isEmpty) return ParsedHealthEnum<T>.absent();
  for (final value in values) {
    if (wireName(value) == raw) {
      return ParsedHealthEnum<T>._known(raw: raw, value: value);
    }
  }
  return ParsedHealthEnum<T>.unknown(raw);
}

/// Parse defensivo público para enums Health com wire name.
///
/// Valores desconhecidos viram [ParsedHealthEnum.unknown]; raw vazio/null
/// vira [ParsedHealthEnum.absent]. Nunca lança por valor desconhecido.
ParsedHealthEnum<T> parseHealthEnum<T extends Enum>(
  Object? input,
  Iterable<T> values,
  String Function(T value) wireName,
) => _parseEnum(input, values, wireName);

extension ClinicalCaseStatusWire on ClinicalCaseStatus {
  String get wireName => switch (this) {
    ClinicalCaseStatus.open => 'open',
    ClinicalCaseStatus.underInvestigation => 'under_investigation',
    ClinicalCaseStatus.underTreatment => 'under_treatment',
    ClinicalCaseStatus.monitoring => 'monitoring',
    ClinicalCaseStatus.discharged => 'discharged',
    ClinicalCaseStatus.cancelled => 'cancelled',
  };

  static ParsedHealthEnum<ClinicalCaseStatus> parse(Object? value) =>
      _parseEnum(value, ClinicalCaseStatus.values, (item) => item.wireName);
}

extension ClinicalEventStatusWire on ClinicalEventStatus {
  String get wireName => switch (this) {
    ClinicalEventStatus.draft => 'draft',
    ClinicalEventStatus.finalised => 'final',
    ClinicalEventStatus.cancelled => 'cancelled',
  };

  static ParsedHealthEnum<ClinicalEventStatus> parse(Object? value) =>
      _parseEnum(value, ClinicalEventStatus.values, (item) => item.wireName);
}

extension ClinicalCaseOpeningTypeWire on ClinicalCaseOpeningType {
  String get wireName => switch (this) {
    ClinicalCaseOpeningType.incident => 'incident',
    ClinicalCaseOpeningType.consultation => 'consultation',
    ClinicalCaseOpeningType.preventive => 'preventive',
    ClinicalCaseOpeningType.administrative => 'administrative',
  };
}

extension ClinicalEventTypeWire on ClinicalEventType {
  String get wireName => switch (this) {
    ClinicalEventType.consultation => 'consultation',
    ClinicalEventType.incident => 'incident',
    ClinicalEventType.vaccination => 'vaccination',
    ClinicalEventType.examRequest => 'exam_request',
    ClinicalEventType.examCollection => 'exam_collection',
    ClinicalEventType.examResult => 'exam_result',
    ClinicalEventType.examInterpretation => 'exam_interpretation',
    ClinicalEventType.treatmentStart => 'treatment_start',
    ClinicalEventType.treatmentNote => 'treatment_note',
    ClinicalEventType.doseNote => 'dose_note',
    ClinicalEventType.reevaluation => 'reevaluation',
    ClinicalEventType.discharge => 'discharge',
    ClinicalEventType.reopen => 'reopen',
    ClinicalEventType.restrictionIssued => 'restriction_issued',
    ClinicalEventType.restrictionEnded => 'restriction_ended',
    ClinicalEventType.surgicalNote => 'surgical_note',
    ClinicalEventType.generalNote => 'general_note',
    ClinicalEventType.observation => 'observation',
  };

  static ParsedHealthEnum<ClinicalEventType> parse(Object? value) =>
      _parseEnum(value, ClinicalEventType.values, (item) => item.wireName);
}

extension ExamStageWire on ExamStage {
  String get wireName => switch (this) {
    ExamStage.requested => 'requested',
    ExamStage.collected => 'collected',
    ExamStage.resulted => 'resulted',
    ExamStage.interpreted => 'interpreted',
    ExamStage.impactAssessed => 'impact_assessed',
    ExamStage.cancelled => 'cancelled',
  };

  static ParsedHealthEnum<ExamStage> parse(Object? value) =>
      _parseEnum(value, ExamStage.values, (item) => item.wireName);
}

extension MealPeriodWire on MealPeriod {
  String get wireName => switch (this) {
    MealPeriod.morning => 'morning',
    MealPeriod.afternoon => 'afternoon',
    MealPeriod.evening => 'evening',
    MealPeriod.night => 'night',
    MealPeriod.extra => 'extra',
  };

  static ParsedHealthEnum<MealPeriod> parseCanonical(Object? value) =>
      _parseEnum(value, MealPeriod.values, (item) => item.wireName);

  /// Parse legado unknown-safe (D6).
  ///
  /// Aliases: `manha→morning`, `almoco→afternoon`, `noite→night`.
  /// Casing/trim: trim + match exato do alias (política existente); depois
  /// tenta wire canônico. Desconhecido → [ParsedHealthEnum.unknown].
  static ParsedHealthEnum<MealPeriod> parseLegacy(Object? value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return const ParsedHealthEnum<MealPeriod>.absent();
    final canonical = switch (raw) {
      'manha' => MealPeriod.morning,
      'almoco' => MealPeriod.afternoon,
      'noite' => MealPeriod.night,
      _ => null,
    };
    if (canonical != null) {
      return ParsedHealthEnum<MealPeriod>._known(
        raw: canonical.wireName,
        value: canonical,
      );
    }
    return parseCanonical(raw);
  }
}

extension MealAcceptanceWire on MealAcceptance {
  String get wireName => switch (this) {
    MealAcceptance.full => 'full',
    MealAcceptance.partial => 'partial',
    MealAcceptance.refused => 'refused',
    MealAcceptance.unknown => 'unknown',
  };

  /// Parse unknown-safe — nunca promove valor desconhecido a um known incorreto.
  static ParsedHealthEnum<MealAcceptance> parse(Object? value) =>
      _parseEnum(value, MealAcceptance.values, (item) => item.wireName);
}

extension WeightRecordTypeWire on WeightRecordType {
  String get wireName => switch (this) {
    WeightRecordType.quick => 'quick',
    WeightRecordType.official => 'official',
    WeightRecordType.legacySimple => 'legacy_simple',
  };

  String get targetWireName => switch (this) {
    WeightRecordType.quick => 'quick',
    WeightRecordType.official => 'official',
    WeightRecordType.legacySimple => throw StateError(
      'legacy_simple é derivado de leitura e não serializável como target',
    ),
  };

  static ParsedHealthEnum<WeightRecordType> parse(Object? value) =>
      _parseEnum(value, WeightRecordType.values, (item) => item.wireName);
}

extension WeightAssessmentStatusWire on WeightAssessmentStatus {
  String get wireName => switch (this) {
    WeightAssessmentStatus.valid => 'valid',
    WeightAssessmentStatus.invalidated => 'invalidated',
  };

  static ParsedHealthEnum<WeightAssessmentStatus> parse(Object? value) =>
      _parseEnum(value, WeightAssessmentStatus.values, (item) => item.wireName);
}

extension WeightInformationSourceWire on WeightInformationSource {
  String get wireName => switch (this) {
    WeightInformationSource.measuredByRecorder => 'measured_by_recorder',
    WeightInformationSource.reportedByOtherOperator =>
      'reported_by_other_operator',
    WeightInformationSource.externalDocumentOrService =>
      'external_document_or_service',
  };

  static ParsedHealthEnum<WeightInformationSource> parse(Object? value) =>
      _parseEnum(
        value,
        WeightInformationSource.values,
        (item) => item.wireName,
      );
}

extension WeightLocationWire on WeightLocation {
  String get wireName => switch (this) {
    WeightLocation.kennel => 'kennel',
    WeightLocation.veterinaryClinic => 'veterinary_clinic',
    WeightLocation.pharmacy => 'pharmacy',
    WeightLocation.other => 'other',
  };

  static ParsedHealthEnum<WeightLocation> parse(Object? value) =>
      _parseEnum(value, WeightLocation.values, (item) => item.wireName);
}

extension WeightMeasurementConditionWire on WeightMeasurementCondition {
  String get wireName => switch (this) {
    WeightMeasurementCondition.fasting => 'fasting',
    WeightMeasurementCondition.afterFeeding => 'after_feeding',
    WeightMeasurementCondition.afterActivityOrTraining =>
      'after_activity_or_training',
    WeightMeasurementCondition.noSpecificCondition => 'no_specific_condition',
    WeightMeasurementCondition.other => 'other',
  };

  static ParsedHealthEnum<WeightMeasurementCondition> parse(Object? value) =>
      _parseEnum(
        value,
        WeightMeasurementCondition.values,
        (item) => item.wireName,
      );
}

extension WeightEquipmentStateWire on WeightEquipmentState {
  String get wireName => switch (this) {
    WeightEquipmentState.none => 'none',
    WeightEquipmentState.collar => 'collar',
    WeightEquipmentState.harnessOrOperationalEquipment =>
      'harness_or_operational_equipment',
    WeightEquipmentState.notInformed => 'not_informed',
  };

  static ParsedHealthEnum<WeightEquipmentState> parse(Object? value) =>
      _parseEnum(value, WeightEquipmentState.values, (item) => item.wireName);
}

extension WeightReadingQualityWire on WeightReadingQuality {
  String get wireName => switch (this) {
    WeightReadingQuality.stable => 'stable',
    WeightReadingQuality.approximate => 'approximate',
    WeightReadingQuality.notRecorded => 'not_recorded',
  };

  static ParsedHealthEnum<WeightReadingQuality> parse(Object? value) =>
      _parseEnum(value, WeightReadingQuality.values, (item) => item.wireName);
}

extension WeightBcsSourceWire on WeightBcsSource {
  String get wireName => switch (this) {
    WeightBcsSource.operatorAssessment => 'operator_assessment',
    WeightBcsSource.veterinaryGuidance => 'veterinary_guidance',
    WeightBcsSource.reportedByOtherOperator => 'reported_by_other_operator',
  };

  static ParsedHealthEnum<WeightBcsSource> parse(Object? value) =>
      _parseEnum(value, WeightBcsSource.values, (item) => item.wireName);
}

extension WeightCorrectionReasonWire on WeightCorrectionReason {
  String get wireName => switch (this) {
    WeightCorrectionReason.dataEntryError => 'data_entry_error',
    WeightCorrectionReason.newScaleReading => 'new_scale_reading',
    WeightCorrectionReason.other => 'other',
  };

  static ParsedHealthEnum<WeightCorrectionReason> parse(Object? value) =>
      _parseEnum(value, WeightCorrectionReason.values, (item) => item.wireName);
}

extension WeightInvalidationReasonWire on WeightInvalidationReason {
  String get wireName => switch (this) {
    WeightInvalidationReason.wrongDog => 'wrong_dog',
    WeightInvalidationReason.defectiveScale => 'defective_scale',
    WeightInvalidationReason.duplicate => 'duplicate',
    WeightInvalidationReason.irrecoverableError => 'irrecoverable_error',
    WeightInvalidationReason.other => 'other',
  };

  static ParsedHealthEnum<WeightInvalidationReason> parse(Object? value) =>
      _parseEnum(
        value,
        WeightInvalidationReason.values,
        (item) => item.wireName,
      );
}

extension WeightAssessmentOperationTypeWire on WeightAssessmentOperationType {
  String get wireName => switch (this) {
    WeightAssessmentOperationType.createQuick => 'create_quick',
    WeightAssessmentOperationType.createOfficial => 'create_official',
    WeightAssessmentOperationType.completeAsOfficial => 'complete_as_official',
    WeightAssessmentOperationType.correct => 'correct',
    WeightAssessmentOperationType.invalidate => 'invalidate',
    WeightAssessmentOperationType.addAttachment => 'add_attachment',
    WeightAssessmentOperationType.removeAttachment => 'remove_attachment',
  };

  static ParsedHealthEnum<WeightAssessmentOperationType> parse(Object? value) =>
      _parseEnum(
        value,
        WeightAssessmentOperationType.values,
        (item) => item.wireName,
      );
}

extension WeightConfigurationOperationTypeWire
    on WeightConfigurationOperationType {
  String get wireName => switch (this) {
    WeightConfigurationOperationType.setReferenceRange => 'set_reference_range',
    WeightConfigurationOperationType.setWeightGoal => 'set_weight_goal',
  };

  static ParsedHealthEnum<WeightConfigurationOperationType> parse(
    Object? value,
  ) => _parseEnum(
    value,
    WeightConfigurationOperationType.values,
    (item) => item.wireName,
  );
}

extension WeightFollowUpOperationTypeWire on WeightFollowUpOperationType {
  String get wireName => switch (this) {
    WeightFollowUpOperationType.createFollowUp => 'create_follow_up',
  };

  static ParsedHealthEnum<WeightFollowUpOperationType> parse(Object? value) =>
      _parseEnum(
        value,
        WeightFollowUpOperationType.values,
        (item) => item.wireName,
      );
}
