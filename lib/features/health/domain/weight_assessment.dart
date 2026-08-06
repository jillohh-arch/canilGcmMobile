import 'health_v1_enums.dart';
import 'health_v1_models.dart' show HealthDomainException, RecordedBy, WeightKg;

enum WeightDocumentSourceShape {
  deployedV1,
  recognizedLegacyWeb,
  recognizedLegacyDogUpdate,
  targetV2,
}

enum WeightDerivedField { recordType, originRecordType, status, revision }

enum WeightDocumentDiagnosticCode {
  missingCanonicalRecorder,
  legacySourceShape,
  derivedLegacySimple,
  derivedStatusValid,
  derivedRevisionOne,
  unknownEnum,
  unsupportedSchema,
  hybridV1V2,
  malformedTimestamp,
  malformedWeight,
  embeddedDogIdMismatch,
  forbiddenTargetFieldOnQuick,
  incompleteOfficialDetails,
  legacyPrecisionPreserved,
  legacyTimestampFallbackAvailable,
  malformedRecorder,
  malformedSchemaVersion,
  unknownLegacyShape,
  nonCanonicalCollection,
}

final class WeightDocumentDiagnostic {
  const WeightDocumentDiagnostic({
    required this.code,
    this.field,
    this.safeRaw,
  });

  final WeightDocumentDiagnosticCode code;
  final String? field;

  /// Somente valores técnicos não sensíveis, como schema ou enum desconhecido.
  final String? safeRaw;

  @override
  bool operator ==(Object other) =>
      other is WeightDocumentDiagnostic &&
      other.code == code &&
      other.field == field &&
      other.safeRaw == safeRaw;

  @override
  int get hashCode => Object.hash(code, field, safeRaw);
}

final class WeightCompatibilityMetadata {
  WeightCompatibilityMetadata({
    required this.sourceShape,
    required this.persistedSchemaVersion,
    this.schemaVersionDerived = false,
    Set<WeightDerivedField> derivedFields = const {},
    this.orderingFallbackAt,
    String? legacyActorReference,
    List<WeightDocumentDiagnostic> diagnostics = const [],
  }) : derivedFields = Set.unmodifiable(derivedFields),
       legacyActorReference = _optional(legacyActorReference),
       diagnostics = List.unmodifiable(diagnostics);

  final WeightDocumentSourceShape sourceShape;
  final int? persistedSchemaVersion;
  final bool schemaVersionDerived;
  final Set<WeightDerivedField> derivedFields;
  final DateTime? orderingFallbackAt;
  final String? legacyActorReference;
  final List<WeightDocumentDiagnostic> diagnostics;

  bool get isReadOnlyCompatibility =>
      sourceShape != WeightDocumentSourceShape.targetV2;
}

final class WeightRecorder {
  WeightRecorder({
    required String uid,
    required String name,
    required String internalRole,
  }) : uid = _required(uid, 'recorded_by.uid'),
       name = _required(name, 'recorded_by.name'),
       internalRole = _required(internalRole, 'recorded_by.internal_role');

  factory WeightRecorder.fromRecordedBy(RecordedBy value) => WeightRecorder(
    uid: value.uid,
    name: value.name,
    internalRole: value.internalRole,
  );

  final String uid;
  final String name;
  final String internalRole;

  RecordedBy toRecordedBy() =>
      RecordedBy(uid: uid, name: name, internalRole: internalRole);

  @override
  bool operator ==(Object other) =>
      other is WeightRecorder &&
      other.uid == uid &&
      other.name == name &&
      other.internalRole == internalRole;

  @override
  int get hashCode => Object.hash(uid, name, internalRole);
}

final class WeightBodyConditionScore {
  WeightBodyConditionScore({required this.value, required this.source}) {
    if (value < 1 || value > 5) {
      throw const HealthDomainException(
        'invalid_weight_bcs',
        'bcs target deve estar entre 1 e 5',
      );
    }
    if (source.isAbsent) {
      throw const HealthDomainException(
        'missing_weight_bcs_source',
        'bcs_source é obrigatório quando bcs existe',
      );
    }
  }

  final int value;
  final ParsedHealthEnum<WeightBcsSource> source;
}

final class WeightAttachmentReference {
  WeightAttachmentReference({required String healthDocumentId, String? caption})
    : healthDocumentId = _required(
        healthDocumentId,
        'attachment.health_document_id',
      ),
      caption = _optional(caption);

  final String healthDocumentId;
  final String? caption;
}

final class WeightClinicalLink {
  WeightClinicalLink({required String entityType, required String entityId})
    : entityType = _required(entityType, 'clinical_link.entity_type'),
      entityId = _required(entityId, 'clinical_link.entity_id');

  final String entityType;
  final String entityId;
}

final class WeightOfficialDetails {
  WeightOfficialDetails({
    required this.informationSource,
    required this.location,
    required this.measurementCondition,
    this.equipmentState = const ParsedHealthEnum<WeightEquipmentState>.absent(),
    this.readingQuality = const ParsedHealthEnum<WeightReadingQuality>.absent(),
    this.bodyConditionScore,
    String? locationOtherDescription,
    String? conditionOtherDescription,
    String? scaleIdentifier,
  }) : locationOtherDescription = _optional(locationOtherDescription),
       conditionOtherDescription = _optional(conditionOtherDescription),
       scaleIdentifier = _optional(scaleIdentifier) {
    if (informationSource.isAbsent ||
        location.isAbsent ||
        measurementCondition.isAbsent) {
      throw const HealthDomainException(
        'incomplete_official_weight_details',
        'Pesagem Oficial exige fonte, local e condição',
      );
    }
    if (location.value == WeightLocation.other &&
        this.locationOtherDescription == null) {
      throw const HealthDomainException(
        'missing_weight_location_other_description',
        'location=other exige descrição',
      );
    }
    if (measurementCondition.value == WeightMeasurementCondition.other &&
        this.conditionOtherDescription == null) {
      throw const HealthDomainException(
        'missing_weight_condition_other_description',
        'measurement_condition=other exige descrição',
      );
    }
  }

  final ParsedHealthEnum<WeightInformationSource> informationSource;
  final ParsedHealthEnum<WeightLocation> location;
  final ParsedHealthEnum<WeightMeasurementCondition> measurementCondition;
  final ParsedHealthEnum<WeightEquipmentState> equipmentState;
  final ParsedHealthEnum<WeightReadingQuality> readingQuality;
  final WeightBodyConditionScore? bodyConditionScore;
  final String? locationOtherDescription;
  final String? conditionOtherDescription;
  final String? scaleIdentifier;
}

/// Aggregate de leitura. O construtor sem nome preserva a API v1 existente.
final class WeightAssessment {
  WeightAssessment({
    required String id,
    required String dogId,
    required this.weight,
    required this.measuredAt,
    required RecordedBy recordedBy,
    required this.schemaVersion,
  }) : entityId = _required(id, 'id'),
       dogId = _required(dogId, 'dog_id'),
       recorder = WeightRecorder.fromRecordedBy(recordedBy),
       recordType = WeightRecordTypeWire.parse('legacy_simple'),
       originRecordType = WeightRecordTypeWire.parse('legacy_simple'),
       status = WeightAssessmentStatusWire.parse('valid'),
       revision = 1,
       recordedAt = null,
       officialDetails = null,
       attachmentReferences = const [],
       clinicalLinks = const [],
       context = null,
       notes = null,
       compatibility = WeightCompatibilityMetadata(
         sourceShape: WeightDocumentSourceShape.deployedV1,
         persistedSchemaVersion: schemaVersion,
         derivedFields: const {
           WeightDerivedField.recordType,
           WeightDerivedField.originRecordType,
           WeightDerivedField.status,
           WeightDerivedField.revision,
         },
       ) {
    _validateCommon();
  }

  WeightAssessment._({
    required this.entityId,
    required this.dogId,
    required this.weight,
    required this.measuredAt,
    required this.recordType,
    required this.originRecordType,
    required this.status,
    required this.revision,
    required this.schemaVersion,
    required this.recordedAt,
    required this.recorder,
    required this.officialDetails,
    required List<WeightAttachmentReference> attachmentReferences,
    required List<WeightClinicalLink> clinicalLinks,
    required this.context,
    required this.notes,
    required this.compatibility,
  }) : attachmentReferences = List.unmodifiable(attachmentReferences),
       clinicalLinks = List.unmodifiable(clinicalLinks) {
    _validateCommon();
  }

  factory WeightAssessment.compatibility({
    required String entityId,
    required String dogId,
    required WeightKg weight,
    required DateTime measuredAt,
    required int schemaVersion,
    required WeightRecorder? recorder,
    required WeightCompatibilityMetadata compatibility,
    DateTime? recordedAt,
    String? context,
    String? notes,
  }) => WeightAssessment._(
    entityId: _required(entityId, 'entity_id'),
    dogId: _required(dogId, 'dog_id'),
    weight: weight,
    measuredAt: measuredAt,
    recordType: WeightRecordTypeWire.parse('legacy_simple'),
    originRecordType: WeightRecordTypeWire.parse('legacy_simple'),
    status: WeightAssessmentStatusWire.parse('valid'),
    revision: 1,
    schemaVersion: schemaVersion,
    recordedAt: recordedAt,
    recorder: recorder,
    officialDetails: null,
    attachmentReferences: const [],
    clinicalLinks: const [],
    context: _optional(context),
    notes: _optional(notes),
    compatibility: compatibility,
  );

  factory WeightAssessment.targetV2({
    required String entityId,
    required String dogId,
    required WeightKg weight,
    required DateTime measuredAt,
    required DateTime recordedAt,
    required WeightRecorder recorder,
    required ParsedHealthEnum<WeightRecordType> recordType,
    required ParsedHealthEnum<WeightRecordType> originRecordType,
    required ParsedHealthEnum<WeightAssessmentStatus> status,
    required int revision,
    required WeightOfficialDetails? officialDetails,
    List<WeightAttachmentReference> attachmentReferences = const [],
    List<WeightClinicalLink> clinicalLinks = const [],
    String? context,
    String? notes,
    List<WeightDocumentDiagnostic> diagnostics = const [],
  }) => WeightAssessment._(
    entityId: _required(entityId, 'entity_id'),
    dogId: _required(dogId, 'dog_id'),
    weight: weight,
    measuredAt: measuredAt,
    recordType: recordType,
    originRecordType: originRecordType,
    status: status,
    revision: revision,
    schemaVersion: 2,
    recordedAt: recordedAt,
    recorder: recorder,
    officialDetails: officialDetails,
    attachmentReferences: attachmentReferences,
    clinicalLinks: clinicalLinks,
    context: _optional(context),
    notes: _optional(notes),
    compatibility: WeightCompatibilityMetadata(
      sourceShape: WeightDocumentSourceShape.targetV2,
      persistedSchemaVersion: 2,
      diagnostics: diagnostics,
    ),
  );

  final String entityId;
  String get id => entityId;
  final String dogId;
  final WeightKg weight;
  double get weightKg => weight.value;
  final DateTime measuredAt;
  final DateTime? recordedAt;
  final WeightRecorder? recorder;

  /// Compatibilidade temporária com o model anterior; somente para v1 factual.
  @Deprecated('Use recorder, que representa corretamente autoria ausente.')
  RecordedBy get recordedBy {
    final factual = recorder;
    if (factual == null) {
      throw StateError('recorded_by não existe neste shape legado');
    }
    return factual.toRecordedBy();
  }

  final ParsedHealthEnum<WeightRecordType> recordType;
  final ParsedHealthEnum<WeightRecordType> originRecordType;
  final ParsedHealthEnum<WeightAssessmentStatus> status;
  final int revision;
  final int schemaVersion;
  final WeightOfficialDetails? officialDetails;
  final List<WeightAttachmentReference> attachmentReferences;
  final List<WeightClinicalLink> clinicalLinks;
  final String? context;
  final String? notes;
  final WeightCompatibilityMetadata compatibility;
  List<WeightDocumentDiagnostic> get diagnostics => compatibility.diagnostics;

  void _validateCommon() {
    if (schemaVersion <= 0) {
      throw const HealthDomainException(
        'invalid_schema_version',
        'schema_version deve ser positivo',
      );
    }
    if (revision < 1) {
      throw const HealthDomainException(
        'invalid_weight_revision',
        'revision deve ser positivo',
      );
    }
    if (compatibility.sourceShape == WeightDocumentSourceShape.targetV2) {
      if (weight.value < 1 ||
          weight.value > 100 ||
          !_hasExactTenths(weight.value)) {
        throw const HealthDomainException(
          'invalid_target_weight',
          'weight_kg v2 exige valor de 1.0 a 100.0 com uma casa decimal',
        );
      }
      if (recordType.isAbsent || originRecordType.isAbsent || status.isAbsent) {
        throw const HealthDomainException(
          'incomplete_weight_v2_discriminators',
          'Documento v2 exige discriminadores completos',
        );
      }
      if (recordType.value == WeightRecordType.legacySimple ||
          originRecordType.value == WeightRecordType.legacySimple) {
        throw const HealthDomainException(
          'legacy_simple_not_target_serializable',
          'legacy_simple não é tipo factual target',
        );
      }
      if (recordType.value == WeightRecordType.official &&
          officialDetails == null) {
        throw const HealthDomainException(
          'incomplete_official_weight_details',
          'Pesagem Official exige detalhes completos',
        );
      }
      if (recordType.value == WeightRecordType.quick &&
          (officialDetails != null || clinicalLinks.isNotEmpty)) {
        throw const HealthDomainException(
          'forbidden_quick_weight_details',
          'Pesagem Quick contém campos exclusivos de Official',
        );
      }
      if (recordType.value == WeightRecordType.quick &&
          originRecordType.value != WeightRecordType.quick) {
        throw const HealthDomainException(
          'invalid_quick_weight_origin',
          'Pesagem Quick deve ter origin_record_type=quick',
        );
      }
      final maxAttachments = recordType.value == WeightRecordType.quick ? 3 : 5;
      if (attachmentReferences.length > maxAttachments) {
        throw const HealthDomainException(
          'too_many_weight_attachments',
          'Quantidade de anexos excede o limite do tipo',
        );
      }
      if (attachmentReferences
              .map((item) => item.healthDocumentId)
              .toSet()
              .length !=
          attachmentReferences.length) {
        throw const HealthDomainException(
          'duplicate_weight_attachment',
          'Um HealthDocument não pode ser referenciado duas vezes',
        );
      }
    }
  }

  void validateMeasuredAt({required DateTime referenceTime}) {
    if (measuredAt.isAfter(referenceTime)) {
      throw const HealthDomainException(
        'future_measured_at',
        'measured_at não pode estar no futuro',
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      other is WeightAssessment &&
      other.entityId == entityId &&
      other.dogId == dogId &&
      other.weight == weight &&
      other.measuredAt == measuredAt &&
      other.recorder == recorder &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode =>
      Object.hash(entityId, dogId, weight, measuredAt, recorder, schemaVersion);
}

bool _hasExactTenths(double value) {
  final tenths = value * 10;
  return (tenths - tenths.round()).abs() <= 1e-9;
}

String _required(String value, String field) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw HealthDomainException('missing_$field', '$field é obrigatório');
  }
  return normalized;
}

String? _optional(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}
