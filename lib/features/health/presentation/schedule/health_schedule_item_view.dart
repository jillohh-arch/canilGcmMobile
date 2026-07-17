import 'package:canil_gcm/features/health/domain/health_schedule_item.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';

/// Item de agenda para apresentação, com estado temporal já derivado.
///
/// A UI **não** recalcula precedência temporal: [temporalStatus] é a única
/// fonte exposta (produzida por [HealthScheduleTemporalPolicy]).
final class HealthScheduleItemView {
  const HealthScheduleItemView({
    required this.id,
    required this.dogId,
    required this.scheduleType,
    required this.title,
    required this.scheduledFor,
    required this.timezone,
    required this.lifecycleStatus,
    required this.sourceType,
    required this.temporalStatus,
    required this.createdAt,
    required this.recordedBy,
    required this.schemaVersion,
    this.dueUntil,
    this.effectiveDueUntil,
    this.completedAt,
    this.completedBy,
    this.cancelledAt,
    this.cancelledBy,
    this.cancelReason,
    this.sourceId,
    this.caseId,
    this.notes,
    this.recurrenceRule,
    this.assignedToUid,
    this.assignedToName,
  });

  /// Constrói a view a partir do agregado canônico + política pura.
  factory HealthScheduleItemView.fromDomain(
    HealthScheduleItem item, {
    required HealthScheduleTemporalPolicy policy,
    required DateTime now,
  }) {
    final temporal = policy.evaluate(item, now: now);
    final DateTime? effectiveDue;
    if (item.lifecycleStatus == ScheduleLifecycleStatus.open) {
      effectiveDue = policy.effectiveDueUntil(item);
    } else {
      effectiveDue = item.dueUntil;
    }
    return HealthScheduleItemView(
      id: item.id,
      dogId: item.dogId,
      scheduleType: item.scheduleType,
      title: item.title,
      scheduledFor: item.scheduledFor,
      dueUntil: item.dueUntil,
      effectiveDueUntil: effectiveDue,
      timezone: item.timezone,
      lifecycleStatus: item.lifecycleStatus,
      sourceType: item.sourceType,
      temporalStatus: temporal,
      createdAt: item.createdAt,
      recordedBy: item.recordedBy,
      schemaVersion: item.schemaVersion,
      completedAt: item.completedAt,
      completedBy: item.completedBy,
      cancelledAt: item.cancelledAt,
      cancelledBy: item.cancelledBy,
      cancelReason: item.cancelReason,
      sourceId: item.sourceId,
      caseId: item.caseId,
      notes: item.notes,
      recurrenceRule: item.recurrenceRule,
      assignedToUid: item.assignedToUid,
      assignedToName: item.assignedToName,
    );
  }

  final String id;
  final String dogId;
  final ScheduleType scheduleType;
  final String title;
  final DateTime scheduledFor;
  final DateTime? dueUntil;

  /// `due_until` efetivo usado na derivação (quando aplicável).
  final DateTime? effectiveDueUntil;
  final String timezone;
  final ScheduleLifecycleStatus lifecycleStatus;
  final ScheduleSourceType sourceType;

  /// Estado temporal derivado — nunca persistido.
  final HealthScheduleTemporalStatus temporalStatus;

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

  bool get isTerminal =>
      temporalStatus == HealthScheduleTemporalStatus.completed ||
      temporalStatus == HealthScheduleTemporalStatus.cancelled;

  @override
  bool operator ==(Object other) {
    if (other is! HealthScheduleItemView) return false;
    return other.id == id &&
        other.dogId == dogId &&
        other.scheduleType == scheduleType &&
        other.title == title &&
        other.scheduledFor == scheduledFor &&
        other.dueUntil == dueUntil &&
        other.effectiveDueUntil == effectiveDueUntil &&
        other.timezone == timezone &&
        other.lifecycleStatus == lifecycleStatus &&
        other.sourceType == sourceType &&
        other.temporalStatus == temporalStatus &&
        other.createdAt == createdAt &&
        other.recordedBy == recordedBy &&
        other.schemaVersion == schemaVersion &&
        other.completedAt == completedAt &&
        other.completedBy == completedBy &&
        other.cancelledAt == cancelledAt &&
        other.cancelledBy == cancelledBy &&
        other.cancelReason == cancelReason &&
        other.sourceId == sourceId &&
        other.caseId == caseId &&
        other.notes == notes &&
        other.recurrenceRule == recurrenceRule &&
        other.assignedToUid == assignedToUid &&
        other.assignedToName == assignedToName;
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    dogId,
    scheduleType,
    title,
    scheduledFor,
    dueUntil,
    effectiveDueUntil,
    timezone,
    lifecycleStatus,
    sourceType,
    temporalStatus,
    createdAt,
    recordedBy,
    schemaVersion,
    completedAt,
    completedBy,
    cancelledAt,
    cancelledBy,
    cancelReason,
    sourceId,
    caseId,
    notes,
    recurrenceRule,
    assignedToUid,
    assignedToName,
  ]);
}
