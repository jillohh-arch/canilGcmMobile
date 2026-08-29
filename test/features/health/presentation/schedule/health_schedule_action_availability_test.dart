import 'package:canil_gcm/features/health/domain/health_schedule_revision.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_action_availability.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_item_view.dart';
import 'package:flutter_test/flutter_test.dart';

import 'schedule_test_helpers.dart';

void main() {
  const rev = HealthScheduleRevision('1');

  group('matriz de ações', () {
    test('manual/open → edit + complete + cancel', () {
      final actions = HealthScheduleActionAvailability.forFields(
        lifecycleStatus: ScheduleLifecycleStatus.open,
        sourceType: ScheduleSourceType.manual,
        revision: rev,
      );
      expect(actions, {
        HealthScheduleItemAction.edit,
        HealthScheduleItemAction.complete,
        HealthScheduleItemAction.cancel,
      });
    });

    test('manual/completed → nenhuma', () {
      final actions = HealthScheduleActionAvailability.forFields(
        lifecycleStatus: ScheduleLifecycleStatus.completed,
        sourceType: ScheduleSourceType.manual,
        revision: rev,
      );
      expect(actions, isEmpty);
    });

    test('manual/cancelled → nenhuma', () {
      final actions = HealthScheduleActionAvailability.forFields(
        lifecycleStatus: ScheduleLifecycleStatus.cancelled,
        sourceType: ScheduleSourceType.manual,
        revision: rev,
      );
      expect(actions, isEmpty);
    });

    test('automatic/open/operator → apenas complete', () {
      for (final source in [
        ScheduleSourceType.treatmentProtocol,
        ScheduleSourceType.clinicalCase,
        ScheduleSourceType.examProcess,
        ScheduleSourceType.preventive,
      ]) {
        final actions = HealthScheduleActionAvailability.forFields(
          lifecycleStatus: ScheduleLifecycleStatus.open,
          sourceType: source,
          revision: rev,
          canCancelAutomaticAsAdmin: false,
        );
        expect(actions, {
          HealthScheduleItemAction.complete,
        }, reason: source.wireName);
        expect(actions.contains(HealthScheduleItemAction.edit), isFalse);
        expect(actions.contains(HealthScheduleItemAction.cancel), isFalse);
      }
    });

    test('automatic/open/admin comprovado → complete + cancel', () {
      final actions = HealthScheduleActionAvailability.forFields(
        lifecycleStatus: ScheduleLifecycleStatus.open,
        sourceType: ScheduleSourceType.preventive,
        revision: rev,
        canCancelAutomaticAsAdmin: true,
      );
      expect(actions, {
        HealthScheduleItemAction.complete,
        HealthScheduleItemAction.cancel,
      });
      expect(actions.contains(HealthScheduleItemAction.edit), isFalse);
    });

    test('automatic/completed e cancelled → nenhuma', () {
      for (final status in [
        ScheduleLifecycleStatus.completed,
        ScheduleLifecycleStatus.cancelled,
      ]) {
        final actions = HealthScheduleActionAvailability.forFields(
          lifecycleStatus: status,
          sourceType: ScheduleSourceType.treatmentProtocol,
          revision: rev,
          canCancelAutomaticAsAdmin: true,
        );
        expect(actions, isEmpty, reason: status.wireName);
      }
    });

    test('item busy → nenhuma ação no forView', () {
      final item = HealthScheduleItemView.fromDomain(
        scheduleItem(sourceType: ScheduleSourceType.manual, revision: rev),
        policy: testSchedulePolicy(),
        now: scheduleTestNow,
      );
      expect(
        HealthScheduleActionAvailability.forView(item, isItemBusy: true),
        isEmpty,
      );
    });
  });
}
