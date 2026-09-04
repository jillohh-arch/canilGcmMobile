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

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'exam_id': id,
      'case_id': caseId,
      'dog_id': dogId,
      'exam_type': examType.wireName,
      'current_stage': stage.wireName,
      'urgency': urgency.wireName,
      'title': title,
      'created_at': createdAt.toUtc().toIso8601String(),
      'recorded_by': {
        'uid': recordedBy.uid,
        'name': recordedBy.name,
        'internal_role': recordedBy.internalRole,
      },
      'schema_version': schemaVersion,
    };
    if (requestedAt != null) {
      map['requested_at'] = requestedAt!.toUtc().toIso8601String();
    }
    if (requestedBy != null) {
      map['requested_by'] = {
        'uid': requestedBy!.uid,
        'name': requestedBy!.name,
        'internal_role': requestedBy!.internalRole,
      };
    }
    if (requestProfessional != null) {
      map['request_professional'] = {
        'name': requestProfessional!.name,
        'registration_type': requestProfessional!.registrationType.wireName,
        'registration_number': requestProfessional!.registrationNumber,
        'clinic': requestProfessional!.clinic,
        if (requestProfessional!.specialty != null)
          'specialty': requestProfessional!.specialty,
      };
    }
    if (requestReason != null) map['request_reason'] = requestReason;
    if (labName != null) map['lab_name'] = labName;

    if (collectedAt != null) {
      map['collected_at'] = collectedAt!.toUtc().toIso8601String();
    }
    if (collectedBy != null) {
      map['collected_by'] = {
        'uid': collectedBy!.uid,
        'name': collectedBy!.name,
        'internal_role': collectedBy!.internalRole,
      };
    }
    if (collectionSite != null) map['collection_site'] = collectionSite;
    if (collectionNotes != null) map['collection_notes'] = collectionNotes;

    if (resultedAt != null) {
      map['resulted_at'] = resultedAt!.toUtc().toIso8601String();
    }
    if (resultReceivedBy != null) {
      map['result_received_by'] = {
        'uid': resultReceivedBy!.uid,
        'name': resultReceivedBy!.name,
        'internal_role': resultReceivedBy!.internalRole,
      };
    }
    if (resultDocument != null) {
      map['result_document_id'] = resultDocument!.healthDocumentId;
    }
    if (resultSummary != null) map['result_summary'] = resultSummary;

    if (interpretedAt != null) {
      map['interpreted_at'] = interpretedAt!.toUtc().toIso8601String();
    }
    if (interpretedBy != null) {
      map['interpreted_by'] = {
        'uid': interpretedBy!.uid,
        'name': interpretedBy!.name,
        'internal_role': interpretedBy!.internalRole,
      };
    }
    if (interpretationProfessional != null) {
      map['interpretation_professional'] = {
        'name': interpretationProfessional!.name,
        'registration_type':
            interpretationProfessional!.registrationType.wireName,
        'registration_number':
            interpretationProfessional!.registrationNumber,
        'clinic': interpretationProfessional!.clinic,
        if (interpretationProfessional!.specialty != null)
          'specialty': interpretationProfessional!.specialty,
      };
    }
    if (interpretationText != null) {
      map['interpretation_text'] = interpretationText;
    }
    if (interpretationDocument != null) {
      map['interpretation_document_id'] =
          interpretationDocument!.healthDocumentId;
    }

    if (impactAssessedAt != null) {
      map['impact_assessed_at'] =
          impactAssessedAt!.toUtc().toIso8601String();
    }
    if (impactAssessedBy != null) {
      map['impact_assessed_by'] = {
        'uid': impactAssessedBy!.uid,
        'name': impactAssessedBy!.name,
        'internal_role': impactAssessedBy!.internalRole,
      };
    }
    if (operationalImpact != null) {
      map['operational_impact'] = {
        'level': operationalImpact!.level.wireName,
        'description': operationalImpact!.description,
        'restrictions_issued': operationalImpact!.restrictionsIssued,
      };
    }

    if (cancelledAt != null) {
      map['cancelled_at'] = cancelledAt!.toUtc().toIso8601String();
    }
    if (cancelledBy != null) {
      map['cancelled_by'] = {
        'uid': cancelledBy!.uid,
        'name': cancelledBy!.name,
        'internal_role': cancelledBy!.internalRole,
      };
    }
    if (cancelReason != null) map['cancel_reason'] = cancelReason;

    return map;
  }

  factory ExamProcess.fromMap(
    Map<String, dynamic> map, {
    String? documentId,
  }) {
    final id = documentId ??
        map['exam_id'] as String? ??
        map['id'] as String? ??
        '';
    final caseId = map['case_id'] as String? ??
        map['caseId'] as String? ??
        '';
    final dogId = map['dog_id'] as String? ??
        map['dogId'] as String? ??
        '';
    final title = map['title'] as String? ?? 'Exame';

    final examTypeRaw = map['exam_type'] ?? map['examType'];
    final examType = ExamType.values.firstWhere(
      (e) => e.wireName == examTypeRaw,
      orElse: () => ExamType.other,
    );

    final stageRaw = map['current_stage'] ?? map['stage'];
    final stage = ExamStageWire.parse(stageRaw).value ??
        ExamStage.requested;

    final urgencyRaw = map['urgency'];
    final urgency = ExamUrgency.values.firstWhere(
      (u) => u.wireName == urgencyRaw,
      orElse: () => ExamUrgency.routine,
    );

    final createdAt = _parseDateTime(map['created_at'] ?? map['createdAt']) ??
        DateTime.now().toUtc();
    final schemaVersion =
        (map['schema_version'] ?? map['schemaVersion'] as num?)?.toInt() ?? 1;

    final recordedBy = _parseRecordedBy(map['recorded_by'] ?? map['recordedBy']) ??
        RecordedBy(uid: 'system', name: 'Sistema', internalRole: 'sistema');

    final requestedAt = _parseDateTime(
      map['requested_at'] ?? map['requestedAt'],
    );
    final requestedBy = _parseRecordedBy(
      map['requested_by'] ?? map['requestedBy'],
    );
    final requestProfessional = _parseProfessional(
      map['request_professional'] ?? map['requestProfessional'],
    );
    final requestReason = map['request_reason'] as String? ??
        map['requestReason'] as String?;
    final labName = map['lab_name'] as String? ?? map['labName'] as String?;

    final collectedAt = _parseDateTime(
      map['collected_at'] ?? map['collectedAt'],
    );
    final collectedBy = _parseRecordedBy(
      map['collected_by'] ?? map['collectedBy'],
    );
    final collectionSite = map['collection_site'] as String? ??
        map['collectionSite'] as String?;
    final collectionNotes = map['collection_notes'] as String? ??
        map['collectionNotes'] as String?;

    final resultedAt = _parseDateTime(map['resulted_at'] ?? map['resultedAt']);
    final resultReceivedBy = _parseRecordedBy(
      map['result_received_by'] ?? map['resultReceivedBy'],
    );
    final resultDocId = map['result_document_id'] as String? ??
        map['resultDocumentId'] as String?;
    final resultDocument = resultDocId != null
        ? HealthDocumentRef(healthDocumentId: resultDocId)
        : null;
    final resultSummary = map['result_summary'] as String? ??
        map['resultSummary'] as String?;

    final interpretedAt = _parseDateTime(
      map['interpreted_at'] ?? map['interpretedAt'],
    );
    final interpretedBy = _parseRecordedBy(
      map['interpreted_by'] ?? map['interpretedBy'],
    );
    final interpretationProfessional = _parseProfessional(
      map['interpretation_professional'] ??
          map['interpretationProfessional'],
    );
    final interpretationText = map['interpretation_text'] as String? ??
        map['interpretationText'] as String?;
    final interpDocId = map['interpretation_document_id'] as String? ??
        map['interpretationDocumentId'] as String?;
    final interpretationDocument = interpDocId != null
        ? HealthDocumentRef(healthDocumentId: interpDocId)
        : null;

    final impactAssessedAt = _parseDateTime(
      map['impact_assessed_at'] ?? map['impactAssessedAt'],
    );
    final impactAssessedBy = _parseRecordedBy(
      map['impact_assessed_by'] ?? map['impactAssessedBy'],
    );
    final operationalImpact = _parseOperationalImpact(
      map['operational_impact'] ?? map['operationalImpact'],
    );

    final cancelledAt = _parseDateTime(
      map['cancelled_at'] ?? map['cancelledAt'],
    );
    final cancelledBy = _parseRecordedBy(
      map['cancelled_by'] ?? map['cancelledBy'],
    );
    final cancelReason = map['cancel_reason'] as String? ??
        map['cancelReason'] as String?;

    return ExamProcess(
      id: id,
      caseId: caseId,
      dogId: dogId,
      examType: examType,
      stage: stage,
      urgency: urgency,
      title: title,
      createdAt: createdAt,
      recordedBy: recordedBy,
      schemaVersion: schemaVersion,
      requestedAt: requestedAt,
      requestedBy: requestedBy,
      requestProfessional: requestProfessional,
      requestReason: requestReason,
      labName: labName,
      collectedAt: collectedAt,
      collectedBy: collectedBy,
      collectionSite: collectionSite,
      collectionNotes: collectionNotes,
      resultedAt: resultedAt,
      resultReceivedBy: resultReceivedBy,
      resultDocument: resultDocument,
      resultSummary: resultSummary,
      interpretedAt: interpretedAt,
      interpretedBy: interpretedBy,
      interpretationProfessional: interpretationProfessional,
      interpretationText: interpretationText,
      interpretationDocument: interpretationDocument,
      impactAssessedAt: impactAssessedAt,
      impactAssessedBy: impactAssessedBy,
      operationalImpact: operationalImpact,
      cancelledAt: cancelledAt,
      cancelledBy: cancelledBy,
      cancelReason: cancelReason,
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

  static RecordedBy? _parseRecordedBy(Object? raw) {
    if (raw is! Map) return null;
    final uid = raw['uid']?.toString().trim();
    final name = raw['name']?.toString().trim();
    final internalRole = (raw['internal_role'] ?? raw['internalRole'])
        ?.toString()
        .trim();
    if (uid == null || uid.isEmpty || name == null || name.isEmpty) return null;
    return RecordedBy(
      uid: uid,
      name: name,
      internalRole: internalRole?.isNotEmpty == true ? internalRole! : 'condutor',
    );
  }

  static ProfessionalIdentity? _parseProfessional(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name']?.toString().trim();
    final regTypeRaw = (raw['registration_type'] ?? raw['registrationType'])
        ?.toString()
        .trim();
    final regNum = (raw['registration_number'] ?? raw['registrationNumber'])
        ?.toString()
        .trim();
    final clinic = raw['clinic']?.toString().trim();
    final specialty = raw['specialty']?.toString().trim();

    if (name == null || name.isEmpty || regNum == null || regNum.isEmpty) {
      return null;
    }
    final regType = ProfessionalRegistrationType.fromWire(regTypeRaw ?? '') ??
        ProfessionalRegistrationType.other;
    return ProfessionalIdentity(
      name: name,
      registrationType: regType,
      registrationNumber: regNum,
      clinic: clinic?.isNotEmpty == true ? clinic! : 'Clínica Externa',
      specialty: specialty,
    );
  }

  static OperationalImpact? _parseOperationalImpact(Object? raw) {
    if (raw is! Map) return null;
    final levelRaw = raw['level']?.toString().trim();
    final desc = raw['description']?.toString().trim() ?? '';
    if (desc.isEmpty) return null;

    final level = OperationalImpactLevel.values.firstWhere(
      (l) => l.wireName == levelRaw,
      orElse: () => OperationalImpactLevel.none,
    );
    final rawRestrictions = raw['restrictions_issued'] ??
        raw['restrictionsIssued'];
    final restrictions = rawRestrictions is List
        ? rawRestrictions.map((e) => e.toString()).toList()
        : <String>[];
    return OperationalImpact(
      level: level,
      description: desc,
      restrictionsIssued: restrictions,
    );
  }
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
