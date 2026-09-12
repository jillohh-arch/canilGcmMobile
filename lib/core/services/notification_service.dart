import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'package:canil_gcm/core/domain/notification_item.dart';
import 'package:canil_gcm/core/services/handler_identity_service.dart';

class NotificationService {
  static NotificationService? _instance;
  factory NotificationService({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    FirebaseAuth? auth,
  }) {
    if (firestore != null || functions != null || auth != null) {
      return NotificationService._custom(
        firestore: firestore,
        functions: functions,
        auth: auth,
      );
    }
    return _instance ??= NotificationService._internal();
  }

  NotificationService._internal()
    : _firestore = null,
      _functions = null,
      _auth = null;

  NotificationService._custom({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    FirebaseAuth? auth,
  }) : _firestore = firestore,
       _functions = functions,
       _auth = auth;

  final FirebaseFirestore? _firestore;
  final FirebaseFunctions? _functions;
  final FirebaseAuth? _auth;

  CollectionReference get _notificationsCollection =>
      (_firestore ?? FirebaseFirestore.instance).collection('notifications');

  bool _isOwnNotification(String userId) {
    try {
      final auth = _auth ?? FirebaseAuth.instance;
      final currentRa = HandlerIdentityService.raFromUser(auth.currentUser);
      if (currentRa != null && currentRa.isNotEmpty) {
        return currentRa.toLowerCase() == userId.trim().toLowerCase();
      }
    } catch (_) {}
    return false;
  }

  // Cache do stream base compartilhado. pending_badge, binomio_header e
  // pending_screen consomem getOpenActionCount/getVisibleNotifications, que
  // derivam de getAllNotifications — sem cache isso abre 3 listeners Firestore
  // simultâneos na mesma subcoleção. Com broadcast + cache por userId, fica 1.
  String? _cachedUserId;
  Stream<List<NotificationItem>>? _cachedAllStream;

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

    try {
      if (deduplicate && _isOwnNotification(userId)) {
        final existing = await docRef.get();
        if (existing.exists) {
          debugPrint(
            '[NotificationService] Notificação duplicada ignorada para $userId: $resolvedNotificationId',
          );
          return resolvedNotificationId;
        }
      }
      await docRef.set(data);
      debugPrint(
        '[NotificationService] Notificação criada: $type para $userId ($resolvedNotificationId)',
      );
    } on FirebaseException catch (e) {
      if (deduplicate &&
          e.code == 'permission-denied' &&
          !_isOwnNotification(userId)) {
        // Notificação cross-user: sob firestore.rules, integrantes da equipe possuem
        // permissão 'create', mas 'update' é restrito ao próprio dono da coleção.
        // Quando um ID determinístico já existe, o set() é avaliado pelas regras como 'update'
        // e retorna permission-denied. Em modo deduplicate, se o doc já foi criado por chamada
        // anterior, trata-se de duplicata idempotente esperada.
        debugPrint(
          '[NotificationService] Aviso idempotente: gravação cross-user para $userId '
          '($resolvedNotificationId) já existe ou foi negada por regras: ${e.message}',
        );
        return resolvedNotificationId;
      }
      debugPrint(
        '[NotificationService] Erro ao criar notificação $type para $userId: $e',
      );
      rethrow;
    } catch (e) {
      debugPrint(
        '[NotificationService] Erro inesperado ao criar notificação $type para $userId: $e',
      );
      rethrow;
    }

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
      final batch = (_firestore ?? FirebaseFirestore.instance).batch();
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
    final functions =
        _functions ??
        FirebaseFunctions.instanceFor(region: 'southamerica-east1');
    final callable = functions.httpsCallable(
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
  ///
  /// O stream é cacheado como broadcast por userId: pending_badge,
  /// binomio_header e pending_screen derivam daqui, então um único listener
  /// Firestore serve a todos. limit(200) evita crescimento ilimitado de leitura.
  Stream<List<NotificationItem>> getAllNotifications({required String userId}) {
    if (_cachedUserId != userId || _cachedAllStream == null) {
      _cachedUserId = userId;
      _cachedAllStream = _notificationsCollection
          .doc(userId)
          .collection('items')
          .orderBy('created_at', descending: true)
          .limit(200)
          .snapshots()
          .map(
            (snapshot) => snapshot.docs
                .map((doc) => NotificationItem.fromJson(doc.data(), doc.id))
                .toList(),
          )
          .asBroadcastStream();
    }
    return _cachedAllStream!;
  }

  /// Invalida o cache ao trocar de usuário (ex: logout/login).
  void invalidateCache() {
    _cachedUserId = null;
    _cachedAllStream = null;
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
