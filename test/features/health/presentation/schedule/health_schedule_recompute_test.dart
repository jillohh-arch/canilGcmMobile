import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_controller.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_query.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_health_schedule_source.dart';
import 'schedule_test_helpers.dart';

void main() {
  late FakeHealthScheduleSource source;
  late DateTime clockNow;
  late HealthScheduleController controller;
  var loadCount = 0;

  setUp(() {
    source = FakeHealthScheduleSource();
    clockNow = scheduleTestNow;
    loadCount = 0;
    source.handler = (query) async {
      loadCount++;
      return schedulePage([
        scheduleItem(
          id: 't1',
          scheduledFor: scheduleTestNow.add(const Duration(hours: 5)),
        ),
      ]);
    };
    controller = HealthScheduleController(
      source: source,
      temporalPolicy: testSchedulePolicy(),
      clock: () => clockNow,
    );
  });

  tearDown(() {
    controller.dispose();
    source.reset();
  });

  test(
    'recomputeTemporalStates avança today → pending sem nova leitura',
    () async {
      await controller.setQuery(HealthScheduleQuery(dogId: 'dog-a'));
      expect(controller.state, isA<HealthScheduleData>());
      expect(
        (controller.state as HealthScheduleData).items.single.temporalStatus,
        HealthScheduleTemporalStatus.today,
      );
      final loadsAfterFirst = loadCount;

      // Avança o relógio além de scheduled_for (mesmo due_until implícito).
      clockNow = scheduleTestNow.add(const Duration(hours: 6));
      controller.recomputeTemporalStates();

      expect(loadCount, loadsAfterFirst);
      final data = controller.state as HealthScheduleData;
      expect(
        data.items.single.temporalStatus,
        HealthScheduleTemporalStatus.pending,
      );
      expect(data.groups.today, isEmpty);
      expect(data.groups.pending, hasLength(1));
    },
  );

  test('recomputeTemporalStates pending → overdue sem nova leitura', () async {
    source.handler = (query) async {
      loadCount++;
      return schedulePage([
        scheduleItem(
          id: 'p1',
          scheduledFor: scheduleTestNow.subtract(const Duration(hours: 1)),
          dueUntil: scheduleTestNow.add(const Duration(hours: 2)),
        ),
      ]);
    };
    await controller.setQuery(HealthScheduleQuery(dogId: 'dog-a'));
    expect(
      (controller.state as HealthScheduleData).items.single.temporalStatus,
      HealthScheduleTemporalStatus.pending,
    );
    final loads = loadCount;

    clockNow = scheduleTestNow.add(const Duration(hours: 3));
    controller.recomputeTemporalStates();

    expect(loadCount, loads);
    final data = controller.state as HealthScheduleData;
    expect(
      data.items.single.temporalStatus,
      HealthScheduleTemporalStatus.overdue,
    );
    expect(data.groups.overdue.map((e) => e.id), ['p1']);
  });

  test('recompute após dispose é no-op', () async {
    await controller.setQuery(HealthScheduleQuery(dogId: 'dog-a'));
    controller.dispose();
    clockNow = scheduleTestNow.add(const Duration(days: 2));
    expect(() => controller.recomputeTemporalStates(), returnsNormally);
  });
}
