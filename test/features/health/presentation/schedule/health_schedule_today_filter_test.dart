import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_item_view.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_ui_filter.dart';

import 'schedule_test_helpers.dart';

void main() {
  // now = 2026-07-14T10:00Z = 07:00 America/Sao_Paulo
  final now = scheduleTestNow;
  final policy = testSchedulePolicy();

  HealthScheduleItemView viewOf({
    required DateTime scheduledFor,
    DateTime? dueUntil,
    String timezone = 'America/Sao_Paulo',
    ScheduleLifecycleStatus status = ScheduleLifecycleStatus.open,
    DateTime? completedAt,
    DateTime? cancelledAt,
    String? cancelReason,
  }) {
    final item = scheduleItem(
      scheduledFor: scheduledFor,
      dueUntil: dueUntil,
      timezone: timezone,
      status: status,
      completedAt: completedAt,
      cancelledAt: cancelledAt,
      cancelReason: cancelReason,
    );
    return HealthScheduleItemView.fromDomain(item, policy: policy, now: now);
  }

  group('filtro Hoje — calendário civil do item', () {
    test('today futuro no mesmo dia aparece', () {
      final v = viewOf(scheduledFor: now.add(const Duration(hours: 5)));
      expect(v.temporalStatus, HealthScheduleTemporalStatus.today);
      expect(HealthScheduleUiFilter.today.matches(v, now: now), isTrue);
    });

    test('pending do mesmo dia aparece', () {
      final v = viewOf(
        scheduledFor: now.subtract(const Duration(minutes: 30)),
        dueUntil: now.add(const Duration(hours: 2)),
      );
      expect(v.temporalStatus, HealthScheduleTemporalStatus.pending);
      expect(HealthScheduleUiFilter.today.matches(v, now: now), isTrue);
      expect(filterScheduleItems([v], HealthScheduleUiFilter.today, now: now), [
        v,
      ]);
      expect(countScheduleItemsToday([v], now: now), 1);
    });

    test('overdue do mesmo dia aparece', () {
      // scheduled manhã SP, due já passou — ainda mesmo dia civil SP
      final scheduled = DateTime.utc(2026, 7, 14, 8); // 05:00 SP
      final due = DateTime.utc(2026, 7, 14, 9);
      final v = viewOf(scheduledFor: scheduled, dueUntil: due);
      expect(v.temporalStatus, HealthScheduleTemporalStatus.overdue);
      expect(HealthScheduleUiFilter.today.matches(v, now: now), isTrue);
    });

    test('ontem não aparece', () {
      final v = viewOf(
        scheduledFor: now.subtract(const Duration(days: 1)),
        dueUntil: now.subtract(const Duration(hours: 20)),
      );
      expect(HealthScheduleUiFilter.today.matches(v, now: now), isFalse);
    });

    test('amanhã não aparece', () {
      final v = viewOf(scheduledFor: now.add(const Duration(days: 1)));
      expect(HealthScheduleUiFilter.today.matches(v, now: now), isFalse);
    });

    test('timezone do item diferente do host (UTC vs SP)', () {
      // scheduled 2026-07-15T02:00Z = 14 23:00 SP → hoje em SP; amanhã em UTC
      final scheduled = DateTime.utc(2026, 7, 15, 2);
      final refNow = DateTime.utc(2026, 7, 14, 15); // 12:00 SP
      final itemSp = viewOf(
        scheduledFor: scheduled,
        timezone: 'America/Sao_Paulo',
      );
      final itemUtc = viewOf(scheduledFor: scheduled, timezone: 'Etc/UTC');
      // re-evaluate temporal with refNow for filter only uses scheduled day
      expect(isScheduledOnLocalCivilDay(item: itemSp, now: refNow), isTrue);
      expect(isScheduledOnLocalCivilDay(item: itemUtc, now: refNow), isFalse);
    });
  });
}
