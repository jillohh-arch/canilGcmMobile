import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/core/domain/notification_item.dart';

void main() {
  group('NotificationItem', () {
    test('keeps read and resolved state independent', () {
      final createdAt = DateTime.utc(2026, 6, 2, 12);
      final readAt = DateTime.utc(2026, 6, 2, 12, 5);

      final item = NotificationItem.fromJson({
        'type': 'training_promotion_requested',
        'occurrence_id': '',
        'occurrence_title': 'Bono - Modulo 1',
        'created_at': Timestamp.fromDate(createdAt),
        'read_at': Timestamp.fromDate(readAt),
        'action_required': true,
        'resolved_at': null,
        'target_screen': 'training_promotion_request',
        'additional_data': 'request-1',
        'promotion_request_id': 'request-1',
        'dog_id': 'dog-1',
        'module_id': 'module-1',
      }, 'notification-1');

      expect(item.isUnread, isFalse);
      expect(item.isResolved, isFalse);
      expect(item.isOpenAction, isTrue);
      expect(item.resolvedPromotionRequestId, 'request-1');
      expect(item.targetScreen, 'training_promotion_request');
      expect(item.dogId, 'dog-1');
      expect(item.moduleId, 'module-1');
    });

    test('does not count resolved action as open action', () {
      final now = DateTime.utc(2026, 6, 2, 12);

      final item = NotificationItem.fromJson({
        'type': 'signature_requested',
        'occurrence_id': 'occ-1',
        'occurrence_title': 'Ocorrencia',
        'created_at': Timestamp.fromDate(now),
        'read_at': null,
        'action_required': true,
        'resolved_at': Timestamp.fromDate(now.add(const Duration(minutes: 8))),
      }, 'notification-2');

      expect(item.isUnread, isTrue);
      expect(item.isResolved, isTrue);
      expect(item.isOpenAction, isFalse);
      expect(item.isNotice, isTrue);
    });

    test('treats archived notices as hidden but still non destructive', () {
      final now = DateTime.utc(2026, 6, 2, 12);

      final item = NotificationItem.fromJson({
        'type': 'training_promotion_approved',
        'occurrence_id': '',
        'occurrence_title': 'Apolo - Modulo 3',
        'created_at': Timestamp.fromDate(now),
        'read_at': null,
        'action_required': false,
        'archived_at': Timestamp.fromDate(now.add(const Duration(hours: 1))),
      }, 'notification-3');

      expect(item.isOpenAction, isFalse);
      expect(item.canBeArchived, isTrue);
      expect(item.isArchived, isTrue);
    });
  });
}
