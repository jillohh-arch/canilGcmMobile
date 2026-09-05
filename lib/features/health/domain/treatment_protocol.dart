import 'health_v1_enums_ext.dart';
import 'health_v1_models.dart';
import 'health_v1_value_objects.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TreatmentProtocol — protocolo de medicação/terapia (Domain Model §2.4).
// ─────────────────────────────────────────────────────────────────────────────

final class TreatmentProtocol {
  TreatmentProtocol({
    required this.id,
    required this.dogId,
    required this.caseId,
    required this.medicationName,
    required this.dose,
    required this.schedule,
    required this.startDate,
    required this.recordedBy,
    required this.professional,
    required this.sourceDocument,
    required this.status,
    required this.schemaVersion,
    String? instructions,
    this.endDate,
    this.durationDays,
    String? dosageDisplay,
    String? frequencyDisplay,
    this.pausedAt,
    String? pauseReason,
    this.completedAt,
    this.cancelledAt,
    String? cancelReason,
  }) : instructions = instructions?.trim(),
       dosageDisplay = dosageDisplay?.trim(),
       frequencyDisplay = frequencyDisplay?.trim(),
       pauseReason = pauseReason?.trim(),
       cancelReason = cancelReason?.trim() {
    if (schemaVersion <= 0) {
      throw const HealthDomainException(
        'invalid_schema_version',
        'schema_version deve ser positivo',
      );
    }
    if (durationDays != null && durationDays! <= 0) {
      throw const HealthDomainException(
        'invalid_duration_days',
        'duration_days deve ser positivo',
      );
    }
    if (endDate != null && endDate!.isBefore(startDate)) {
      throw const HealthDomainException(
        'inconsistent_end_date',
        'end_date não pode ser anterior a start_date',
      );
    }
    if (status == TreatmentStatus.completed && completedAt == null) {
      throw const HealthDomainException(
        'missing_completion_metadata',
        'completed exige completed_at',
      );
    }
    if (status == TreatmentStatus.paused &&
        (pausedAt == null || pauseReason == null)) {
      throw const HealthDomainException(
        'missing_pause_metadata',
        'paused exige paused_at e pause_reason',
      );
    }
    final cancelAny = cancelledAt != null || cancelReason != null;
    final cancelAll = cancelledAt != null && cancelReason != null;
    if (cancelAny && !cancelAll) {
      throw const HealthDomainException(
        'incomplete_cancellation_metadata',
        'Metadados de cancelamento devem ser completos',
      );
    }
    if (status == TreatmentStatus.cancelled && !cancelAll) {
      throw const HealthDomainException(
        'missing_cancellation_metadata',
        'cancelled exige cancelled_at e cancel_reason',
      );
    }
    if (status != TreatmentStatus.cancelled && cancelAny) {
      throw const HealthDomainException(
        'unexpected_cancellation_metadata',
        'protocolo não cancelado não pode ter metadados de cancelamento',
      );
    }
    if (status == TreatmentStatus.active &&
        (pausedAt != null || pauseReason != null || completedAt != null)) {
      throw const HealthDomainException(
        'inconsistent_active_state',
        'active não pode ter metadados paused/completed/cancelled',
      );
    }
  }

  final String id;
  final String dogId;
  final String caseId;
  final String medicationName;
  final DoseBlock dose;
  final ScheduleBlock schedule;
  final DateTime startDate;
  final RecordedBy recordedBy;
  final ProfessionalIdentity professional;
  final HealthDocumentRef sourceDocument;
  final TreatmentStatus status;
  final int schemaVersion;
  final String? instructions;
  final DateTime? endDate;
  final int? durationDays;
  final String? dosageDisplay;
  final String? frequencyDisplay;
  final DateTime? pausedAt;
  final String? pauseReason;
  final DateTime? completedAt;
  final DateTime? cancelledAt;
  final String? cancelReason;

  @override
  bool operator ==(Object other) =>
      other is TreatmentProtocol &&
      other.id == id &&
      other.dogId == dogId &&
      other.caseId == caseId &&
      other.medicationName == medicationName &&
      other.dose == dose &&
      other.schedule == schedule &&
      other.startDate == startDate &&
      other.recordedBy == recordedBy &&
      other.professional == professional &&
      other.sourceDocument == sourceDocument &&
      other.status == status &&
      other.schemaVersion == schemaVersion &&
      other.instructions == instructions &&
      other.endDate == endDate &&
      other.durationDays == durationDays &&
      other.dosageDisplay == dosageDisplay &&
      other.frequencyDisplay == frequencyDisplay &&
      other.pausedAt == pausedAt &&
      other.pauseReason == pauseReason &&
      other.completedAt == completedAt &&
      other.cancelledAt == cancelledAt &&
      other.cancelReason == cancelReason;

  @override
  int get hashCode => Object.hashAll([
    id,
    dogId,
    caseId,
    medicationName,
    dose,
    schedule,
    startDate,
    recordedBy,
    professional,
    sourceDocument,
    status,
    schemaVersion,
    instructions,
    endDate,
    durationDays,
    dosageDisplay,
    frequencyDisplay,
    pausedAt,
    pauseReason,
    completedAt,
    cancelledAt,
    cancelReason,
  ]);

  Map<String, dynamic> toMap() {
    return {
      'protocol_id': id,
      'id': id,
      'dog_id': dogId,
      'case_id': caseId,
      'medication_name': medicationName,
      'dose': {
        'value': dose.value,
        'unit': dose.unit.wireName,
        'per_kg': dose.perKg,
        'route': dose.route.wireName,
      },
      'schedule': {
        'type': schedule.type.wireName,
        if (schedule.intervalMinutes != null)
          'interval_minutes': schedule.intervalMinutes,
        'times_of_day': schedule.timesOfDay,
        'timezone': schedule.timezone,
        'tolerance_minutes': schedule.toleranceMinutes,
      },
      'start_date': startDate.toUtc().toIso8601String(),
      'recorded_by': {
        'uid': recordedBy.uid,
        'name': recordedBy.name,
        'internal_role': recordedBy.internalRole,
      },
      'professional': {
        'name': professional.name,
        'registration_type': professional.registrationType.wireName,
        'registration_number': professional.registrationNumber,
        'clinic': professional.clinic,
        if (professional.specialty != null) 'specialty': professional.specialty,
      },
      'source_document': {
        'health_document_id': sourceDocument.healthDocumentId,
        if (sourceDocument.description != null)
          'description': sourceDocument.description,
      },
      'status': status.wireName,
      'schema_version': schemaVersion,
      if (instructions != null) 'instructions': instructions,
      if (endDate != null) 'end_date': endDate!.toUtc().toIso8601String(),
      if (durationDays != null) 'duration_days': durationDays,
      if (dosageDisplay != null) 'dosage_display': dosageDisplay,
      if (frequencyDisplay != null) 'frequency_display': frequencyDisplay,
      if (pausedAt != null) 'paused_at': pausedAt!.toUtc().toIso8601String(),
      if (pauseReason != null) 'pause_reason': pauseReason,
      if (completedAt != null)
        'completed_at': completedAt!.toUtc().toIso8601String(),
      if (cancelledAt != null)
        'cancelled_at': cancelledAt!.toUtc().toIso8601String(),
      if (cancelReason != null) 'cancel_reason': cancelReason,
    };
  }

  factory TreatmentProtocol.fromMap(
    Map<String, dynamic> map, {
    String? documentId,
  }) {
    final id = documentId ??
        map['protocol_id'] as String? ??
        map['id'] as String? ??
        '';
    final dogId = map['dog_id'] as String? ?? map['dogId'] as String? ?? '';
    final caseId = map['case_id'] as String? ?? map['caseId'] as String? ?? '';
    final medicationName = map['medication_name'] as String? ??
        map['medicationName'] as String? ??
        '';

    final doseMap = (map['dose'] as Map?)?.cast<String, dynamic>() ?? const {};
    final doseValue = (doseMap['value'] as num?)?.toDouble() ?? 1.0;
    final doseUnitStr = doseMap['unit'] as String? ?? 'mg';
    final doseUnit = DoseUnit.values.firstWhere(
      (u) => u.wireName == doseUnitStr,
      orElse: () => DoseUnit.mg,
    );
    final dosePerKg =
        doseMap['per_kg'] as bool? ?? doseMap['perKg'] as bool? ?? false;
    final doseRouteStr = doseMap['route'] as String? ?? 'oral';
    final doseRoute = DoseRoute.values.firstWhere(
      (r) => r.wireName == doseRouteStr,
      orElse: () => DoseRoute.oral,
    );
    final dose = DoseBlock(
      value: doseValue,
      unit: doseUnit,
      perKg: dosePerKg,
      route: doseRoute,
    );

    final schedMap =
        (map['schedule'] as Map?)?.cast<String, dynamic>() ?? const {};
    final schedTypeStr = schedMap['type'] as String? ?? 'interval';
    final schedType = ScheduleTypeBlock.values.firstWhere(
      (s) => s.wireName == schedTypeStr,
      orElse: () => ScheduleTypeBlock.interval,
    );
    final intervalMinutes = (schedMap['interval_minutes'] as num?)?.toInt() ??
        (schedMap['intervalMinutes'] as num?)?.toInt() ??
        (schedType == ScheduleTypeBlock.interval ? 720 : null);
    final timesOfDayRaw = schedMap['times_of_day'] ?? schedMap['timesOfDay'];
    final timesOfDay = timesOfDayRaw is List
        ? timesOfDayRaw.map((t) => t.toString()).toList()
        : <String>[];
    final timezone = schedMap['timezone'] as String? ?? 'America/Sao_Paulo';
    final toleranceMinutes = (schedMap['tolerance_minutes'] as num?)?.toInt() ??
        (schedMap['toleranceMinutes'] as num?)?.toInt() ??
        30;
    final schedule = ScheduleBlock(
      type: schedType,
      intervalMinutes: intervalMinutes,
      timesOfDay: timesOfDay,
      timezone: timezone,
      toleranceMinutes: toleranceMinutes,
    );

    final startDate = _parseDateTime(map['start_date'] ?? map['startDate']) ??
        DateTime.now();
    final endDate = _parseDateTime(map['end_date'] ?? map['endDate']);
    final durationDays = (map['duration_days'] as num?)?.toInt() ??
        (map['durationDays'] as num?)?.toInt();

    final recordedByMap =
        (map['recorded_by'] as Map?)?.cast<String, dynamic>() ?? const {};
    final recordedBy = RecordedBy(
      uid: recordedByMap['uid'] as String? ?? '',
      name: recordedByMap['name'] as String? ?? '',
      internalRole: recordedByMap['internal_role'] as String? ??
          recordedByMap['internalRole'] as String? ??
          'condutor',
    );

    final profMap =
        (map['professional'] as Map?)?.cast<String, dynamic>() ?? const {};
    final regTypeStr = profMap['registration_type'] as String? ??
        profMap['registrationType'] as String? ??
        'CRMV';
    final regType = ProfessionalRegistrationType.values.firstWhere(
      (r) => r.wireName == regTypeStr || r.name == regTypeStr,
      orElse: () => ProfessionalRegistrationType.crmv,
    );
    final professional = ProfessionalIdentity(
      name: profMap['name'] as String? ?? 'Veterinário',
      registrationType: regType,
      registrationNumber: profMap['registration_number'] as String? ??
          profMap['registrationNumber'] as String? ??
          'CRMV-0000',
      clinic: profMap['clinic'] as String? ?? 'Clínica Veterinária',
      specialty: profMap['specialty'] as String?,
    );

    final srcDocMap =
        (map['source_document'] as Map?)?.cast<String, dynamic>() ??
        (map['sourceDocument'] as Map?)?.cast<String, dynamic>() ??
        const {};
    final sourceDocument = HealthDocumentRef(
      healthDocumentId: srcDocMap['health_document_id'] as String? ??
          srcDocMap['healthDocumentId'] as String? ??
          'doc_default',
      description: srcDocMap['description'] as String?,
    );

    final statusStr = map['status'] as String? ?? 'active';
    final status = TreatmentStatus.values.firstWhere(
      (s) => s.wireName == statusStr,
      orElse: () => TreatmentStatus.active,
    );
    final schemaVersion = (map['schema_version'] as num?)?.toInt() ??
        (map['schemaVersion'] as num?)?.toInt() ??
        1;

    return TreatmentProtocol(
      id: id,
      dogId: dogId,
      caseId: caseId,
      medicationName: medicationName,
      dose: dose,
      schedule: schedule,
      startDate: startDate,
      endDate: endDate,
      durationDays: durationDays,
      recordedBy: recordedBy,
      professional: professional,
      sourceDocument: sourceDocument,
      status: status,
      schemaVersion: schemaVersion,
      instructions: map['instructions'] as String?,
      dosageDisplay:
          map['dosage_display'] as String? ?? map['dosageDisplay'] as String?,
      frequencyDisplay:
          map['frequency_display'] as String? ??
          map['frequencyDisplay'] as String?,
      pausedAt: _parseDateTime(map['paused_at'] ?? map['pausedAt']),
      pauseReason:
          map['pause_reason'] as String? ?? map['pauseReason'] as String?,
      completedAt: _parseDateTime(map['completed_at'] ?? map['completedAt']),
      cancelledAt: _parseDateTime(map['cancelled_at'] ?? map['cancelledAt']),
      cancelReason:
          map['cancel_reason'] as String? ?? map['cancelReason'] as String?,
    );
  }

  static DateTime? _parseDateTime(Object? raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw);
    try {
      final dynamic dyn = raw;
      final toDate = dyn.toDate;
      if (toDate is Function) return toDate() as DateTime;
    } catch (_) {}
    return null;
  }
}
