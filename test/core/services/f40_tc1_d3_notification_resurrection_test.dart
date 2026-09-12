import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/core/domain/notification_item.dart';
import 'package:canil_gcm/core/services/notification_service.dart';

void main() {
  late FakeFirebaseFirestore fakeFirestore;
  late NotificationService notificationService;

  const userA = '990002';
  const userB = '990003';
  const occ1 = 'occ_d3_001';
  const occ2 = 'occ_d3_002';

  final t0 = DateTime(2026, 9, 12, 10, 0); // Occurrence open & participation request
  final t1 = DateTime(2026, 9, 12, 11, 0); // Occurrence finalized

  setUp(() {
    fakeFirestore = FakeFirebaseFirestore();
    notificationService = NotificationService(firestore: fakeFirestore);
    NotificationService.clearDispatchedKeysForTesting();
    notificationService.invalidateCache();
  });

  tearDown(() {
    notificationService.invalidateCache();
  });

  group('D3 — Post-Seal Notification Resurrection Prevention Tests', () {
    test(
      'Full 8-step matrix: participation request is suppressed permanently after finalization across archive, read, restart, and user switch',
      () async {
        // Step 1: participation request while occurrence open => ACTION
        await fakeFirestore
            .collection('notifications')
            .doc(userA)
            .collection('items')
            .doc('notif_part_occ1')
            .set({
          'type': 'occurrence_participation_requested',
          'occurrence_id': occ1,
          'occurrence_title': 'Ocorrência #1',
          'created_at': Timestamp.fromDate(t0),
          'action_required': true,
          'read_at': null,
          'archived_at': null,
          'resolved_at': null,
        });

        final actionsStep1 = <List<NotificationItem>>[];
        var sub = notificationService
            .getOpenActionNotifications(userId: userA)
            .listen(actionsStep1.add);

        await pumpEventQueue();
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(actionsStep1.isNotEmpty, isTrue);
        expect(actionsStep1.last.length, equals(1));
        expect(actionsStep1.last.first.id, equals('notif_part_occ1'));
        expect(actionsStep1.last.first.isOpenAction, isTrue);

        // Step 2: finalized notification arrives => NOT ACTION
        await fakeFirestore
            .collection('notifications')
            .doc(userA)
            .collection('items')
            .doc('notif_finalized_occ1')
            .set({
          'type': 'occurrence_finalized',
          'occurrence_id': occ1,
          'occurrence_title': 'Ocorrência #1',
          'created_at': Timestamp.fromDate(t1),
          'action_required': false,
          'read_at': null,
          'archived_at': null,
          'resolved_at': null,
        });

        await pumpEventQueue();
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(
          actionsStep1.last.isEmpty,
          isTrue,
          reason: 'Finalized occurrence must suppress participation request from open actions',
        );

        // Step 3: finalized notification archived => STILL NOT ACTION (Phantom Resurrection Prevented!)
        await fakeFirestore
            .collection('notifications')
            .doc(userA)
            .collection('items')
            .doc('notif_finalized_occ1')
            .update({
          'archived_at': Timestamp.fromDate(DateTime(2026, 9, 12, 11, 30)),
        });

        await pumpEventQueue();
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(
          actionsStep1.last.isEmpty,
          isTrue,
          reason: 'Archiving finalized notice must NOT resurrect sealed participation request as action',
        );

        // Step 4: finalized notification marked read => STILL NOT ACTION
        await fakeFirestore
            .collection('notifications')
            .doc(userA)
            .collection('items')
            .doc('notif_finalized_occ1')
            .update({
          'read_at': Timestamp.fromDate(DateTime(2026, 9, 12, 11, 35)),
        });

        await pumpEventQueue();
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(
          actionsStep1.last.isEmpty,
          isTrue,
          reason: 'Marking finalized notice read must NOT resurrect sealed participation request',
        );

        // Step 5: notification screen recreated (new subscription) => STILL NOT ACTION
        await sub.cancel();
        final actionsStep5 = <List<NotificationItem>>[];
        sub = notificationService
            .getOpenActionNotifications(userId: userA)
            .listen(actionsStep5.add);

        await pumpEventQueue();
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(actionsStep5.isNotEmpty, isTrue);
        expect(actionsStep5.last.isEmpty, isTrue);

        // Step 6: service/cache recreated as app-restart approximation => STILL NOT ACTION
        await sub.cancel();
        notificationService.invalidateCache();
        final freshService = NotificationService(firestore: fakeFirestore);

        final actionsStep6 = <List<NotificationItem>>[];
        final sub6 = freshService
            .getOpenActionNotifications(userId: userA)
            .listen(actionsStep6.add);

        await pumpEventQueue();
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(actionsStep6.isNotEmpty, isTrue);
        expect(
          actionsStep6.last.isEmpty,
          isTrue,
          reason: 'App restart must compute finalizedOccurrences from full feed and remain suppressed',
        );
        await sub6.cancel();
        freshService.invalidateCache();

        // Step 7: user switch => no cross-user contamination
        // Create an open participation request for userB on occ2 (NOT finalized)
        await fakeFirestore
            .collection('notifications')
            .doc(userB)
            .collection('items')
            .doc('notif_part_occ2')
            .set({
          'type': 'occurrence_participation_requested',
          'occurrence_id': occ2,
          'occurrence_title': 'Ocorrência #2',
          'created_at': Timestamp.fromDate(t0),
          'action_required': true,
          'read_at': null,
          'archived_at': null,
          'resolved_at': null,
        });

        final actionsUserB = <List<NotificationItem>>[];
        final subUserB = notificationService
            .getOpenActionNotifications(userId: userB)
            .listen(actionsUserB.add);

        await pumpEventQueue();
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(actionsUserB.isNotEmpty, isTrue);
        expect(actionsUserB.last.length, equals(1));
        expect(actionsUserB.last.first.id, equals('notif_part_occ2'));
        expect(actionsUserB.last.first.occurrenceId, equals(occ2));

        // Switch back to userA: userA remains clean with 0 actions
        final actionsUserAAfterSwitch = <List<NotificationItem>>[];
        final subUserASwitch = notificationService
            .getOpenActionNotifications(userId: userA)
            .listen(actionsUserAAfterSwitch.add);

        await pumpEventQueue();
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(actionsUserAAfterSwitch.last.isEmpty, isTrue);

        await subUserB.cancel();
        await subUserASwitch.cancel();

        // Step 8: open occurrence participation request without finalization => still ACTION
        // Verified by userB's occ2 above: it had no finalization and correctly stayed ACTION.
        expect(actionsUserB.last.first.isOpenAction, isTrue);
      },
    );

    test('Limit and order boundary: t_finalized > t_participation guarantees inclusion in descending feed', () async {
      // In Firestore: orderBy('created_at', descending: true).limit(N)
      // For any occurrence, finalization is strictly chronologically after participation request creation.
      // Therefore, in descending order, finalization has rank <= participation request rank.
      // If participation request is within the top N, finalization is guaranteed to be within the top N.
      final tRequest = DateTime(2026, 9, 12, 10, 0);
      final tFinalized = DateTime(2026, 9, 12, 12, 0);

      expect(tFinalized.isAfter(tRequest), isTrue);

      // Simulate 5 intervening notifications between request and finalization
      await fakeFirestore
          .collection('notifications')
          .doc(userA)
          .collection('items')
          .doc('req_item')
          .set({
        'type': 'occurrence_participation_requested',
        'occurrence_id': 'occ_bounded',
        'occurrence_title': 'Ocorrência Bounded',
        'created_at': Timestamp.fromDate(tRequest),
        'action_required': true,
        'read_at': null,
      });

      for (var i = 1; i <= 5; i++) {
        await fakeFirestore
            .collection('notifications')
            .doc(userA)
            .collection('items')
            .doc('intervening_$i')
            .set({
          'type': 'vehicle_crew_invitation_accepted',
          'occurrence_id': 'vtr_fake',
          'occurrence_title': 'VTR Fake',
          'created_at': Timestamp.fromDate(tRequest.add(Duration(minutes: i * 10))),
          'action_required': false,
          'read_at': null,
        });
      }

      await fakeFirestore
          .collection('notifications')
          .doc(userA)
          .collection('items')
          .doc('fin_item')
          .set({
        'type': 'occurrence_finalized',
        'occurrence_id': 'occ_bounded',
        'occurrence_title': 'Ocorrência Bounded',
        'created_at': Timestamp.fromDate(tFinalized),
        'action_required': false,
        'read_at': null,
        'archived_at': Timestamp.fromDate(tFinalized), // archived!
      });

      final actions = <List<NotificationItem>>[];
      final sub = notificationService
          .getOpenActionNotifications(userId: userA)
          .listen(actions.add);

      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(actions.isNotEmpty, isTrue);
      // Even with intervening items and finalization archived, the bounded feed includes both,
      // and finalization correctly suppresses the older participation request.
      expect(
        actions.last.any((a) => a.id == 'req_item'),
        isFalse,
      );

      await sub.cancel();
    });
  });
}
