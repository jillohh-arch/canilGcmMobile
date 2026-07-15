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

  static ParsedHealthEnum<MealPeriod> parseLegacy(Object? value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return const ParsedHealthEnum<MealPeriod>.absent();
    final canonical = switch (raw) {
      'manha' => MealPeriod.morning,
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
