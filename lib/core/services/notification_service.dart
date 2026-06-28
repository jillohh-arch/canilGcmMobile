import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import 'package:canil_gcm/core/domain/notification_item.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final CollectionReference _notificationsCollection = FirebaseFirestore
      .instance
      .collection('notifications');
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'southamerica-east1',
  );

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
      data['resolved_at'] = null;
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
  Future<void> archiveNotice({
    required String userId,
    required NotificationItem notification,
  }) async {
    if (!notification.canBeArchived) {
      throw StateError('Pendencia aberta nao pode ser limpa.');
    }

    await _notificationsCollection
        .doc(userId)
        .collection('items')
        .doc(notification.id)
        .update({'archived_at': FieldValue.serverTimestamp()});

    debugPrint('[NotificationService] Aviso arquivado: ${notification.id}');
  }

  /// Arquiva todos os avisos elegiveis de uma lista pre-filtrada em memoria.
  ///
  /// Parte 14: notificacoes nunca sao deletadas. Apenas soft-archive via
  /// [archived_at]. Pendencias abertas ([isOpenAction]) sao excluidas.
  /// Fragmenta em blocos de ate 400 operacoes por batch.
  Future<int> archiveAllNotices({
    required String userId,
    required List<NotificationItem> notifications,
  }) async {
    final toArchive = notifications
        .where((n) => n.canBeArchived && !n.isArchived)
        .toList();

    if (toArchive.isEmpty) return 0;

    int archived = 0;
    const batchSize = 400;

    for (var i = 0; i < toArchive.length; i += batchSize) {
      final batch = FirebaseFirestore.instance.batch();
      final chunk = toArchive.skip(i).take(batchSize);

      for (final notice in chunk) {
        batch.update(
          _notificationsCollection
              .doc(userId)
              .collection('items')
              .doc(notice.id),
          {'archived_at': FieldValue.serverTimestamp()},
        );
      }

      await batch.commit();
      archived += chunk.length;
    }

    debugPrint(
      '[NotificationService] $archived avisos arquivados para $userId',
    );
    return archived;
  }

  Future<void> resolveShiftReminderNotification({
    required String notificationId,
  }) async {
    final callable = _functions.httpsCallable(
      'resolveShiftReminderNotification',
    );
    await callable.call<void>({'notification_id': notificationId});
  }

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

  /// Obtém notificações visíveis para a central.
  ///
  /// Avisos arquivados ficam fora da caixa de entrada, mas o registro
  /// operacional original permanece intacto na entidade de origem.
  Stream<List<NotificationItem>> getVisibleNotifications({
    required String userId,
  }) {
    return getAllNotifications(
      userId: userId,
    ).map((items) => items.where((item) => !item.isArchived).toList());
  }

  /// Obtém pendências acionáveis ainda não resolvidas.
  ///
  /// Este stream é propositalmente derivado do modelo em memória, sem query
  /// composta, para evitar depender de índice enquanto a migração/backfill roda.
  Stream<List<NotificationItem>> getOpenActionNotifications({
    required String userId,
  }) {
    return getVisibleNotifications(
      userId: userId,
    ).map((items) => items.where((item) => item.isOpenAction).toList());
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

  /// Conta somente pendências reais: action_required == true && resolved_at == null.
  Stream<int> getOpenActionCount({required String userId}) {
    return getOpenActionNotifications(
      userId: userId,
    ).map((items) => items.length);
  }

  /// Mantido temporariamente por compatibilidade.
  ///
  /// Parte 14: notificações não devem ser deletadas pelo app. O fluxo de
  /// limpeza será `archived_at` apenas para avisos, com rules próprias.
  @Deprecated(
    'Use soft-archive com archived_at; notificacoes nao sao deletadas.',
  )
  Future<void> cleanupOldNotifications({
    required String userId,
    required Duration olderThan,
  }) async {
    debugPrint(
      '[NotificationService] cleanupOldNotifications bloqueado para $userId '
      '(${olderThan.inDays}d): Parte 14 exige archived_at, nunca delete.',
    );
  }
}
