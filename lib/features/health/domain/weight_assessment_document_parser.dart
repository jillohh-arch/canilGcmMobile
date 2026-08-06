import 'health_v1_enums.dart';
import 'health_v1_models.dart' show HealthDomainException, WeightKg;
import 'weight_assessment.dart';

enum WeightAssessmentParseResultKind { success, malformed, unsupported }

final class WeightAssessmentParseResult {
  WeightAssessmentParseResult._({
    required this.kind,
    required this.assessment,
    required List<WeightDocumentDiagnostic> diagnostics,
    required this.unsupportedSchemaVersion,
  }) : diagnostics = List.unmodifiable(diagnostics);

  factory WeightAssessmentParseResult.success(WeightAssessment value) =>
      WeightAssessmentParseResult._(
        kind: WeightAssessmentParseResultKind.success,
        assessment: value,
        diagnostics: value.diagnostics,
        unsupportedSchemaVersion: null,
      );

  factory WeightAssessmentParseResult.malformed(
    List<WeightDocumentDiagnostic> diagnostics,
  ) => WeightAssessmentParseResult._(
    kind: WeightAssessmentParseResultKind.malformed,
    assessment: null,
    diagnostics: diagnostics,
    unsupportedSchemaVersion: null,
  );

  factory WeightAssessmentParseResult.unsupported(int version) =>
      WeightAssessmentParseResult._(
        kind: WeightAssessmentParseResultKind.unsupported,
        assessment: null,
        diagnostics: [
          WeightDocumentDiagnostic(
            code: WeightDocumentDiagnosticCode.unsupportedSchema,
            field: 'schema_version',
            safeRaw: '$version',
          ),
        ],
        unsupportedSchemaVersion: version,
      );

  final WeightAssessmentParseResultKind kind;
  final WeightAssessment? assessment;
  final List<WeightDocumentDiagnostic> diagnostics;
  final int? unsupportedSchemaVersion;
  bool get isSuccess => kind == WeightAssessmentParseResultKind.success;
}

abstract final class WeightAssessmentDocumentParser {
  WeightAssessmentDocumentParser._();

  static const _targetFields = {
    'record_type',
    'origin_record_type',
    'status',
    'revision',
    'recorded_at',
    'information_source',
    'location',
    'measurement_condition',
    'equipment_state',
    'reading_quality',
    'bcs',
    'bcs_source',
    'attachment_refs',
    'clinical_links',
  };

  static const _officialOnlyFields = {
    'information_source',
    'location',
    'location_other_description',
    'measurement_condition',
    'condition_other_description',
    'equipment_state',
    'reading_quality',
    'scale_identifier',
    'bcs',
    'bcs_source',
    'clinical_links',
  };

  static const _targetStringFields = {
    'record_type',
    'origin_record_type',
    'status',
    'information_source',
    'location',
    'location_other_description',
    'measurement_condition',
    'condition_other_description',
    'equipment_state',
    'reading_quality',
    'scale_identifier',
    'bcs_source',
    'context',
    'notes',
  };

  static WeightAssessmentParseResult parse({
    required String entityId,
    required String dogId,
    required Map<String, Object?> data,
    String sourceCollection = 'weight_records',
  }) {
    if (sourceCollection != 'weight_records') {
      return WeightAssessmentParseResult.malformed(const [
        WeightDocumentDiagnostic(
          code: WeightDocumentDiagnosticCode.nonCanonicalCollection,
          field: 'source_collection',
        ),
      ]);
    }
    if (entityId.trim().isEmpty || dogId.trim().isEmpty) {
      return WeightAssessmentParseResult.malformed(const [
        WeightDocumentDiagnostic(
          code: WeightDocumentDiagnosticCode.unknownLegacyShape,
          field: 'identity',
        ),
      ]);
    }
    final identityIssue = _embeddedDogIdIssue(dogId, data);
    if (identityIssue != null) {
      return WeightAssessmentParseResult.malformed([identityIssue]);
    }

    if (!data.containsKey('schema_version')) {
      if (_containsAny(data, _targetFields)) {
        return WeightAssessmentParseResult.malformed(const [
          WeightDocumentDiagnostic(
            code: WeightDocumentDiagnosticCode.hybridV1V2,
            field: 'schema_version',
          ),
        ]);
      }
      return _parseRecognizedLegacy(
        entityId: entityId,
        dogId: dogId,
        data: data,
      );
    }

    final schema = _strictInteger(data['schema_version']);
    if (schema == null || schema < 1) {
      return WeightAssessmentParseResult.malformed(const [
        WeightDocumentDiagnostic(
          code: WeightDocumentDiagnosticCode.malformedSchemaVersion,
          field: 'schema_version',
        ),
      ]);
    }
    if (schema > 2) return WeightAssessmentParseResult.unsupported(schema);
    if (schema == 1) {
      if (_containsAny(data, _targetFields)) {
        return WeightAssessmentParseResult.malformed(const [
          WeightDocumentDiagnostic(
            code: WeightDocumentDiagnosticCode.hybridV1V2,
            field: 'schema_version',
          ),
        ]);
      }
      return _parseDeployedV1(entityId: entityId, dogId: dogId, data: data);
    }
    return _parseTargetV2(entityId: entityId, dogId: dogId, data: data);
  }

  static WeightAssessmentParseResult _parseDeployedV1({
    required String entityId,
    required String dogId,
    required Map<String, Object?> data,
  }) {
    final diagnostics = _legacyBridgeDiagnostics();
    final weight = _historicalWeight(data['weight_kg'], diagnostics);
    if (weight == null) {
      return WeightAssessmentParseResult.malformed([
        ...diagnostics,
        const WeightDocumentDiagnostic(
          code: WeightDocumentDiagnosticCode.malformedWeight,
          field: 'weight_kg',
        ),
      ]);
    }
    final measuredAt = _dateTime(data['measured_at']);
    if (measuredAt == null) {
      return WeightAssessmentParseResult.malformed([
        ...diagnostics,
        const WeightDocumentDiagnostic(
          code: WeightDocumentDiagnosticCode.malformedTimestamp,
          field: 'measured_at',
        ),
      ]);
    }
    final recorder = _recorder(data['recorded_by']);
    if (recorder == null) {
      return WeightAssessmentParseResult.malformed([
        ...diagnostics,
        const WeightDocumentDiagnostic(
          code: WeightDocumentDiagnosticCode.malformedRecorder,
          field: 'recorded_by',
        ),
      ]);
    }
    final context = _optionalString(data['context']);
    if (data['context'] != null &&
        (context == null ||
            !const {
              'routine',
              'clinical',
              'pre_op',
              'post_op',
            }.contains(context))) {
      return WeightAssessmentParseResult.malformed(const [
        WeightDocumentDiagnostic(
          code: WeightDocumentDiagnosticCode.unknownLegacyShape,
          field: 'context',
        ),
      ]);
    }
    final notes = _optionalString(data['notes']);
    if (data['notes'] != null && data['notes'] is! String) {
      return WeightAssessmentParseResult.malformed(const [
        WeightDocumentDiagnostic(
          code: WeightDocumentDiagnosticCode.unknownLegacyShape,
          field: 'notes',
        ),
      ]);
    }
    final createdAt = _dateTime(data['created_at']);
    if (createdAt != null) {
      diagnostics.add(
        const WeightDocumentDiagnostic(
          code: WeightDocumentDiagnosticCode.legacyTimestampFallbackAvailable,
          field: 'created_at',
        ),
      );
    }
    final value = WeightAssessment.compatibility(
      entityId: entityId,
      dogId: dogId,
      weight: WeightKg(weight),
      measuredAt: measuredAt,
      schemaVersion: 1,
      recorder: recorder,
      context: context,
      notes: notes,
      compatibility: WeightCompatibilityMetadata(
        sourceShape: WeightDocumentSourceShape.deployedV1,
        persistedSchemaVersion: 1,
        derivedFields: _legacyDerivedFields,
        orderingFallbackAt: createdAt,
        diagnostics: diagnostics,
      ),
    );
    return WeightAssessmentParseResult.success(value);
  }

  static WeightAssessmentParseResult _parseRecognizedLegacy({
    required String entityId,
    required String dogId,
    required Map<String, Object?> data,
  }) {
    final isWeb = data['measured_by'] != null && data['performed_by'] != null;
    final isDogUpdate =
        data['performed_by'] != null &&
        data['measured_by'] == null &&
        data['context'] == null &&
        data['notes'] == null;
    if (!isWeb && !isDogUpdate) {
      return WeightAssessmentParseResult.malformed(const [
        WeightDocumentDiagnostic(
          code: WeightDocumentDiagnosticCode.unknownLegacyShape,
          field: 'schema_version',
        ),
      ]);
    }
    if (data['recorded_by'] != null) {
      return WeightAssessmentParseResult.malformed(const [
        WeightDocumentDiagnostic(
          code: WeightDocumentDiagnosticCode.unknownLegacyShape,
          field: 'recorded_by',
        ),
      ]);
    }
    final diagnostics = _legacyBridgeDiagnostics()
      ..addAll(const [
        WeightDocumentDiagnostic(
          code: WeightDocumentDiagnosticCode.legacySourceShape,
        ),
        WeightDocumentDiagnostic(
          code: WeightDocumentDiagnosticCode.missingCanonicalRecorder,
          field: 'recorded_by',
        ),
      ]);
    final weight = _historicalWeight(data['weight_kg'], diagnostics);
    final measuredAt = _dateTime(data['measured_at']);
    if (weight == null || measuredAt == null) {
      return WeightAssessmentParseResult.malformed([
        ...diagnostics,
        if (weight == null)
          const WeightDocumentDiagnostic(
            code: WeightDocumentDiagnosticCode.malformedWeight,
            field: 'weight_kg',
          ),
        if (measuredAt == null)
          const WeightDocumentDiagnostic(
            code: WeightDocumentDiagnosticCode.malformedTimestamp,
            field: 'measured_at',
          ),
      ]);
    }
    final createdAt = _dateTime(data['created_at']);
    if (createdAt != null) {
      diagnostics.add(
        const WeightDocumentDiagnostic(
          code: WeightDocumentDiagnosticCode.legacyTimestampFallbackAvailable,
          field: 'created_at',
        ),
      );
    }
    final actor = _optionalString(data['measured_by'] ?? data['performed_by']);
    final value = WeightAssessment.compatibility(
      entityId: entityId,
      dogId: dogId,
      weight: WeightKg(weight),
      measuredAt: measuredAt,
      schemaVersion: 1,
      recorder: null,
      context: _optionalString(data['context']),
      notes: _optionalString(data['notes']),
      compatibility: WeightCompatibilityMetadata(
        sourceShape: isWeb
            ? WeightDocumentSourceShape.recognizedLegacyWeb
            : WeightDocumentSourceShape.recognizedLegacyDogUpdate,
        persistedSchemaVersion: null,
        schemaVersionDerived: true,
        derivedFields: _legacyDerivedFields,
        orderingFallbackAt: createdAt,
        legacyActorReference: actor,
        diagnostics: diagnostics,
      ),
    );
    return WeightAssessmentParseResult.success(value);
  }

  static WeightAssessmentParseResult _parseTargetV2({
    required String entityId,
    required String dogId,
    required Map<String, Object?> data,
  }) {
    final diagnostics = <WeightDocumentDiagnostic>[];
    for (final field in _targetStringFields) {
      if (data.containsKey(field) &&
          data[field] != null &&
          data[field] is! String) {
        return WeightAssessmentParseResult.malformed([
          WeightDocumentDiagnostic(
            code: WeightDocumentDiagnosticCode.unknownLegacyShape,
            field: field,
          ),
        ]);
      }
    }
    final embeddedDogId = _optionalString(data['dog_id'] ?? data['dogId']);
    final weight = _targetWeight(data['weight_kg']);
    final measuredAt = _dateTime(data['measured_at']);
    final recordedAt = _dateTime(data['recorded_at']);
    final recorder = _recorder(data['recorded_by']);
    final revision = _strictInteger(data['revision']);
    final recordType = WeightRecordTypeWire.parse(data['record_type']);
    final originType = WeightRecordTypeWire.parse(data['origin_record_type']);
    final status = WeightAssessmentStatusWire.parse(data['status']);

    if (embeddedDogId == null ||
        weight == null ||
        measuredAt == null ||
        recordedAt == null ||
        recorder == null ||
        revision == null ||
        revision < 1 ||
        recordType.isAbsent ||
        originType.isAbsent ||
        status.isAbsent ||
        recordType.value == WeightRecordType.legacySimple ||
        originType.value == WeightRecordType.legacySimple) {
      return WeightAssessmentParseResult.malformed([
        if (embeddedDogId == null)
          const WeightDocumentDiagnostic(
            code: WeightDocumentDiagnosticCode.unknownLegacyShape,
            field: 'dog_id',
          ),
        if (weight == null)
          const WeightDocumentDiagnostic(
            code: WeightDocumentDiagnosticCode.malformedWeight,
            field: 'weight_kg',
          ),
        if (measuredAt == null)
          const WeightDocumentDiagnostic(
            code: WeightDocumentDiagnosticCode.malformedTimestamp,
            field: 'measured_at',
          ),
        if (recordedAt == null)
          const WeightDocumentDiagnostic(
            code: WeightDocumentDiagnosticCode.malformedTimestamp,
            field: 'recorded_at',
          ),
        if (recorder == null)
          const WeightDocumentDiagnostic(
            code: WeightDocumentDiagnosticCode.malformedRecorder,
            field: 'recorded_by',
          ),
        if (revision == null || revision < 1)
          const WeightDocumentDiagnostic(
            code: WeightDocumentDiagnosticCode.unknownLegacyShape,
            field: 'revision',
          ),
        if (recordType.isAbsent ||
            recordType.value == WeightRecordType.legacySimple)
          const WeightDocumentDiagnostic(
            code: WeightDocumentDiagnosticCode.unknownLegacyShape,
            field: 'record_type',
          ),
        if (originType.isAbsent ||
            originType.value == WeightRecordType.legacySimple)
          const WeightDocumentDiagnostic(
            code: WeightDocumentDiagnosticCode.unknownLegacyShape,
            field: 'origin_record_type',
          ),
        if (status.isAbsent)
          const WeightDocumentDiagnostic(
            code: WeightDocumentDiagnosticCode.unknownLegacyShape,
            field: 'status',
          ),
      ]);
    }

    for (final parsed in [recordType, originType, status]) {
      if (parsed.isUnknown) {
        diagnostics.add(
          WeightDocumentDiagnostic(
            code: WeightDocumentDiagnosticCode.unknownEnum,
            safeRaw: parsed.raw,
          ),
        );
      }
    }

    WeightOfficialDetails? officialDetails;
    if (recordType.value == WeightRecordType.quick &&
        _containsAny(data, _officialOnlyFields)) {
      return WeightAssessmentParseResult.malformed(const [
        WeightDocumentDiagnostic(
          code: WeightDocumentDiagnosticCode.forbiddenTargetFieldOnQuick,
          field: 'record_type',
        ),
      ]);
    }
    if (recordType.value == WeightRecordType.official) {
      final parsedDetails = _parseOfficialDetails(data, diagnostics);
      if (parsedDetails == null) {
        return WeightAssessmentParseResult.malformed([
          ...diagnostics,
          const WeightDocumentDiagnostic(
            code: WeightDocumentDiagnosticCode.incompleteOfficialDetails,
          ),
        ]);
      }
      officialDetails = parsedDetails;
    }

    final attachments = _parseAttachments(data['attachment_refs']);
    final links = _parseClinicalLinks(data['clinical_links']);
    if (attachments == null || links == null) {
      return WeightAssessmentParseResult.malformed(const [
        WeightDocumentDiagnostic(
          code: WeightDocumentDiagnosticCode.unknownLegacyShape,
          field: 'references',
        ),
      ]);
    }
    try {
      return WeightAssessmentParseResult.success(
        WeightAssessment.targetV2(
          entityId: entityId,
          dogId: dogId,
          weight: WeightKg(weight),
          measuredAt: measuredAt,
          recordedAt: recordedAt,
          recorder: recorder,
          recordType: recordType,
          originRecordType: originType,
          status: status,
          revision: revision,
          officialDetails: officialDetails,
          attachmentReferences: attachments,
          clinicalLinks: links,
          context: _optionalString(data['context']),
          notes: _optionalString(data['notes']),
          diagnostics: diagnostics,
        ),
      );
    } on HealthDomainException {
      return WeightAssessmentParseResult.malformed([
        ...diagnostics,
        const WeightDocumentDiagnostic(
          code: WeightDocumentDiagnosticCode.unknownLegacyShape,
          field: 'target_v2',
        ),
      ]);
    }
  }

  static WeightOfficialDetails? _parseOfficialDetails(
    Map<String, Object?> data,
    List<WeightDocumentDiagnostic> diagnostics,
  ) {
    final source = WeightInformationSourceWire.parse(
      data['information_source'],
    );
    final location = WeightLocationWire.parse(data['location']);
    final condition = WeightMeasurementConditionWire.parse(
      data['measurement_condition'],
    );
    final equipment = WeightEquipmentStateWire.parse(data['equipment_state']);
    final quality = WeightReadingQualityWire.parse(data['reading_quality']);
    if (source.isAbsent || location.isAbsent || condition.isAbsent) return null;
    for (final parsed in [source, location, condition, equipment, quality]) {
      if (parsed.isUnknown) {
        diagnostics.add(
          WeightDocumentDiagnostic(
            code: WeightDocumentDiagnosticCode.unknownEnum,
            safeRaw: parsed.raw,
          ),
        );
      }
    }
    WeightBodyConditionScore? bcs;
    if (data.containsKey('bcs') || data.containsKey('bcs_source')) {
      final value = _strictInteger(data['bcs']);
      final bcsSource = WeightBcsSourceWire.parse(data['bcs_source']);
      if (value == null || value < 1 || value > 5 || bcsSource.isAbsent) {
        return null;
      }
      if (bcsSource.isUnknown) {
        diagnostics.add(
          WeightDocumentDiagnostic(
            code: WeightDocumentDiagnosticCode.unknownEnum,
            field: 'bcs_source',
            safeRaw: bcsSource.raw,
          ),
        );
      }
      bcs = WeightBodyConditionScore(value: value, source: bcsSource);
    }
    try {
      return WeightOfficialDetails(
        informationSource: source,
        location: location,
        measurementCondition: condition,
        equipmentState: equipment,
        readingQuality: quality,
        bodyConditionScore: bcs,
        locationOtherDescription: _optionalString(
          data['location_other_description'],
        ),
        conditionOtherDescription: _optionalString(
          data['condition_other_description'],
        ),
        scaleIdentifier: _optionalString(data['scale_identifier']),
      );
    } on HealthDomainException {
      return null;
    }
  }

  static List<WeightAttachmentReference>? _parseAttachments(Object? raw) {
    if (raw == null) return const [];
    if (raw is! List) return null;
    final values = <WeightAttachmentReference>[];
    try {
      for (final item in raw) {
        if (item is! Map) return null;
        final map = Map<String, Object?>.from(item);
        final id = _optionalString(map['health_document_id']);
        if (id == null) return null;
        values.add(
          WeightAttachmentReference(
            healthDocumentId: id,
            caption: _optionalString(map['caption']),
          ),
        );
      }
    } on HealthDomainException {
      return null;
    }
    return values;
  }

  static List<WeightClinicalLink>? _parseClinicalLinks(Object? raw) {
    if (raw == null) return const [];
    if (raw is! List) return null;
    final values = <WeightClinicalLink>[];
    try {
      for (final item in raw) {
        if (item is! Map) return null;
        final map = Map<String, Object?>.from(item);
        final type = _optionalString(map['entity_type']);
        final id = _optionalString(map['entity_id']);
        if (type == null || id == null) return null;
        values.add(WeightClinicalLink(entityType: type, entityId: id));
      }
    } on HealthDomainException {
      return null;
    }
    return values;
  }

  static WeightRecorder? _recorder(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, Object?>.from(raw);
    final uid = _optionalString(map['uid']);
    final name = _optionalString(map['name']);
    final role = _optionalString(map['internal_role']);
    if (uid == null ||
        name == null ||
        role == null ||
        map.containsKey('email')) {
      return null;
    }
    try {
      return WeightRecorder(uid: uid, name: name, internalRole: role);
    } on HealthDomainException {
      return null;
    }
  }

  static WeightDocumentDiagnostic? _embeddedDogIdIssue(
    String dogId,
    Map<String, Object?> data,
  ) {
    for (final key in const ['dogId', 'dog_id']) {
      if (!data.containsKey(key)) continue;
      final embedded = _optionalString(data[key]);
      if (embedded == null || embedded != dogId.trim()) {
        return WeightDocumentDiagnostic(
          code: WeightDocumentDiagnosticCode.embeddedDogIdMismatch,
          field: key,
        );
      }
    }
    return null;
  }

  static num? _historicalWeight(
    Object? raw,
    List<WeightDocumentDiagnostic> diagnostics,
  ) {
    if (raw is! num || !raw.isFinite || raw <= 0 || raw > 100) return null;
    if (!_hasExactTenths(raw.toDouble())) {
      diagnostics.add(
        const WeightDocumentDiagnostic(
          code: WeightDocumentDiagnosticCode.legacyPrecisionPreserved,
          field: 'weight_kg',
        ),
      );
    }
    return raw;
  }

  static num? _targetWeight(Object? raw) {
    if (raw is! num || !raw.isFinite || raw < 1 || raw > 100) return null;
    return _hasExactTenths(raw.toDouble()) ? raw : null;
  }

  static int? _strictInteger(Object? raw) {
    if (raw is! num || !raw.isFinite) return null;
    final value = raw.toInt();
    return value == raw ? value : null;
  }

  static DateTime? _dateTime(Object? raw) {
    if (raw is DateTime) return raw;
    if (raw is Map) {
      final seconds = raw.containsKey('seconds')
          ? raw['seconds']
          : raw['_seconds'];
      final nanos = raw.containsKey('nanoseconds')
          ? raw['nanoseconds']
          : raw['_nanoseconds'] ?? 0;
      final secondsInt = _strictInteger(seconds);
      final nanosInt = _strictInteger(nanos);
      if (secondsInt == null ||
          nanosInt == null ||
          nanosInt < 0 ||
          nanosInt >= 1000000000) {
        return null;
      }
      final micros =
          BigInt.from(secondsInt) * BigInt.from(1000000) +
          BigInt.from(nanosInt ~/ 1000);
      if (!micros.isValidInt) return null;
      try {
        return DateTime.fromMicrosecondsSinceEpoch(micros.toInt(), isUtc: true);
      } on ArgumentError {
        return null;
      }
    }
    try {
      final converted = (raw as dynamic).toDate();
      return converted is DateTime ? converted : null;
    } catch (_) {
      return null;
    }
  }

  static bool _containsAny(Map<String, Object?> data, Set<String> fields) =>
      fields.any(data.containsKey);

  static String? _optionalString(Object? raw) {
    if (raw is! String) return null;
    final value = raw.trim();
    return value.isEmpty ? null : value;
  }

  static List<WeightDocumentDiagnostic> _legacyBridgeDiagnostics() => [
    const WeightDocumentDiagnostic(
      code: WeightDocumentDiagnosticCode.derivedLegacySimple,
      field: 'record_type',
    ),
    const WeightDocumentDiagnostic(
      code: WeightDocumentDiagnosticCode.derivedLegacySimple,
      field: 'origin_record_type',
    ),
    const WeightDocumentDiagnostic(
      code: WeightDocumentDiagnosticCode.derivedStatusValid,
      field: 'status',
    ),
    const WeightDocumentDiagnostic(
      code: WeightDocumentDiagnosticCode.derivedRevisionOne,
      field: 'revision',
    ),
  ];

  static const _legacyDerivedFields = {
    WeightDerivedField.recordType,
    WeightDerivedField.originRecordType,
    WeightDerivedField.status,
    WeightDerivedField.revision,
  };
}

bool _hasExactTenths(double value) {
  final tenths = value * 10;
  return (tenths - tenths.round()).abs() <= 1e-9;
}
