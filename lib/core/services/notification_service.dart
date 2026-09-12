import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'package:canil_gcm/core/domain/notification_item.dart';
import 'package:canil_gcm/core/services/handler_identity_service.dart';

typedef NotificationWriter = Future<void> Function(
  DocumentReference document,
  Map<String, dynamic> data,
);

class NotificationService {
  static final Set<String> _dispatchedNotificationKeys = <String>{};

  @visibleForTesting
  static void clearDispatchedKeysForTesting() {
    _dispatchedNotificationKeys.clear();
  }

  static NotificationService? _instance;
  factory NotificationService({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    FirebaseAuth? auth,
    NotificationWriter? notificationWriter,
  }) {
    if (firestore != null ||
        functions != null ||
        auth != null ||
        notificationWriter != null) {
      return NotificationService._custom(
        firestore: firestore,
        functions: functions,
        auth: auth,
        notificationWriter: notificationWriter,
      );
    }
    return _instance ??= NotificationService._internal();
  }

  NotificationService._internal()
    : _firestore = null,
      _functions = null,
      _auth = null,
      _notificationWriter = null;

  NotificationService._custom({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    FirebaseAuth? auth,
    NotificationWriter? notificationWriter,
  }) : _firestore = firestore,
       _functions = functions,
       _auth = auth,
       _notificationWriter = notificationWriter;

  final FirebaseFirestore? _firestore;
  final FirebaseFunctions? _functions;
  final FirebaseAuth? _auth;
  final NotificationWriter? _notificationWriter;

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

  // Cache do stream base compartilhado com replay do último valor conhecido.
  // pending_badge, binomio_header e pending_screen consomem
  // getOpenActionCount/getVisibleNotifications, que derivam de getAllNotifications.
  // Sem replay, ouvintes tardios (ex.: PendingScreen ao abrir após a badge já ter
  // consumido o snapshot inicial) ficam em espera infinita por nova alteração.
  // O replay entrega o snapshot mais recente imediatamente ao novo ouvinte.
  String? _cachedUserId;
  StreamController<List<NotificationItem>>? _cachedController;
  StreamSubscription<List<NotificationItem>>? _firestoreSubscription;
  List<NotificationItem>? _lastKnownNotifications;

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

    final dispatchKey = '$userId:$resolvedNotificationId';
    if (deduplicate && _dispatchedNotificationKeys.contains(dispatchKey)) {
      debugPrint(
        '[NotificationService] Notificação duplicada já enviada ignorada para $userId: $resolvedNotificationId',
      );
      return resolvedNotificationId;
    }

    try {
      if (deduplicate && _isOwnNotification(userId)) {
        final existing = await docRef.get();
        if (existing.exists) {
          debugPrint(
            '[NotificationService] Notificação duplicada ignorada para $userId: $resolvedNotificationId',
          );
          _dispatchedNotificationKeys.add(dispatchKey);
          return resolvedNotificationId;
        }
      }
      await (_notificationWriter?.call(docRef, data) ?? docRef.set(data));
      if (deduplicate) {
        _dispatchedNotificationKeys.add(dispatchKey);
      }
      debugPrint(
        '[NotificationService] Notificação criada: $type para $userId ($resolvedNotificationId)',
      );
    } on FirebaseException catch (e) {
      // R3: nunca engolir permission-denied genérico. Falhas reais de segurança
      // (escritor não autorizado N4, payload inválido N5, destinatário errado N6)
      // DEVEM propagar para que o chamador observe a falha. Duplicatas legítimas
      // em mesma sessão são suprimidas benignamente por _dispatchedNotificationKeys;
      // falhas de segurança reais nunca chegam a registrar a chave e sempre propagam.
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
  ///
  /// D3: Ocorrências seladas não podem reter solicitações impossíveis de ciência
  /// sob contagem acionável. Se o feed já possui `occurrenceFinalized` daquela
  /// ocorrência, a pendência de participação é desqualificada de ação aberta.
  Stream<List<NotificationItem>> getOpenActionNotifications({
    required String userId,
  }) {
    return getVisibleNotifications(
      userId: userId,
    ).map((items) {
      final finalizedOccurrenceIds = items
          .where((item) =>
              item.type == NotificationType.occurrenceFinalized &&
              item.occurrenceId.isNotEmpty)
          .map((item) => item.occurrenceId)
          .toSet();

      return items
          .where((item) =>
              item.isOpenAction &&
              !(item.type == NotificationType.occurrenceParticipationRequested &&
                  finalizedOccurrenceIds.contains(item.occurrenceId)))
          .toList();
    });
  }

  /// Obtém todas as notificações de um usuário.
  ///
  /// O stream é cacheado como broadcast compartilhado por userId com replay do
  /// último valor conhecido. pending_badge, binomio_header e pending_screen
  /// derivam daqui, consumindo um único listener Firestore simultâneo.
  /// Ouvintes subsequentes recebem imediatamente o snapshot em memória,
  /// evitando starvation/loading infinito em telas abertas tardiamente.
  Stream<List<NotificationItem>> getAllNotifications({required String userId}) {
    if (_cachedUserId != userId) {
      invalidateCache();
      _cachedUserId = userId;
    }

    if (_cachedController == null) {
      _cachedController = StreamController<List<NotificationItem>>.broadcast();
      _firestoreSubscription = _notificationsCollection
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
          .listen(
            (items) {
              _lastKnownNotifications = items;
              if (_cachedController != null && !_cachedController!.isClosed) {
                _cachedController!.add(items);
              }
            },
            onError: (err, stack) {
              if (_cachedController != null && !_cachedController!.isClosed) {
                _cachedController!.addError(err, stack);
              }
            },
          );
    }

    late final StreamController<List<NotificationItem>> subscriberController;
    StreamSubscription<List<NotificationItem>>? liveSubscription;

    subscriberController = StreamController<List<NotificationItem>>(
      onListen: () {
        if (_lastKnownNotifications != null) {
          subscriberController.add(_lastKnownNotifications!);
        }
        liveSubscription = _cachedController!.stream.listen(
          (items) {
            if (!subscriberController.isClosed) {
              subscriberController.add(items);
            }
          },
          onError: (err, stack) {
            if (!subscriberController.isClosed) {
              subscriberController.addError(err, stack);
            }
          },
          onDone: () {
            if (!subscriberController.isClosed) {
              subscriberController.close();
            }
          },
        );
      },
      onCancel: () async {
        await liveSubscription?.cancel();
      },
    );

    return subscriberController.stream;
  }

  /// Invalida o cache ao trocar de usuário (ex: logout/login).
  void invalidateCache() {
    _cachedUserId = null;
    _lastKnownNotifications = null;
    _firestoreSubscription?.cancel();
    _firestoreSubscription = null;
    _cachedController?.close();
    _cachedController = null;
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
