import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:canil_gcm/core/domain/notification_item.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final CollectionReference _notificationsCollection = FirebaseFirestore
      .instance
      .collection('notifications');

  /// Cria uma nova notificação para um usuário.
  Future<String> createNotification({
    required String userId,
    required NotificationType type,
    required String occurrenceId,
    required String occurrenceTitle,
    String? additionalData,
    String? notificationId,
    bool deduplicate = false,
    String? targetScreen,
    bool actionRequired = false,
  }) async {
    final resolvedNotificationId =
        notificationId ?? _notificationsCollection.doc().id;
    final notification = NotificationItem(
      id: resolvedNotificationId,
      type: type,
      occurrenceId: occurrenceId,
      occurrenceTitle: occurrenceTitle,
      createdAt: DateTime.now(),
      additionalData: additionalData,
    );

    final docRef = _notificationsCollection
        .doc(userId)
        .collection('items')
        .doc(resolvedNotificationId);
    final data = notification.toJson();
    final resolvedTarget = targetScreen?.trim();
    if (resolvedTarget != null && resolvedTarget.isNotEmpty) {
      data['target_screen'] = resolvedTarget;
    }
    if (actionRequired) {
      data['action_required'] = true;
    }

    if (deduplicate) {
      final existing = await docRef.get();
      if (!existing.exists) {
        await docRef.set(data);
      }
    } else {
      await docRef.set(data);
    }

    debugPrint('[NotificationService] Notificação criada: $type para $userId');
    return resolvedNotificationId;
  }

  /// Marca uma notificação como lida.
  Future<void> markAsRead({
    required String userId,
    required String notificationId,
  }) async {
    await _notificationsCollection
        .doc(userId)
        .collection('items')
        .doc(notificationId)
        .update({'read_at': FieldValue.serverTimestamp()});

    debugPrint(
      '[NotificationService] Notificação marcada como lida: $notificationId',
    );
  }

  /// Marca todas as notificações como lidas.
  Future<void> markAllAsRead({required String userId}) async {
    final batch = FirebaseFirestore.instance.batch();
    final notifications = await _notificationsCollection
        .doc(userId)
        .collection('items')
        .where('read_at', isNull: true)
        .get();

    for (final doc in notifications.docs) {
      batch.update(doc.reference, {'read_at': FieldValue.serverTimestamp()});
    }

    if (notifications.docs.isNotEmpty) {
      await batch.commit();
      debugPrint(
        '[NotificationService] ${notifications.docs.length} notificações marcadas como lidas',
      );
    }
  }

  /// Obtém as notificações não lidas de um usuário.
  Stream<List<NotificationItem>> getUnreadNotifications({
    required String userId,
  }) {
    return _notificationsCollection
        .doc(userId)
        .collection('items')
        .where('read_at', isNull: true)
        .orderBy('created_at', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => NotificationItem.fromJson(doc.data(), doc.id))
              .toList(),
        );
  }

  /// Obtém todas as notificações de um usuário.
  Stream<List<NotificationItem>> getAllNotifications({required String userId}) {
    return _notificationsCollection
        .doc(userId)
        .collection('items')
        .orderBy('created_at', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => NotificationItem.fromJson(doc.data(), doc.id))
              .toList(),
        );
  }

  /// Conta notificações não lidas.
  Stream<int> getUnreadCount({required String userId}) {
    return _notificationsCollection
        .doc(userId)
        .collection('items')
        .where('read_at', isNull: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  /// Remove notificações antigas.
  Future<void> cleanupOldNotifications({
    required String userId,
    required Duration olderThan,
  }) async {
    final cutoff = DateTime.now().subtract(olderThan);
    final notifications = await _notificationsCollection
        .doc(userId)
        .collection('items')
        .where('created_at', isLessThan: Timestamp.fromDate(cutoff))
        .get();

    final batch = FirebaseFirestore.instance.batch();
    for (final doc in notifications.docs) {
      batch.delete(doc.reference);
    }

    if (notifications.docs.isNotEmpty) {
      await batch.commit();
      debugPrint(
        '[NotificationService] ${notifications.docs.length} notificações antigas removidas',
      );
    }
  }
}
