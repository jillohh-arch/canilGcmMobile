import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'health_v1_enums_ext.dart';
import 'health_v1_models.dart';
import 'health_v1_value_objects.dart';

// ─────────────────────────────────────────────────────────────────────────────
// HealthScheduleItem — item canônico de agenda (Domain Model §2.12 e ADR-004 §13).
// Estados temporais derivados no cliente; nunca persistidos.
// ─────────────────────────────────────────────────────────────────────────────

final class HealthScheduleItem {
  HealthScheduleItem({
    required this.id,
    required this.dogId,
    required this.scheduleType,
    required String title,
    required this.scheduledFor,
    required this.timezone,
    required ScheduleLifecycleStatus lifecycleStatus,
    required this.sourceType,
    required this.createdAt,
    required this.recordedBy,
    required this.schemaVersion,
    this.dueUntil,
    this.completedAt,
    this.completedBy,
    this.cancelledAt,
    this.cancelledBy,
    String? cancelReason,
    this.sourceId,
    this.caseId,
    String? notes,
    this.recurrenceRule,
    this.assignedToUid,
    this.assignedToName,
  }) : lifecycleStatus = lifecycleStatus,
       title = title.trim(),
       cancelReason = cancelReason?.trim(),
       notes = notes?.trim() {
    if (schemaVersion <= 0) {
      throw const HealthDomainException(
        'invalid_schema_version',
        'schema_version deve ser positivo',
      );
    }
    final tzName = timezone.trim();
    if (tzName.isEmpty) {
      throw const HealthDomainException(
        'missing_schedule_timezone',
        'timezone é obrigatório',
      );
    }
    HealthScheduleTemporalPolicy.validateTimezone(tzName);
    if (title.isEmpty) {
      throw const HealthDomainException(
        'missing_schedule_title',
        'title é obrigatório',
      );
    }
    if (lifecycleStatus == ScheduleLifecycleStatus.completed &&
        (completedAt == null || completedBy == null)) {
      throw const HealthDomainException(
        'missing_completion_metadata',
        'completed exige completed_at e completed_by',
      );
    }
    final cancelAny =
        cancelledAt != null || cancelledBy != null || cancelReason != null;
    final cancelAll =
        cancelledAt != null && cancelledBy != null && cancelReason != null;
    if (cancelAny && !cancelAll) {
      throw const HealthDomainException(
        'incomplete_cancellation_metadata',
        'Metadados de cancelamento devem ser completos',
      );
    }
    if (lifecycleStatus == ScheduleLifecycleStatus.cancelled && !cancelAll) {
      throw const HealthDomainException(
        'missing_cancellation_metadata',
        'cancelled exige cancelled_at, cancelled_by e cancel_reason',
      );
    }
    if (lifecycleStatus != ScheduleLifecycleStatus.cancelled && cancelAny) {
      throw const HealthDomainException(
        'unexpected_cancellation_metadata',
        'item não cancelado não pode ter metadados de cancelamento',
      );
    }
    if (lifecycleStatus == ScheduleLifecycleStatus.open &&
        (completedAt != null || completedBy != null || cancelAny)) {
      throw const HealthDomainException(
        'inconsistent_open_state',
        'open não pode ter metadados completed/cancelled',
      );
    }
    if (dueUntil != null && dueUntil!.isBefore(scheduledFor)) {
      throw const HealthDomainException(
        'inconsistent_due_until',
        'due_until não pode ser anterior a scheduled_for',
      );
    }
  }

  final String id;
  final String dogId;
  final ScheduleType scheduleType;
  final String title;
  final DateTime scheduledFor;
  final DateTime? dueUntil;
  final String timezone;
  final ScheduleLifecycleStatus lifecycleStatus;
  final ScheduleSourceType sourceType;
  final DateTime createdAt;
  final RecordedBy recordedBy;
  final int schemaVersion;

  final DateTime? completedAt;
  final RecordedBy? completedBy;
  final DateTime? cancelledAt;
  final RecordedBy? cancelledBy;
  final String? cancelReason;
  final String? sourceId;
  final String? caseId;
  final String? notes;
  final String? recurrenceRule;
  final String? assignedToUid;
  final String? assignedToName;
}

/// Política pura de derivação temporal conforme Domain Model §2.12 e
/// ADR-004 §13. Recebe `now` explicitamente; sem relógio global.
///
/// O dia civil é calculado no **timezone do próprio item** usando
/// `package:timezone` (já presente no `pubspec.yaml`). Timezones inválidos
/// são rejeitados no construtor do item e em [validateTimezone].
///
/// A base IANA é inicializada de forma **privada, idempotente e
/// autossuficiente** em [_ensureTimeZonesInitialized] — o Health não depende
/// da ordem de bootstrap de Push ou de qualquer outro módulo. Não há
/// fallback silencioso para UTC: nome IANA inválido continua falhando.
final class HealthScheduleTemporalPolicy {
  HealthScheduleTemporalPolicy({
    required ScheduleToleranceResolver resolveTolerance,
    this.upcomingWindow = const Duration(days: 7),
  }) : resolveTolerance = resolveTolerance;

  final ScheduleToleranceResolver resolveTolerance;
  final Duration upcomingWindow;

  /// Flag interna: `timeZoneDatabase.isEmpty` NÃO indica prontidão do package
  /// (antes do init a base reporta isEmpty=false e getLocation falha).
  static bool _tzDatabaseReady = false;

  /// Garante que a database IANA do `package:timezone` está carregada.
  /// Idempotente e autossuficiente — o Health não depende de Push/main.
  /// Privado — não é contrato público.
  static void _ensureTimeZonesInitialized() {
    if (_tzDatabaseReady) return;
    tz_data.initializeTimeZones();
    _tzDatabaseReady = true;
  }

  /// Valida uma string de timezone IANA. Lança [HealthDomainException]
  /// com código `invalid_schedule_timezone` quando a base de timezones não
  /// reconhece o nome. Nunca substitui por UTC.
  static void validateTimezone(String timezone) {
    final name = timezone.trim();
    if (name.isEmpty) {
      throw const HealthDomainException(
        'invalid_schedule_timezone',
        'timezone não pode ser vazio',
      );
    }
    _ensureTimeZonesInitialized();
    try {
      tz.getLocation(name);
    } on Exception {
      throw HealthDomainException(
        'invalid_schedule_timezone',
        'timezone "$name" não é reconhecido pela base IANA',
      );
    }
  }

  /// Regra única absoluta — primeira condição verdadeira vence.
  HealthScheduleTemporalStatus evaluate(
    HealthScheduleItem item, {
    required DateTime now,
  }) {
    if (item.lifecycleStatus == ScheduleLifecycleStatus.completed) {
      return HealthScheduleTemporalStatus.completed;
    }
    if (item.lifecycleStatus == ScheduleLifecycleStatus.cancelled) {
      return HealthScheduleTemporalStatus.cancelled;
    }
    final DateTime effectiveDueUntil;
    if (item.dueUntil != null) {
      effectiveDueUntil = item.dueUntil!;
    } else {
      final tolerance = resolveTolerance(item.scheduleType);
      effectiveDueUntil = item.scheduledFor.add(tolerance);
    }
    if (now.isAfter(effectiveDueUntil)) {
      return HealthScheduleTemporalStatus.overdue;
    }
    if (!now.isBefore(item.scheduledFor)) {
      return HealthScheduleTemporalStatus.pending;
    }
    _ensureTimeZonesInitialized();
    final location = tz.getLocation(item.timezone);
    final nowInZone = tz.TZDateTime.from(now, location);
    final scheduledInZone = tz.TZDateTime.from(item.scheduledFor, location);
    if (_isSameLocalDay(nowInZone, scheduledInZone)) {
      return HealthScheduleTemporalStatus.today;
    }
    final upcomingBoundary = scheduledInZone.subtract(upcomingWindow);
    if (nowInZone.isAfter(upcomingBoundary) &&
        nowInZone.isBefore(scheduledInZone)) {
      return HealthScheduleTemporalStatus.upcoming;
    }
    return HealthScheduleTemporalStatus.scheduled;
  }

  static bool _isSameLocalDay(tz.TZDateTime a, tz.TZDateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
