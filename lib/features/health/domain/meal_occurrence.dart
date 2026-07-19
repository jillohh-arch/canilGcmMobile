import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'health_v1_models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Meal occurrence (D39) — identidade semântica ≠ ID físico opaco.
// Hash/ID de persistência: DEFERRED 5D (Q7).
// ─────────────────────────────────────────────────────────────────────────────

/// Identidade **semântica** da ocorrência planejada no dia operacional local.
///
/// ```text
/// dogId + planId + plannedMealId + localServiceDate
/// ```
///
/// Não é o valor persistido em `meal_occurrence_id` (ver [MealOccurrenceId]).
final class MealOccurrenceKey {
  MealOccurrenceKey({
    required String dogId,
    required String planId,
    required String plannedMealId,
    required this.localServiceDate,
  }) : dogId = _require(dogId, 'dog_id'),
       planId = _require(planId, 'plan_id'),
       plannedMealId = _require(plannedMealId, 'planned_meal_id');

  final String dogId;
  final String planId;
  final String plannedMealId;
  final LocalServiceDate localServiceDate;

  /// Representação diagnóstica estável (não é ID físico de produção).
  String get diagnosticLabel =>
      'occurrence(dog=$dogId,plan=$planId,slot=$plannedMealId,date=${localServiceDate.isoDate})';

  static String _require(String value, String field) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw HealthDomainException('missing_$field', '$field é obrigatório');
    }
    return trimmed;
  }

  @override
  bool operator ==(Object other) =>
      other is MealOccurrenceKey &&
      other.dogId == dogId &&
      other.planId == planId &&
      other.plannedMealId == plannedMealId &&
      other.localServiceDate == localServiceDate;

  @override
  int get hashCode =>
      Object.hash(dogId, planId, plannedMealId, localServiceDate);

  @override
  String toString() => diagnosticLabel;
}

/// @nodoc Compat: nome anterior da identidade semântica.
typedef MealOccurrenceIdentity = MealOccurrenceKey;

/// Valor **opaco** de `meal_occurrence_id` lido/persistido — sem reinterpretar.
///
/// Não define SHA-256, UUID nem Firestore document ID nesta fase.
final class MealOccurrenceId {
  MealOccurrenceId(String raw) : value = _require(raw);

  final String value;

  static String _require(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw const HealthDomainException(
        'missing_meal_occurrence_id',
        'meal_occurrence_id não pode ser vazio quando presente',
      );
    }
    return trimmed;
  }

  @override
  bool operator ==(Object other) =>
      other is MealOccurrenceId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// Data operacional local `YYYY-MM-DD` (sem horário; sem TZ embutido no valor).
///
/// A **regra normativa** (D27/D39): a data é a civil no timezone do plano.
/// Qual instant usar (`fed_at` vs `serverNow` em backdated) = DEFERRED 5D.
///
/// [fromInstant] usa `package:timezone` já presente no projeto; **não** usa
/// timezone do device.
final class LocalServiceDate {
  LocalServiceDate._(this.year, this.month, this.day)
    : isoDate =
          '${year.toString().padLeft(4, '0')}-'
          '${month.toString().padLeft(2, '0')}-'
          '${day.toString().padLeft(2, '0')}';

  /// Constrói a partir de uma data já resolvida (YYYY-MM-DD).
  factory LocalServiceDate.fromIso(String iso) {
    final trimmed = iso.trim();
    final match = _isoPattern.firstMatch(trimmed);
    if (match == null) {
      throw HealthDomainException(
        'invalid_local_service_date',
        'local_service_date deve ser YYYY-MM-DD; recebido "$iso"',
      );
    }
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    _assertCivilDate(year, month, day);
    return LocalServiceDate._(year, month, day);
  }

  /// Deriva data civil no [timezone] IANA a partir de um instante absoluto.
  ///
  /// Requer timezone **explícito** (tipicamente o do plano). Nunca device TZ.
  factory LocalServiceDate.fromInstant(
    DateTime instant, {
    required String timezone,
  }) {
    final name = timezone.trim();
    if (name.isEmpty) {
      throw const HealthDomainException(
        'missing_timezone',
        'timezone é obrigatório para local_service_date',
      );
    }
    _ensureTimeZonesInitialized();
    final tz.Location location;
    try {
      location = tz.getLocation(name);
    } on Exception {
      throw HealthDomainException(
        'invalid_timezone',
        'timezone "$name" não é reconhecido pela base IANA',
      );
    }
    final local = tz.TZDateTime.from(instant, location);
    return LocalServiceDate._(local.year, local.month, local.day);
  }

  /// Converte um instante para a data/hora civil no mesmo timezone normativo.
  ///
  /// Mantém apresentação e agregação alinhadas sem depender do timezone do
  /// aparelho.
  static DateTime instantInTimezone(
    DateTime instant, {
    required String timezone,
  }) {
    final name = timezone.trim();
    if (name.isEmpty) {
      throw const HealthDomainException(
        'missing_timezone',
        'timezone é obrigatório para conversão civil',
      );
    }
    _ensureTimeZonesInitialized();
    try {
      return tz.TZDateTime.from(instant, tz.getLocation(name));
    } on Exception {
      throw HealthDomainException(
        'invalid_timezone',
        'timezone "$name" não é reconhecido pela base IANA',
      );
    }
  }

  final int year;
  final int month;
  final int day;

  /// Valor canônico `YYYY-MM-DD` — sem horário e sem offset.
  final String isoDate;

  static final RegExp _isoPattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
  static bool _tzReady = false;

  static void _ensureTimeZonesInitialized() {
    if (_tzReady) return;
    tz_data.initializeTimeZones();
    _tzReady = true;
  }

  static void _assertCivilDate(int year, int month, int day) {
    if (month < 1 || month > 12 || day < 1 || day > 31) {
      throw HealthDomainException(
        'invalid_local_service_date',
        'data civil inválida: $year-$month-$day',
      );
    }
    final dt = DateTime.utc(year, month, day);
    if (dt.year != year || dt.month != month || dt.day != day) {
      throw HealthDomainException(
        'invalid_local_service_date',
        'data civil inválida: $year-$month-$day',
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      other is LocalServiceDate && other.isoDate == isoDate;

  @override
  int get hashCode => isoDate.hashCode;

  @override
  String toString() => isoDate;
}
