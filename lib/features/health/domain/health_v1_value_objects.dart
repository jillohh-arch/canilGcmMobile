import 'dart:collection';

import 'health_v1_enums_ext.dart';
import 'health_v1_models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Value Objects compartilhados (Domain Model §5 e §17).
// ─────────────────────────────────────────────────────────────────────────────

/// Identidade profissional externa — diferencia de `RecordedBy` (interno)
/// conforme ADR-005 §10 e Domain Model §5.
final class ProfessionalIdentity {
  ProfessionalIdentity({
    required String name,
    required ProfessionalRegistrationType registrationType,
    required String registrationNumber,
    required String clinic,
    String? specialty,
  }) : name = name.trim(),
       registrationType = registrationType,
       registrationNumber = registrationNumber.trim(),
       clinic = clinic.trim(),
       specialty = specialty?.trim() {
    if (name.isEmpty) {
      throw const HealthDomainException(
        'missing_professional_name',
        'professional.name é obrigatório',
      );
    }
    if (registrationNumber.isEmpty) {
      throw const HealthDomainException(
        'missing_professional_registration_number',
        'professional.registration_number é obrigatório',
      );
    }
    if (clinic.isEmpty) {
      throw const HealthDomainException(
        'missing_professional_clinic',
        'professional.clinic é obrigatório',
      );
    }
  }

  final String name;
  final ProfessionalRegistrationType registrationType;
  final String registrationNumber;
  final String clinic;
  final String? specialty;

  @override
  bool operator ==(Object other) =>
      other is ProfessionalIdentity &&
      other.name == name &&
      other.registrationType == registrationType &&
      other.registrationNumber == registrationNumber &&
      other.clinic == clinic &&
      other.specialty == specialty;

  @override
  int get hashCode => Object.hash(
    name,
    registrationType,
    registrationNumber,
    clinic,
    specialty,
  );
}

/// Resumo leve para projeções — apenas nome + especialidade opcional.
final class ProfessionalIdentitySummary {
  const ProfessionalIdentitySummary({required this.name, this.specialty});

  final String name;
  final String? specialty;

  @override
  bool operator ==(Object other) =>
      other is ProfessionalIdentitySummary &&
      other.name == name &&
      other.specialty == specialty;

  @override
  int get hashCode => Object.hash(name, specialty);
}

/// Bloco de impacto operacional em ClinicalEvent/ExamProcess.
final class OperationalImpact {
  OperationalImpact({
    required this.level,
    required String description,
    List<String> restrictionsIssued = const [],
  }) : description = description.trim(),
       restrictionsIssued = List.unmodifiable(
         List<String>.of(restrictionsIssued),
       ) {
    if (this.description.isEmpty) {
      throw const HealthDomainException(
        'missing_operational_impact_description',
        'operational_impact.description é obrigatório',
      );
    }
    if (level == OperationalImpactLevel.none &&
        this.restrictionsIssued.isNotEmpty) {
      throw const HealthDomainException(
        'inconsistent_operational_impact',
        'restrictions_issued exige level diferente de none',
      );
    }
  }

  final OperationalImpactLevel level;
  final String description;
  final List<String> restrictionsIssued;

  @override
  bool operator ==(Object other) =>
      other is OperationalImpact &&
      other.level == level &&
      other.description == description &&
      _listEq(other.restrictionsIssued, restrictionsIssued);

  @override
  int get hashCode =>
      Object.hash(level, description, Object.hashAll(restrictionsIssued));

  static bool _listEq(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Referência lógica a HealthDocument — sem URL/storage.
final class HealthDocumentRef {
  const HealthDocumentRef({required this.healthDocumentId, this.description});

  final String healthDocumentId;
  final String? description;

  @override
  bool operator ==(Object other) =>
      other is HealthDocumentRef &&
      other.healthDocumentId == healthDocumentId &&
      other.description == description;

  @override
  int get hashCode => Object.hash(healthDocumentId, description);
}

/// Evidência que liga uma restrição ao agregado de origem.
final class RestrictionEvidence {
  const RestrictionEvidence({
    this.caseId,
    this.eventId,
    this.examId,
    this.description,
  });

  final String? caseId;
  final String? eventId;
  final String? examId;
  final String? description;

  @override
  bool operator ==(Object other) =>
      other is RestrictionEvidence &&
      other.caseId == caseId &&
      other.eventId == eventId &&
      other.examId == examId &&
      other.description == description;

  @override
  int get hashCode => Object.hash(caseId, eventId, examId, description);
}

/// Bloco estruturado de dose prescrita.
final class DoseBlock {
  DoseBlock({
    required this.value,
    required this.unit,
    required this.perKg,
    required this.route,
  }) {
    if (!value.isFinite || value <= 0) {
      throw const HealthDomainException(
        'invalid_dose_value',
        'dose.value deve ser finito e maior que zero',
      );
    }
  }

  final double value;
  final DoseUnit unit;
  final bool perKg;
  final DoseRoute route;

  @override
  bool operator ==(Object other) =>
      other is DoseBlock &&
      other.value == value &&
      other.unit == unit &&
      other.perKg == perKg &&
      other.route == route;

  @override
  int get hashCode => Object.hash(value, unit, perKg, route);
}

/// Bloco estruturado de schedule.
final class ScheduleBlock {
  ScheduleBlock({
    required this.type,
    this.intervalMinutes,
    List<String>? timesOfDay,
    required String timezone,
    required this.toleranceMinutes,
  }) : timesOfDay = List.unmodifiable(List<String>.of(timesOfDay ?? const [])),
       timezone = timezone.trim() {
    if (toleranceMinutes < 0) {
      throw const HealthDomainException(
        'invalid_schedule_tolerance',
        'schedule.tolerance_minutes não pode ser negativo',
      );
    }
    if (type == ScheduleTypeBlock.interval && intervalMinutes == null) {
      throw const HealthDomainException(
        'missing_schedule_interval',
        'schedule.interval_minutes é obrigatório quando type=interval',
      );
    }
    final interval = intervalMinutes;
    if (interval != null && interval <= 0) {
      throw const HealthDomainException(
        'invalid_schedule_interval',
        'schedule.interval_minutes deve ser positivo quando informado',
      );
    }
    final times = timesOfDay;
    if (type == ScheduleTypeBlock.fixedTimes &&
        (times == null || times.isEmpty)) {
      throw const HealthDomainException(
        'missing_schedule_times',
        'schedule.times_of_day é obrigatório quando type=fixed_times',
      );
    }
    if (timezone.isEmpty) {
      throw const HealthDomainException(
        'missing_schedule_timezone',
        'schedule.timezone é obrigatório',
      );
    }
  }

  final ScheduleTypeBlock type;
  final int? intervalMinutes;
  final List<String> timesOfDay;
  final String timezone;
  final int toleranceMinutes;

  @override
  bool operator ==(Object other) =>
      other is ScheduleBlock &&
      other.type == type &&
      other.intervalMinutes == intervalMinutes &&
      _listEq(other.timesOfDay, timesOfDay) &&
      other.timezone == timezone &&
      other.toleranceMinutes == toleranceMinutes;

  @override
  int get hashCode => Object.hash(
    type,
    intervalMinutes,
    Object.hashAll(timesOfDay),
    timezone,
    toleranceMinutes,
  );

  static bool _listEq(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Configuração temporal explícita de um `ScheduleType`.
///
/// Não há default universal: cada tipo ativo deve fornecer valores válidos
/// antes da derivação que dependa deles (Domain Model §2.12 / ADR-004 §13).
final class HealthScheduleTypeTemporalConfig {
  HealthScheduleTypeTemporalConfig({
    required this.toleranceAfterScheduled,
    required this.upcomingWindow,
  }) {
    if (toleranceAfterScheduled.isNegative) {
      throw ArgumentError.value(
        toleranceAfterScheduled,
        'toleranceAfterScheduled',
        'não pode ser negativo',
      );
    }
    if (upcomingWindow.isNegative) {
      throw ArgumentError.value(
        upcomingWindow,
        'upcomingWindow',
        'não pode ser negativo',
      );
    }
  }

  /// Acrescentada a `scheduled_for` quando `due_until` está ausente.
  final Duration toleranceAfterScheduled;

  /// Janela "upcoming" antes de `scheduled_for` (configurável por tipo).
  final Duration upcomingWindow;

  @override
  bool operator ==(Object other) =>
      other is HealthScheduleTypeTemporalConfig &&
      other.toleranceAfterScheduled == toleranceAfterScheduled &&
      other.upcomingWindow == upcomingWindow;

  @override
  int get hashCode => Object.hash(toleranceAfterScheduled, upcomingWindow);
}

/// Resolve a configuração temporal por `schedule_type`.
///
/// A assinatura inclui `scheduledFor` e `timezone` para permitir regras
/// futuras sem fallback universal silencioso.
abstract interface class HealthScheduleTemporalConfigResolver {
  /// Deve falhar de forma explícita se o tipo não tiver configuração.
  HealthScheduleTypeTemporalConfig resolve(
    ScheduleType scheduleType, {
    required DateTime scheduledFor,
    required String timezone,
  });
}

/// Implementação map-based sem fallback universal.
///
/// Tipos ausentes do mapa falham com [HealthDomainException]
/// (`missing_schedule_type_temporal_config`).
final class MapHealthScheduleTemporalConfig
    implements HealthScheduleTemporalConfigResolver {
  MapHealthScheduleTemporalConfig(
    Map<ScheduleType, HealthScheduleTypeTemporalConfig> byType,
  ) : _byType =
          Map<ScheduleType, HealthScheduleTypeTemporalConfig>.unmodifiable(
            byType,
          );

  final Map<ScheduleType, HealthScheduleTypeTemporalConfig> _byType;

  /// Atalho de teste/produção: mesma config para todos os [ScheduleType].
  factory MapHealthScheduleTemporalConfig.uniform(
    HealthScheduleTypeTemporalConfig config,
  ) {
    return MapHealthScheduleTemporalConfig({
      for (final type in ScheduleType.values) type: config,
    });
  }

  @override
  HealthScheduleTypeTemporalConfig resolve(
    ScheduleType scheduleType, {
    required DateTime scheduledFor,
    required String timezone,
  }) {
    final config = _byType[scheduleType];
    if (config == null) {
      throw HealthDomainException(
        'missing_schedule_type_temporal_config',
        'Configuração temporal ausente para schedule_type=${scheduleType.wireName}',
      );
    }
    return config;
  }
}

/// Resolvedor legado de tolerância por `ScheduleType` (compatibilidade).
///
/// Preferir [HealthScheduleTemporalConfigResolver]. Mantido para consumidores
/// que ainda injetam apenas a duração de tolerância.
@Deprecated(
  'Use HealthScheduleTemporalConfigResolver (tolerância + upcoming por tipo)',
)
typedef ScheduleToleranceResolver =
    Duration Function(ScheduleType scheduleType);

/// Wrapper de lista imutável com `==`/`hashCode` por valor.
final class ImmutableList<T> {
  ImmutableList(Iterable<T> items) : items = List<T>.unmodifiable(items);

  final List<T> items;

  @override
  bool operator ==(Object other) {
    if (other is! ImmutableList<T>) return false;
    if (other.items.length != items.length) return false;
    for (var i = 0; i < items.length; i++) {
      if (items[i] != other.items[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(items);
}

/// Wrapper de mapa imutável (read-only).
final class ImmutableDomainMap {
  ImmutableDomainMap(Map<String, Object?> source)
    : _map = UnmodifiableMapView(
        freezeJsonMap(Map<String, Object?>.from(source)),
      );

  final Map<String, Object?> _map;

  Map<String, Object?> get value => _map;

  @override
  bool operator ==(Object other) {
    if (other is! ImmutableDomainMap) return false;
    if (other._map.length != _map.length) return false;
    for (final entry in _map.entries) {
      if (other._map[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAllUnordered(
    _map.entries.map((e) => Object.hash(e.key, e.value)),
  );
}
