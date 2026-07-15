import 'dart:collection';

import 'health_v1_enums.dart';

final class HealthDomainException implements Exception {
  const HealthDomainException(this.code, this.message);

  final String code;
  final String message;

  @override
  bool operator ==(Object other) =>
      other is HealthDomainException &&
      other.code == code &&
      other.message == message;

  @override
  int get hashCode => Object.hash(code, message);

  @override
  String toString() => 'HealthDomainException($code): $message';
}

String _required(String value, String field) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw HealthDomainException('missing_$field', '$field é obrigatório');
  }
  return normalized;
}

Object? _freezeJsonLike(Object? value, Set<Object> activeContainers) {
  if (value == null || value is String || value is bool) {
    return value;
  }
  if (value is num) {
    if (!value.isFinite) {
      throw const HealthDomainException(
        'non_finite_json_number',
        'Payload clínico não aceita número não finito',
      );
    }
    return value;
  }
  if (value is DateTime) return value;
  if (value is Map) {
    if (!activeContainers.add(value)) {
      throw const HealthDomainException(
        'cyclic_json_structure',
        'Payload clínico não aceita referências cíclicas',
      );
    }
    final frozen = <String, Object?>{};
    try {
      for (final entry in value.entries) {
        if (entry.key is! String) {
          throw const HealthDomainException(
            'invalid_json_map_key',
            'Mapas clínicos aceitam somente chaves string',
          );
        }
        frozen[entry.key as String] = _freezeJsonLike(
          entry.value,
          activeContainers,
        );
      }
    } finally {
      activeContainers.remove(value);
    }
    return UnmodifiableMapView(frozen);
  }
  if (value is List) {
    if (!activeContainers.add(value)) {
      throw const HealthDomainException(
        'cyclic_json_structure',
        'Payload clínico não aceita referências cíclicas',
      );
    }
    try {
      return List<Object?>.unmodifiable(
        value.map((item) => _freezeJsonLike(item, activeContainers)),
      );
    } finally {
      activeContainers.remove(value);
    }
  }
  throw HealthDomainException(
    'unsupported_json_value',
    'Tipo ${value.runtimeType} não é suportado em payload clínico',
  );
}

Map<String, Object?> _freezeMap(Map<String, Object?> source) =>
    _freezeJsonLike(source, HashSet<Object>.identity())!
        as Map<String, Object?>;

/// Versão pública do helper de congelamento profundo. Adicionada na Fase 1C
/// para permitir que novos value objects compartilhados (em arquivos
/// distintos) reutilizem a mesma política de imutabilidade. Não duplica o
/// helper e não altera o comportamento de nenhum contrato existente.
Map<String, Object?> freezeJsonMap(Map<String, Object?> source) => _freezeMap(source);

final class RecordedBy {
  RecordedBy({
    required String uid,
    required String name,
    required String internalRole,
  }) : uid = _required(uid, 'uid'),
       name = _required(name, 'name'),
       internalRole = _required(internalRole, 'internal_role');

  final String uid;
  final String name;
  final String internalRole;

  @override
  bool operator ==(Object other) =>
      other is RecordedBy &&
      other.uid == uid &&
      other.name == name &&
      other.internalRole == internalRole;

  @override
  int get hashCode => Object.hash(uid, name, internalRole);
}

final class WeightKg {
  WeightKg(num value) : value = value.toDouble() {
    if (!this.value.isFinite || this.value <= 0) {
      throw const HealthDomainException(
        'invalid_weight',
        'weight_kg deve ser finito e maior que zero',
      );
    }
  }

  final double value;

  @override
  bool operator ==(Object other) => other is WeightKg && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

final class ClinicalCase {
  ClinicalCase({
    required String id,
    required String dogId,
    required String title,
    required this.status,
    required this.openedAt,
    required String openingEventId,
    required this.openingType,
    required this.recordedBy,
    required this.schemaVersion,
    this.reopenedAt,
    this.reopenedBy,
    this.previousStatus,
    String? reopenReason,
    this.reopenedCount = 0,
  }) : id = _required(id, 'id'),
       dogId = _required(dogId, 'dog_id'),
       title = _required(title, 'title'),
       openingEventId = _required(openingEventId, 'opening_event_id'),
       reopenReason = reopenReason?.trim() {
    if (reopenedCount < 0) {
      throw const HealthDomainException(
        'invalid_reopened_count',
        'reopened_count não pode ser negativo',
      );
    }
    final metadata = [
      reopenedAt,
      reopenedBy,
      previousStatus,
      this.reopenReason,
    ];
    final hasAny = metadata.any((value) => value != null);
    final hasAll = metadata.every((value) => value != null);
    if (schemaVersion <= 0) {
      throw const HealthDomainException(
        'invalid_schema_version',
        'schema_version deve ser positivo',
      );
    }
    if (hasAny && !hasAll) {
      throw const HealthDomainException(
        'incomplete_reopen_metadata',
        'Metadados de reabertura devem ser completos',
      );
    }
    if (this.reopenReason != null && this.reopenReason!.isEmpty) {
      throw const HealthDomainException(
        'missing_reopen_reason',
        'reopen_reason é obrigatório',
      );
    }
    if (hasAll &&
        (previousStatus != ClinicalCaseStatus.discharged ||
            !_reopenStatuses.contains(status) ||
            reopenedCount <= 0)) {
      throw const HealthDomainException(
        'inconsistent_reopen_metadata',
        'Metadados de reabertura não correspondem ao status do caso',
      );
    }
    if (!hasAny && reopenedCount != 0) {
      throw const HealthDomainException(
        'inconsistent_reopened_count',
        'reopened_count exige metadados da última reabertura',
      );
    }
  }

  final String id;
  final String dogId;
  final String title;
  final ClinicalCaseStatus status;
  final DateTime openedAt;
  final String openingEventId;
  final ClinicalCaseOpeningType openingType;
  final RecordedBy recordedBy;
  final int schemaVersion;
  final DateTime? reopenedAt;
  final RecordedBy? reopenedBy;
  final ClinicalCaseStatus? previousStatus;
  final String? reopenReason;
  final int reopenedCount;

  ClinicalCase copyWith({
    ClinicalCaseStatus? status,
    Object? reopenedAt = _notProvided,
    Object? reopenedBy = _notProvided,
    Object? previousStatus = _notProvided,
    Object? reopenReason = _notProvided,
    int? reopenedCount,
  }) => ClinicalCase(
    id: id,
    dogId: dogId,
    title: title,
    status: status ?? this.status,
    openedAt: openedAt,
    openingEventId: openingEventId,
    openingType: openingType,
    recordedBy: recordedBy,
    schemaVersion: schemaVersion,
    reopenedAt: identical(reopenedAt, _notProvided)
        ? this.reopenedAt
        : reopenedAt as DateTime?,
    reopenedBy: identical(reopenedBy, _notProvided)
        ? this.reopenedBy
        : reopenedBy as RecordedBy?,
    previousStatus: identical(previousStatus, _notProvided)
        ? this.previousStatus
        : previousStatus as ClinicalCaseStatus?,
    reopenReason: identical(reopenReason, _notProvided)
        ? this.reopenReason
        : reopenReason as String?,
    reopenedCount: reopenedCount ?? this.reopenedCount,
  );

  @override
  bool operator ==(Object other) =>
      other is ClinicalCase &&
      other.id == id &&
      other.dogId == dogId &&
      other.title == title &&
      other.status == status &&
      other.openedAt == openedAt &&
      other.openingEventId == openingEventId &&
      other.openingType == openingType &&
      other.recordedBy == recordedBy &&
      other.schemaVersion == schemaVersion &&
      other.reopenedAt == reopenedAt &&
      other.reopenedBy == reopenedBy &&
      other.previousStatus == previousStatus &&
      other.reopenReason == reopenReason &&
      other.reopenedCount == reopenedCount;

  @override
  int get hashCode => Object.hash(
    id,
    dogId,
    title,
    status,
    openedAt,
    openingEventId,
    openingType,
    recordedBy,
    schemaVersion,
    reopenedAt,
    reopenedBy,
    previousStatus,
    reopenReason,
    reopenedCount,
  );
}

const _notProvided = Object();
const _reopenStatuses = {
  ClinicalCaseStatus.open,
  ClinicalCaseStatus.underInvestigation,
  ClinicalCaseStatus.underTreatment,
  ClinicalCaseStatus.monitoring,
};

final class ClinicalEvent {
  ClinicalEvent({
    required String id,
    required String caseId,
    required this.type,
    required this.status,
    required this.occurredAt,
    required this.recordedAt,
    required this.recordedBy,
    required String payloadType,
    required this.payloadVersion,
    required this.schemaVersion,
    required Map<String, Object?> content,
    List<String> attachmentRefs = const [],
    String? cancelReason,
    this.cancelledAt,
    this.cancelledBy,
  }) : id = _required(id, 'id'),
       caseId = _required(caseId, 'case_id'),
       payloadType = _required(payloadType, 'payload_type'),
       content = _freezeMap(content),
       attachmentRefs = List.unmodifiable(attachmentRefs),
       cancelReason = cancelReason?.trim() {
    if (payloadVersion <= 0 || schemaVersion <= 0) {
      throw const HealthDomainException(
        'invalid_schema_version',
        'payload_version e schema_version devem ser positivos',
      );
    }
    final cancellation = [this.cancelReason, cancelledAt, cancelledBy];
    final hasAny = cancellation.any((value) => value != null);
    final hasAll = cancellation.every((value) => value != null);
    if (hasAny && !hasAll) {
      throw const HealthDomainException(
        'incomplete_cancellation_metadata',
        'Metadados de cancelamento devem ser completos',
      );
    }
    if (status == ClinicalEventStatus.cancelled && !hasAll) {
      throw const HealthDomainException(
        'missing_cancellation_metadata',
        'Evento cancelado exige motivo, instante e autoria',
      );
    }
    if (status != ClinicalEventStatus.cancelled && hasAny) {
      throw const HealthDomainException(
        'unexpected_cancellation_metadata',
        'Evento não cancelado não pode ter metadados de cancelamento',
      );
    }
    if (this.cancelReason != null && this.cancelReason!.isEmpty) {
      throw const HealthDomainException(
        'missing_cancel_reason',
        'cancel_reason é obrigatório',
      );
    }
  }

  final String id;
  final String caseId;
  final ClinicalEventType type;
  final ClinicalEventStatus status;
  final DateTime occurredAt;
  final DateTime recordedAt;
  final RecordedBy recordedBy;
  final String payloadType;
  final int payloadVersion;
  final int schemaVersion;
  final Map<String, Object?> content;
  final List<String> attachmentRefs;
  final String? cancelReason;
  final DateTime? cancelledAt;
  final RecordedBy? cancelledBy;

  void validateOccurredAt({required DateTime referenceTime}) {
    if (occurredAt.isAfter(referenceTime)) {
      throw const HealthDomainException(
        'future_occurred_at',
        'occurred_at não pode estar no futuro',
      );
    }
  }

  ClinicalEvent copyWith({
    ClinicalEventStatus? status,
    Object? cancelReason = _notProvided,
    Object? cancelledAt = _notProvided,
    Object? cancelledBy = _notProvided,
  }) => ClinicalEvent(
    id: id,
    caseId: caseId,
    type: type,
    status: status ?? this.status,
    occurredAt: occurredAt,
    recordedAt: recordedAt,
    recordedBy: recordedBy,
    payloadType: payloadType,
    payloadVersion: payloadVersion,
    schemaVersion: schemaVersion,
    content: content,
    attachmentRefs: attachmentRefs,
    cancelReason: identical(cancelReason, _notProvided)
        ? this.cancelReason
        : cancelReason as String?,
    cancelledAt: identical(cancelledAt, _notProvided)
        ? this.cancelledAt
        : cancelledAt as DateTime?,
    cancelledBy: identical(cancelledBy, _notProvided)
        ? this.cancelledBy
        : cancelledBy as RecordedBy?,
  );
}

final class WeightAssessment {
  WeightAssessment({
    required String id,
    required String dogId,
    required this.weight,
    required this.measuredAt,
    required this.recordedBy,
    required this.schemaVersion,
  }) : id = _required(id, 'id'),
       dogId = _required(dogId, 'dog_id') {
    if (schemaVersion <= 0) {
      throw const HealthDomainException(
        'invalid_schema_version',
        'schema_version deve ser positivo',
      );
    }
  }

  final String id;
  final String dogId;
  final WeightKg weight;
  final DateTime measuredAt;
  final RecordedBy recordedBy;
  final int schemaVersion;

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
      other.id == id &&
      other.dogId == dogId &&
      other.weight == weight &&
      other.measuredAt == measuredAt &&
      other.recordedBy == recordedBy &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode =>
      Object.hash(id, dogId, weight, measuredAt, recordedBy, schemaVersion);
}

final class MealLog {
  MealLog({
    required String id,
    required String dogId,
    required this.period,
    required num amountGrams,
    required this.fedAt,
    required this.recordedBy,
    required this.schemaVersion,
  }) : id = _required(id, 'id'),
       dogId = _required(dogId, 'dog_id'),
       amountGrams = amountGrams.toDouble() {
    if (period.isAbsent) {
      throw const HealthDomainException(
        'missing_period',
        'period é obrigatório',
      );
    }
    if (!this.amountGrams.isFinite || this.amountGrams <= 0) {
      throw const HealthDomainException(
        'invalid_amount_grams',
        'amount_grams deve ser finito e maior que zero',
      );
    }
    if (schemaVersion <= 0) {
      throw const HealthDomainException(
        'invalid_schema_version',
        'schema_version deve ser positivo',
      );
    }
  }

  final String id;
  final String dogId;
  final ParsedHealthEnum<MealPeriod> period;
  final double amountGrams;
  final DateTime fedAt;
  final RecordedBy recordedBy;
  final int schemaVersion;

  void validateFedAt({required DateTime referenceTime}) {
    if (fedAt.isAfter(referenceTime)) {
      throw const HealthDomainException(
        'future_fed_at',
        'fed_at não pode estar no futuro',
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      other is MealLog &&
      other.id == id &&
      other.dogId == dogId &&
      other.period == period &&
      other.amountGrams == amountGrams &&
      other.fedAt == fedAt &&
      other.recordedBy == recordedBy &&
      other.schemaVersion == schemaVersion;

  @override
  int get hashCode => Object.hash(
    id,
    dogId,
    period,
    amountGrams,
    fedAt,
    recordedBy,
    schemaVersion,
  );
}

final class LegacyHealthRecordView {
  LegacyHealthRecordView({
    required String sourceId,
    required String dogId,
    required this.occurredAt,
    required String typeRaw,
    required String description,
    required Map<String, Object?> originalPayload,
  }) : sourceId = _required(sourceId, 'source_id'),
       dogId = _required(dogId, 'dog_id'),
       typeRaw = typeRaw.trim(),
       description = description.trim(),
       originalPayload = _freezeMap(originalPayload);

  final String sourceId;
  final String dogId;
  final DateTime occurredAt;
  final String typeRaw;
  final String description;
  final Map<String, Object?> originalPayload;
}
