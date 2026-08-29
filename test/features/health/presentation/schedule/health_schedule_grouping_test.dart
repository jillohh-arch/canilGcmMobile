import 'package:canil_gcm/features/health/domain/health_schedule_item.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_grouping.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_item_view.dart';
import 'package:flutter_test/flutter_test.dart';

import 'schedule_test_helpers.dart';

void main() {
  final policy = testSchedulePolicy();
  final now = scheduleTestNow;

  HealthScheduleItemView view(HealthScheduleItem item) =>
      HealthScheduleItemView.fromDomain(item, policy: policy, now: now);

  group('groupScheduleItems', () {
    test('separa por temporalStatus sem recalcular regras', () {
      final groups = groupScheduleItems([
        view(
          scheduleItem(
            id: 'o',
            scheduledFor: now.subtract(const Duration(days: 2)),
            dueUntil: now.subtract(const Duration(hours: 1)),
          ),
        ),
        view(
          scheduleItem(
            id: 'p',
            scheduledFor: now.subtract(const Duration(minutes: 10)),
            dueUntil: now.add(const Duration(hours: 2)),
          ),
        ),
        view(
          scheduleItem(
            id: 't',
            scheduledFor: now.add(const Duration(hours: 4)),
          ),
        ),
        view(
          scheduleItem(id: 'u', scheduledFor: now.add(const Duration(days: 2))),
        ),
        view(
          scheduleItem(
            id: 's',
            scheduledFor: now.add(const Duration(days: 40)),
          ),
        ),
        view(
          scheduleItem(
            id: 'c',
            status: ScheduleLifecycleStatus.completed,
            scheduledFor: now.subtract(const Duration(days: 1)),
            completedAt: now,
          ),
        ),
        view(
          scheduleItem(
            id: 'x',
            status: ScheduleLifecycleStatus.cancelled,
            scheduledFor: now.add(const Duration(days: 1)),
            cancelledAt: now,
            cancelReason: 'x',
          ),
        ),
      ]);

      expect(groups.overdue.map((e) => e.id), ['o']);
      expect(groups.pending.map((e) => e.id), ['p']);
      expect(groups.today.map((e) => e.id), ['t']);
      expect(groups.upcoming.map((e) => e.id), ['u']);
      expect(groups.scheduled.map((e) => e.id), ['s']);
      expect(groups.completed.map((e) => e.id), ['c']);
      expect(groups.cancelled.map((e) => e.id), ['x']);
      expect(groups.operationalItems.map((e) => e.id), [
        'o',
        'p',
        't',
        'u',
        's',
      ]);
    });

    test('ordena por scheduledFor ASC dentro do grupo', () {
      final later = view(
        scheduleItem(id: 'b', scheduledFor: now.add(const Duration(days: 5))),
      );
      final earlier = view(
        scheduleItem(id: 'a', scheduledFor: now.add(const Duration(days: 2))),
      );
      final groups = groupScheduleItems([later, earlier]);
      expect(groups.upcoming.map((e) => e.id), ['a', 'b']);
    });

    test('item aparece em exatamente um grupo (sem duplicação)', () {
      final items = [
        view(
          scheduleItem(
            id: 'o',
            scheduledFor: now.subtract(const Duration(days: 2)),
            dueUntil: now.subtract(const Duration(hours: 1)),
          ),
        ),
        view(
          scheduleItem(
            id: 't',
            scheduledFor: now.add(const Duration(hours: 4)),
          ),
        ),
        view(
          scheduleItem(id: 'u', scheduledFor: now.add(const Duration(days: 2))),
        ),
        view(
          scheduleItem(
            id: 's',
            scheduledFor: now.add(const Duration(days: 40)),
          ),
        ),
      ];
      final groups = groupScheduleItems(items);
      final all = [
        ...groups.overdue,
        ...groups.pending,
        ...groups.today,
        ...groups.upcoming,
        ...groups.scheduled,
        ...groups.completed,
        ...groups.cancelled,
      ];
      expect(all.map((e) => e.id).toSet().length, all.length);
      expect(all.map((e) => e.id).toSet(), items.map((e) => e.id).toSet());
    });
  });
}
