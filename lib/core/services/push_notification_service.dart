import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:canil_gcm/core/services/handler_identity_service.dart';
import 'package:canil_gcm/core/services/notification_service.dart';
import 'package:canil_gcm/features/dogs/data/dog_service.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/occurrences/presentation/screens/active_occurrence_screen.dart';
import 'package:canil_gcm/features/occurrences/presentation/screens/occurrence_review_screen.dart';
import 'package:canil_gcm/features/occurrences/presentation/screens/occurrence_team_screen.dart';
import 'package:canil_gcm/features/shifts/data/vehicle_crew_transition_service.dart';
import 'package:canil_gcm/features/shifts/presentation/screens/vehicle_crew_profile_screen.dart';
import 'package:canil_gcm/features/training/presentation/screens/busca_captura_formacao_screen.dart';
import 'package:canil_gcm/features/training/presentation/screens/training_promotion_request_screen.dart';

const String _operationsChannelId = 'canil_k9_operations';
const String _operationsChannelName = 'Operações K9';
const String _crewAcceptActionId = 'vehicle_crew_accept';
const String _crewDeclineActionId = 'vehicle_crew_decline';

@pragma('vm:entry-point')
Future<void> canilK9FirebaseMessagingBackgroundHandler(
  RemoteMessage message,
) async {
  await PushNotificationService.handleBackgroundMessage(message);
}

@pragma('vm:entry-point')
void canilK9NotificationTapBackground(NotificationResponse response) {
  unawaited(
    PushNotificationService.handleBackgroundNotificationResponse(response),
  );
}

class PushNotificationService {
  static final PushNotificationService _instance =
      PushNotificationService._internal();

  factory PushNotificationService() => _instance;

  PushNotificationService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  GlobalKey<NavigatorState>? _navigatorKey;
  Map<String, dynamic>? _pendingNavigationData;
  bool _localNotificationsReady = false;

  Future<void> initialize({GlobalKey<NavigatorState>? navigatorKey}) async {
    _navigatorKey = navigatorKey ?? _navigatorKey;

    try {
      await _configureLocalNotifications(
        _localNotifications,
        onResponse: _handleNotificationResponse,
        backgroundResponse: canilK9NotificationTapBackground,
      ).timeout(const Duration(seconds: 5));
      _localNotificationsReady = true;
    } catch (e, stack) {
      debugPrint(
        '[PushNotificationService] Falha ao preparar notificacoes: $e',
      );
      debugPrintStack(stackTrace: stack);
    }

    await _runStartupStep(
      'permissao FCM',
      () => _messaging.requestPermission(alert: true, badge: true, sound: true),
    );
    await _runStartupStep(
      'permissao Android de notificacao',
      _requestAndroidNotificationPermission,
    );
    await _runStartupStep(
      'opcoes de apresentacao FCM',
      () => _messaging.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: true,
        sound: true,
      ),
    );

    _authSubscription ??= _auth.authStateChanges().listen((user) {
      if (user != null) {
        _runInBackground('registro de token FCM', _registerCurrentToken(user));
      }
    });

    _tokenSubscription ??= _messaging.onTokenRefresh.listen((token) {
      final user = _auth.currentUser;
      if (user != null) {
        _runInBackground('atualizacao de token FCM', _saveToken(user, token));
      }
    });

    _foregroundSubscription ??= FirebaseMessaging.onMessage.listen(
      _showRemoteNotification,
    );
    _openedSubscription ??= FirebaseMessaging.onMessageOpenedApp.listen(
      _handleRemoteMessageNavigation,
    );

    await _runStartupStep('mensagens iniciais FCM', _handleInitialMessages);

    final user = _auth.currentUser;
    if (user != null) {
      _runInBackground(
        'registro inicial de token FCM',
        _registerCurrentToken(user),
      );
    }
  }

  Future<void> _runStartupStep<T>(
    String label,
    Future<T> Function() task,
  ) async {
    try {
      await task().timeout(const Duration(seconds: 5));
    } catch (e, stack) {
      debugPrint('[PushNotificationService] $label nao bloqueou o app: $e');
      debugPrintStack(stackTrace: stack);
    }
  }

  void _runInBackground(String label, Future<void> future) {
    unawaited(
      future.timeout(const Duration(seconds: 8)).catchError((
        Object e,
        StackTrace stack,
      ) {
        debugPrint('[PushNotificationService] Falha em $label: $e');
        debugPrintStack(stackTrace: stack);
      }),
    );
  }

  static Future<void> handleBackgroundMessage(RemoteMessage message) async {
    await _ensureFirebaseForBackground();
    final plugin = FlutterLocalNotificationsPlugin();
    await _configureLocalNotifications(plugin);
    await _showRemoteNotificationWith(plugin, message);
  }

  static Future<void> handleBackgroundNotificationResponse(
    NotificationResponse response,
  ) async {
    await _ensureFirebaseForBackground();
    final data = _payloadMap(response.payload);
    if (data == null) return;

    if (response.actionId == _crewAcceptActionId) {
      await _handleBackgroundCrewAction(data, accept: true);
      return;
    }

    if (response.actionId == _crewDeclineActionId) {
      final reason = response.input?.trim();
      if (reason == null || reason.isEmpty) {
        await _showActionResultNotification(
          title: 'Motivo obrigatório',
          body: 'Abra o app e informe o motivo para recusar a guarnição.',
        );
        return;
      }
      await _handleBackgroundCrewAction(data, accept: false, reason: reason);
    }
  }

  Future<void> _handleInitialMessages() async {
    final launchDetails = await _localNotifications
        .getNotificationAppLaunchDetails();
    final localResponse = launchDetails?.notificationResponse;
    if (launchDetails?.didNotificationLaunchApp == true &&
        localResponse?.payload != null) {
      _scheduleNavigation(_payloadMap(localResponse!.payload));
      return;
    }

    final remoteMessage = await _messaging.getInitialMessage();
    if (remoteMessage != null) {
      _scheduleNavigation(remoteMessage.data);
    }
  }

  Future<void> _requestAndroidNotificationPermission() async {
    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.requestNotificationsPermission();
  }

  Future<void> _registerCurrentToken(User user) async {
    final token = await _messaging.getToken();
    if (token == null || token.trim().isEmpty) return;
    await _saveToken(user, token);
  }

  Future<void> _saveToken(User user, String token) async {
    final ra = HandlerIdentityService.raFromUser(user);
    if (ra == null || ra.isEmpty) return;

    final tokenHash = sha256.convert(utf8.encode(token)).toString();
    await _firestore
        .collection('users')
        .doc(ra)
        .collection('devices')
        .doc(tokenHash)
        .set({
          'token': token,
          'token_hash': tokenHash,
          'platform': defaultTargetPlatform.name,
          'auth_uid': user.uid,
          'handler_email': user.email,
          'updated_at': FieldValue.serverTimestamp(),
          'created_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  Future<void> _showRemoteNotification(RemoteMessage message) async {
    if (!_localNotificationsReady) return;
    await _showRemoteNotificationWith(_localNotifications, message);
  }

  void _handleRemoteMessageNavigation(RemoteMessage message) {
    _scheduleNavigation(message.data);
  }

  void _handleNotificationResponse(NotificationResponse response) {
    final data = _payloadMap(response.payload);
    if (data == null) return;

    if (response.actionId == _crewAcceptActionId) {
      unawaited(_handleCrewAction(data, accept: true));
      return;
    }

    if (response.actionId == _crewDeclineActionId) {
      final reason = response.input?.trim();
      if (reason == null || reason.isEmpty) {
        _scheduleNavigation(data);
        return;
      }
      unawaited(_handleCrewAction(data, accept: false, reason: reason));
      return;
    }

    _scheduleNavigation(data);
  }

  Future<void> _handleCrewAction(
    Map<String, dynamic> data, {
    required bool accept,
    String? reason,
  }) async {
    try {
      await _respondToCrewInvitation(data, accept: accept, reason: reason);
      await _markNotificationAsRead(data);
      if (accept) return;
    } catch (error) {
      debugPrint('[PushNotificationService] Ação da guarnição falhou: $error');
    }
    _scheduleNavigation(data);
  }

  Future<void> _markNotificationAsRead(Map<String, dynamic> data) async {
    final user = _auth.currentUser;
    final notificationId = _stringValue(data['notification_id']);
    final userId = HandlerIdentityService.raFromUser(user);
    if (userId == null || notificationId == null) return;
    await NotificationService().markAsRead(
      userId: userId,
      notificationId: notificationId,
    );
  }

  void _scheduleNavigation(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) return;
    _pendingNavigationData = data;
    WidgetsBinding.instance.addPostFrameCallback((_) => _flushNavigation());
  }

  void _flushNavigation() {
    final data = _pendingNavigationData;
    final navigator = _navigatorKey?.currentState;
    final context = _navigatorKey?.currentContext;
    if (data == null || navigator == null || context == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _flushNavigation());
      return;
    }

    _pendingNavigationData = null;
    final target = _targetScreen(data);
    if (target == 'training_promotion_request' ||
        _isTrainingPromotionType(data)) {
      final requestId = _promotionRequestIdFromPayload(data);
      if (requestId == null) return;
      navigator.push(
        MaterialPageRoute(
          builder: (_) => TrainingPromotionRequestScreen(requestId: requestId),
        ),
      );
      return;
    }
    if (target == 'training_bonus_milestone' || _isTrainingBonusType(data)) {
      final dogId = _stringValue(data['dog_id']);
      final modality = _stringValue(data['modality']);
      if (dogId == null || modality != 'busca_captura') return;
      navigator.push(
        MaterialPageRoute(
          builder: (_) => _TrainingBonusMilestoneRoute(dogId: dogId),
        ),
      );
      return;
    }
    if (target == 'vehicle_crew' || _isVehicleCrewType(data)) {
      final crewId = _crewIdFromPayload(data);
      if (crewId == null) return;
      navigator.push(
        MaterialPageRoute(
          builder: (_) => VehicleCrewProfileScreen(crewId: crewId),
        ),
      );
      return;
    }

    final occurrenceId = _stringValue(data['occurrence_id']);
    if (occurrenceId == null) return;
    if (_opensActiveOccurrence(data)) {
      navigator.push(
        MaterialPageRoute(
          builder: (_) => ActiveOccurrenceScreen(occurrenceId: occurrenceId),
        ),
      );
      return;
    }
    if (_opensSignatureReview(data)) {
      navigator.push(
        MaterialPageRoute(
          builder: (_) => OccurrenceReviewScreen(occurrenceId: occurrenceId),
        ),
      );
      return;
    }
    navigator.push(
      MaterialPageRoute(
        builder: (_) => OccurrenceTeamScreen(occurrenceId: occurrenceId),
      ),
    );
  }

  Future<void> dispose() async {
    await _authSubscription?.cancel();
    await _tokenSubscription?.cancel();
    await _foregroundSubscription?.cancel();
    await _openedSubscription?.cancel();
    _authSubscription = null;
    _tokenSubscription = null;
    _foregroundSubscription = null;
    _openedSubscription = null;
  }
}

Future<void> _configureLocalNotifications(
  FlutterLocalNotificationsPlugin plugin, {
  DidReceiveNotificationResponseCallback? onResponse,
  DidReceiveBackgroundNotificationResponseCallback? backgroundResponse,
}) async {
  const androidSettings = AndroidInitializationSettings('ic_launcher');
  final initializationSettings = InitializationSettings(
    android: androidSettings,
    iOS: DarwinInitializationSettings(
      notificationCategories: [
        DarwinNotificationCategory(
          'vehicle_crew_invitation',
          actions: [
            DarwinNotificationAction.plain(
              _crewAcceptActionId,
              'Aceitar',
              options: {DarwinNotificationActionOption.authenticationRequired},
            ),
            DarwinNotificationAction.text(
              _crewDeclineActionId,
              'Recusar',
              buttonTitle: 'Enviar',
              placeholder: 'Motivo da recusa',
              options: {DarwinNotificationActionOption.authenticationRequired},
            ),
          ],
        ),
      ],
    ),
  );

  await plugin.initialize(
    settings: initializationSettings,
    onDidReceiveNotificationResponse: onResponse,
    onDidReceiveBackgroundNotificationResponse: backgroundResponse,
  );

  final androidPlugin = plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
  await androidPlugin?.createNotificationChannel(
    const AndroidNotificationChannel(
      _operationsChannelId,
      _operationsChannelName,
      description: 'Alertas operacionais do Canil K9',
      importance: Importance.high,
    ),
  );
}

Future<void> _showRemoteNotificationWith(
  FlutterLocalNotificationsPlugin plugin,
  RemoteMessage message,
) async {
  final data = Map<String, dynamic>.from(message.data);
  final title =
      _stringValue(data['title']) ?? message.notification?.title ?? 'Canil K9';
  final body =
      _stringValue(data['body']) ??
      message.notification?.body ??
      'Nova pendência operacional.';
  final type = _stringValue(data['type']) ?? '';
  final payload = jsonEncode(data);

  final androidDetails = AndroidNotificationDetails(
    _operationsChannelId,
    _operationsChannelName,
    channelDescription: 'Alertas operacionais do Canil K9',
    importance: Importance.high,
    priority: Priority.high,
    category: AndroidNotificationCategory.status,
    color: AppTheme.primary,
    actions: type == 'vehicle_crew_invitation'
        ? const [
            AndroidNotificationAction(
              _crewAcceptActionId,
              'Aceitar',
              showsUserInterface: false,
              semanticAction: SemanticAction.markAsRead,
            ),
            AndroidNotificationAction(
              _crewDeclineActionId,
              'Recusar',
              showsUserInterface: false,
              semanticAction: SemanticAction.reply,
              inputs: [
                AndroidNotificationActionInput(label: 'Motivo da recusa'),
              ],
            ),
          ]
        : null,
  );

  const darwinDetails = DarwinNotificationDetails(
    categoryIdentifier: 'vehicle_crew_invitation',
  );

  await plugin.show(
    id: _notificationIdFor(data),
    title: title,
    body: body,
    notificationDetails: NotificationDetails(
      android: androidDetails,
      iOS: type == 'vehicle_crew_invitation' ? darwinDetails : null,
    ),
    payload: payload,
  );
}

Future<void> _respondToCrewInvitation(
  Map<String, dynamic> data, {
  required bool accept,
  String? reason,
}) async {
  final crewId = _crewIdFromPayload(data);
  if (crewId == null) return;
  await VehicleCrewTransitionService().respondToInvitation(
    crewId: crewId,
    accept: accept,
    reason: reason,
  );
}

Future<void> _handleBackgroundCrewAction(
  Map<String, dynamic> data, {
  required bool accept,
  String? reason,
}) async {
  try {
    await _respondToCrewInvitation(data, accept: accept, reason: reason);
    await _markNotificationAsReadFromPayload(data);
    await _showActionResultNotification(
      title: accept ? 'Convite aceito' : 'Convite recusado',
      body: accept
          ? 'Você entrou na guarnição.'
          : 'Sua recusa foi registrada com justificativa.',
    );
  } catch (error) {
    await _showActionResultNotification(
      title: 'Ação não concluída',
      body: 'Abra o app para responder ao convite da guarnição.',
    );
  }
}

Future<void> _markNotificationAsReadFromPayload(
  Map<String, dynamic> data,
) async {
  final user = FirebaseAuth.instance.currentUser;
  final userId = HandlerIdentityService.raFromUser(user);
  final notificationId = _stringValue(data['notification_id']);
  if (userId == null || notificationId == null) return;
  await NotificationService().markAsRead(
    userId: userId,
    notificationId: notificationId,
  );
}

Future<void> _showActionResultNotification({
  required String title,
  required String body,
}) async {
  final plugin = FlutterLocalNotificationsPlugin();
  await _configureLocalNotifications(plugin);
  await plugin.show(
    id: _notificationIdFor({'title': title, 'body': body}),
    title: title,
    body: body,
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        _operationsChannelId,
        _operationsChannelName,
        importance: Importance.high,
        priority: Priority.high,
      ),
    ),
  );
}

Future<void> _ensureFirebaseForBackground() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } on FirebaseException catch (error) {
    if (error.code != 'duplicate-app') rethrow;
  }
}

Map<String, dynamic>? _payloadMap(String? payload) {
  if (payload == null || payload.trim().isEmpty) return null;
  final decoded = jsonDecode(payload);
  if (decoded is Map<String, dynamic>) return decoded;
  if (decoded is Map) return Map<String, dynamic>.from(decoded);
  return null;
}

String? _crewIdFromPayload(Map<String, dynamic> data) {
  return _stringValue(data['crew_id']) ??
      _stringValue(data['additional_data']) ??
      _stringValue(data['vehicle_crew_id']);
}

String _targetScreen(Map<String, dynamic> data) {
  return _stringValue(data['target_screen']) ?? '';
}

bool _isVehicleCrewType(Map<String, dynamic> data) {
  return (_stringValue(data['type']) ?? '').startsWith('vehicle_crew_');
}

bool _isTrainingPromotionType(Map<String, dynamic> data) {
  return (_stringValue(data['type']) ?? '').startsWith('training_promotion_');
}

bool _isTrainingBonusType(Map<String, dynamic> data) {
  return (_stringValue(data['type']) ?? '') ==
      'training_bonus_milestone_available';
}

String? _promotionRequestIdFromPayload(Map<String, dynamic> data) {
  return _stringValue(data['promotion_request_id']) ??
      _stringValue(data['additional_data']);
}

bool _opensActiveOccurrence(Map<String, dynamic> data) {
  final target = _targetScreen(data);
  final type = _stringValue(data['type']) ?? '';
  return target == 'occurrence_active' ||
      type == 'occurrence_participation_requested' ||
      type == 'correction_requested';
}

bool _opensSignatureReview(Map<String, dynamic> data) {
  final target = _targetScreen(data);
  final type = _stringValue(data['type']) ?? '';
  return type == 'signature_requested' || target == 'occurrence_review';
}

String? _stringValue(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

class _TrainingBonusMilestoneRoute extends StatelessWidget {
  const _TrainingBonusMilestoneRoute({required this.dogId});

  final String dogId;

  @override
  Widget build(BuildContext context) {
    final dogService = DogService();
    return StreamBuilder<Dog?>(
      stream: dogService.watchDog(dogId),
      builder: (context, snapshot) {
        final dog = snapshot.data;
        if (dog != null) {
          return BuscaCapturaFormacaoScreen(dog: dog);
        }
        if (snapshot.hasError) {
          return Scaffold(
            backgroundColor: AppTheme.background,
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Falha ao abrir o treino do cao. ${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.textPrimary),
                ),
              ),
            ),
          );
        }
        return const Scaffold(
          backgroundColor: AppTheme.background,
          body: Center(child: CircularProgressIndicator()),
        );
      },
    );
  }
}

int _notificationIdFor(Map<String, dynamic> data) {
  final source =
      _stringValue(data['notification_id']) ??
      _stringValue(data['occurrence_id']) ??
      jsonEncode(data);
  final digest = sha256.convert(utf8.encode(source)).toString();
  return int.parse(digest.substring(0, 7), radix: 16);
}
