import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/core/domain/notification_item.dart';
import 'package:canil_gcm/core/services/notification_service.dart';

void main() {
  late FakeFirebaseFirestore fakeFirestore;
  late NotificationService notificationService;

  setUp(() {
    fakeFirestore = FakeFirebaseFirestore();
    notificationService = NotificationService(firestore: fakeFirestore);
    NotificationService.clearDispatchedKeysForTesting();
    notificationService.invalidateCache();
  });

  tearDown(() {
    notificationService.invalidateCache();
  });

  group('D1 — Notification Stream Replay & Cache Semantics', () {
    test('late subscriber receives current notifications immediately via replay', () async {
      const userId = '990002';

      // Seed an initial notification in Firestore
      await fakeFirestore
          .collection('notifications')
          .doc(userId)
          .collection('items')
          .doc('notif_1')
          .set({
        'title': 'Ocorrência Atribuída',
        'body': 'Você foi incluído na equipe da ocorrência #101',
        'type': 'occurrence_participation_requested',
        'created_at': DateTime.now().toIso8601String(),
        'action_required': true,
        'read_at': null,
      });

      // Subscriber 1 (e.g. PendingBadge) listens first and consumes the initial snapshot
      final subscriber1Events = <List<NotificationItem>>[];
      final sub1 = notificationService
          .getVisibleNotifications(userId: userId)
          .listen(subscriber1Events.add);

      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(subscriber1Events.isNotEmpty, isTrue);
      expect(subscriber1Events.last.length, equals(1));
      expect(subscriber1Events.last.first.id, equals('notif_1'));

      // Subscriber 2 (e.g. PendingScreen opening late) subscribes after first snapshot was consumed
      final subscriber2Events = <List<NotificationItem>>[];
      final sub2 = notificationService
          .getVisibleNotifications(userId: userId)
          .listen(subscriber2Events.add);

      // Must receive the last known notifications immediately WITHOUT waiting for a new Firestore write
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(subscriber2Events.isNotEmpty, isTrue,
          reason: 'Late subscriber must receive cached snapshot without delay');
      expect(subscriber2Events.first.length, equals(1));
      expect(subscriber2Events.first.first.id, equals('notif_1'));

      await sub1.cancel();
      await sub2.cancel();
    });

    test('subsequent Firestore updates are received by all active subscribers', () async {
      const userId = '990002';

      final subscriber1Events = <List<NotificationItem>>[];
      final sub1 = notificationService
          .getVisibleNotifications(userId: userId)
          .listen(subscriber1Events.add);

      // Seed notif_1
      await fakeFirestore
          .collection('notifications')
          .doc(userId)
          .collection('items')
          .doc('notif_1')
          .set({
        'title': 'Primeira Notificação',
        'body': 'Mensagem 1',
        'type': 'occurrence_opened',
        'created_at': DateTime.now().toIso8601String(),
        'action_required': false,
      });

      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Late subscriber 2 joins
      final subscriber2Events = <List<NotificationItem>>[];
      final sub2 = notificationService
          .getVisibleNotifications(userId: userId)
          .listen(subscriber2Events.add);

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(subscriber2Events.last.length, equals(1));

      // Now add a second notification
      await fakeFirestore
          .collection('notifications')
          .doc(userId)
          .collection('items')
          .doc('notif_2')
          .set({
        'title': 'Segunda Notificação',
        'body': 'Mensagem 2',
        'type': 'occurrence_participation_requested',
        'created_at': DateTime.now().toIso8601String(),
        'action_required': true,
      });

      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Both subscribers should have received the update
      expect(subscriber1Events.last.length, equals(2));
      expect(subscriber2Events.last.length, equals(2));

      await sub1.cancel();
      await sub2.cancel();
    });

    test('invalidateCache clears cached stream and resets state on user switch', () async {
      const userA = '990001';
      const userB = '990002';

      await fakeFirestore
          .collection('notifications')
          .doc(userA)
          .collection('items')
          .doc('notif_a')
          .set({
        'title': 'User A Notif',
        'body': 'Para User A',
        'type': 'occurrence_opened',
        'created_at': DateTime.now().toIso8601String(),
        'action_required': false,
      });

      final userAEvents = <List<NotificationItem>>[];
      final subA = notificationService
          .getVisibleNotifications(userId: userA)
          .listen(userAEvents.add);

      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(userAEvents.last.length, equals(1));

      // Invalidate cache (e.g. logout)
      notificationService.invalidateCache();

      // User B subscribes
      final userBEvents = <List<NotificationItem>>[];
      final subB = notificationService
          .getVisibleNotifications(userId: userB)
          .listen(userBEvents.add);

      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // User B should not receive User A's notifications
      expect(userBEvents.last.isEmpty, isTrue);

      await subA.cancel();
      await subB.cancel();
    });
  });
}
