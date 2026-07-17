import 'package:canil_gcm/features/health/domain/health_schedule_item.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/health_v1_value_objects.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_cursor.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_page.dart';

final scheduleTestActor = RecordedBy(
  uid: 'u1',
  name: 'Condutor',
  internalRole: 'condutor',
);

/// Relógio fixo canônico dos testes de apresentação da Agenda.
final scheduleTestNow = DateTime.utc(2026, 7, 14, 10);

HealthScheduleTemporalPolicy testSchedulePolicy({
  Duration tolerance = const Duration(hours: 24),
  Duration upcomingWindow = const Duration(days: 7),
}) {
  return HealthScheduleTemporalPolicy(
    config: MapHealthScheduleTemporalConfig.uniform(
      HealthScheduleTypeTemporalConfig(
        toleranceAfterScheduled: tolerance,
        upcomingWindow: upcomingWindow,
      ),
    ),
  );
}

HealthScheduleItem scheduleItem({
  String id = 's1',
  String dogId = 'dog-a',
  ScheduleType scheduleType = ScheduleType.vaccination,
  ScheduleSourceType sourceType = ScheduleSourceType.manual,
  ScheduleLifecycleStatus status = ScheduleLifecycleStatus.open,
  DateTime? scheduledFor,
  DateTime? dueUntil,
  String timezone = 'America/Sao_Paulo',
  String title = 'Item agenda',
  DateTime? completedAt,
  DateTime? cancelledAt,
  String? cancelReason,
}) {
  final scheduled =
      scheduledFor ?? scheduleTestNow.add(const Duration(hours: 2));
  return HealthScheduleItem(
    id: id,
    dogId: dogId,
    scheduleType: scheduleType,
    title: title,
    scheduledFor: scheduled,
    timezone: timezone,
    lifecycleStatus: status,
    sourceType: sourceType,
    createdAt: scheduleTestNow,
    recordedBy: scheduleTestActor,
    schemaVersion: 1,
    dueUntil: dueUntil,
    completedAt: completedAt,
    completedBy: completedAt == null ? null : scheduleTestActor,
    cancelledAt: cancelledAt,
    cancelledBy: cancelledAt == null ? null : scheduleTestActor,
    cancelReason: cancelReason,
  );
}

HealthSchedulePage schedulePage(
  List<HealthScheduleItem> items, {
  String? nextCursorToken,
}) {
  if (nextCursorToken == null) {
    return HealthSchedulePage(items: items, hasMore: false, nextCursor: null);
  }
  return HealthSchedulePage(
    items: items,
    hasMore: true,
    nextCursor: HealthScheduleCursor(nextCursorToken),
  );
}
