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
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'package:canil_gcm/core/services/handler_identity_service.dart';
import 'package:canil_gcm/core/services/notification_service.dart';
import 'package:canil_gcm/features/occurrences/presentation/screens/active_occurrence_screen.dart';
import 'package:canil_gcm/features/occurrences/presentation/screens/occurrence_review_screen.dart';
import 'package:canil_gcm/features/occurrences/presentation/screens/occurrence_team_screen.dart';
import 'package:canil_gcm/features/shifts/presentation/screens/active_shift_dashboard_screen.dart';
import 'package:canil_gcm/features/shifts/presentation/screens/shift_assumption_screen.dart';
import 'package:canil_gcm/features/shifts/presentation/screens/vehicle_crew_profile_screen.dart';
import 'package:canil_gcm/features/training/presentation/screens/training_log_screen.dart';
import 'package:canil_gcm/features/training/presentation/screens/training_promotion_request_screen.dart';

const String _operationsChannelId = 'canil_k9_operations';
const String _operationsChannelName = 'Operações K9';
const int _shiftEndReminderNotificationId = 910101;
const int _shiftOverdueReminderNotificationId = 910102;
const String _shiftTimeZone = 'America/Sao_Paulo';

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
  bool _timeZonesReady = false;

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
    if (message.notification != null) return;
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

    // Navigation will be handled when the app opens
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

  Future<void> scheduleShiftEndReminders({
    required DateTime expectedEndAt,
    required String shiftId,
    required String shiftGroupLabel,
    Duration overdueAfter = const Duration(minutes: 30),
  }) async {
    await _ensureLocalNotificationsReady();
    _ensureTimeZonesReady();

    await cancelShiftEndReminders();

    final now = DateTime.now();
    final title = 'Hora de encerrar o turno';
    final body =
        '$shiftGroupLabel encerra às ${_formatLocalTime(expectedEndAt)}. '
        'Se ainda estiver em ocorrência, encerre quando finalizar.';
    if (expectedEndAt.isAfter(now.add(const Duration(minutes: 1)))) {
      await _scheduleShiftLocalNotification(
        id: _shiftEndReminderNotificationId,
        type: 'shift_end_reminder',
        title: title,
        body: body,
        scheduledAt: expectedEndAt,
        shiftId: shiftId,
        shiftGroupLabel: shiftGroupLabel,
      );
    }

    final overdueAt = expectedEndAt.add(overdueAfter);
    if (overdueAt.isAfter(now.add(const Duration(minutes: 1)))) {
      await _scheduleShiftLocalNotification(
        id: _shiftOverdueReminderNotificationId,
        type: 'shift_overdue_reminder',
        title: 'Turno aberto além do previsto',
        body:
            '$shiftGroupLabel continua aberto. Toque para revisar o turno ativo.',
        scheduledAt: overdueAt,
        shiftId: shiftId,
        shiftGroupLabel: shiftGroupLabel,
      );
    }
  }

  Future<void> cancelShiftEndReminders() async {
    await _ensureLocalNotificationsReady();
    await _localNotifications.cancel(id: _shiftEndReminderNotificationId);
    await _localNotifications.cancel(id: _shiftOverdueReminderNotificationId);
  }

  Future<void> _ensureLocalNotificationsReady() async {
    if (_localNotificationsReady) return;
    await _configureLocalNotifications(
      _localNotifications,
      onResponse: _handleNotificationResponse,
      backgroundResponse: canilK9NotificationTapBackground,
    );
    _localNotificationsReady = true;
    await _requestAndroidNotificationPermission();
  }

  void _ensureTimeZonesReady() {
    if (_timeZonesReady) return;
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation(_shiftTimeZone));
    _timeZonesReady = true;
  }

  Future<void> _scheduleShiftLocalNotification({
    required int id,
    required String type,
    required String title,
    required String body,
    required DateTime scheduledAt,
    required String shiftId,
    required String shiftGroupLabel,
  }) {
    final payload = jsonEncode({
      'type': type,
      'title': title,
      'body': body,
      'target_screen': 'active_shift',
      'shift_id': shiftId,
      'shift_group_label': shiftGroupLabel,
      'notification_id': 'local_$type',
    });

    return _localNotifications.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: tz.TZDateTime.from(scheduledAt, tz.local),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _operationsChannelId,
          _operationsChannelName,
          channelDescription: 'Alertas operacionais do Canil K9',
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.reminder,
        ),
      ),
      payload: payload,
    );
  }

  String _formatLocalTime(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  void _handleRemoteMessageNavigation(RemoteMessage message) {
    _scheduleNavigation(message.data);
  }

  void _handleNotificationResponse(NotificationResponse response) {
    final data = _payloadMap(response.payload);
    if (data == null) return;
    _scheduleNavigation(data);
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
    if (_opensTrainingPromotionRequest(data)) {
      final requestId = _promotionRequestIdFromPayload(data);
      if (requestId == null) return;
      navigator.push(
        MaterialPageRoute(
          builder: (_) => TrainingPromotionRequestScreen(requestId: requestId),
        ),
      );
      return;
    }
    if (_opensTrainingHistory(data, target)) {
      final dogId = _stringValue(data['dog_id']);
      if (dogId == null) return;
      navigator.push(
        MaterialPageRoute(
          builder: (_) => TrainingLogScreen(
            dogId: dogId,
            dogName: _dogNameFromPayload(data) ?? '',
          ),
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
    if (_opensShiftScreen(data, target)) {
      final type = _stringValue(data['type']) ?? '';
      final opensAssumption =
          target == 'shift_assumption' || type == 'shift_start_reminder';
      if (!opensAssumption && _isShiftEndReminderPayload(data)) {
        unawaited(_resolveShiftReminderFromPayload(data));
      }
      navigator.push(
        MaterialPageRoute(
          builder: (_) => opensAssumption
              ? const ShiftAssumptionScreen()
              : const ActiveShiftDashboardScreen(),
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
  // `flutter_local_notifications` não aceita adaptive icons (mipmap/ic_launcher
  // em mipmap-anydpi-v26) como DrawableResource no momento do initialize.
  // Apontamos para um drawable bitmap que resolve para o mipmap legacy PNG.
  const androidSettings =
      AndroidInitializationSettings('drawable/ic_launcher');
  final initializationSettings = InitializationSettings(
    android: androidSettings,
    iOS: const DarwinInitializationSettings(),
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
  final payload = jsonEncode(data);

  final androidDetails = AndroidNotificationDetails(
    _operationsChannelId,
    _operationsChannelName,
    channelDescription: 'Alertas operacionais do Canil K9',
    importance: Importance.high,
    priority: Priority.high,
    category: AndroidNotificationCategory.status,
    color: AppTheme.primary,
  );

  await plugin.show(
    id: _notificationIdFor(data),
    title: title,
    body: body,
    notificationDetails: NotificationDetails(
      android: androidDetails,
    ),
    payload: payload,
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

bool _opensTrainingPromotionRequest(Map<String, dynamic> data) {
  final type = _stringValue(data['type']) ?? '';
  final target = _targetScreen(data);
  return type == 'training_promotion_requested' ||
      (type.isEmpty && target == 'training_promotion_request');
}

bool _opensTrainingHistory(Map<String, dynamic> data, String target) {
  final type = _stringValue(data['type']) ?? '';
  return type == 'training_promotion_approved' ||
      type == 'training_promotion_rejected' ||
      type == 'training_bonus_milestone_available' ||
      target == 'training_bonus_milestone';
}

bool _opensShiftScreen(Map<String, dynamic> data, String target) {
  final type = _stringValue(data['type']) ?? '';
  return target == 'shift_assumption' ||
      target == 'active_shift' ||
      type == 'shift_start_reminder' ||
      type == 'shift_end_reminder' ||
      type == 'shift_overdue_reminder' ||
      type == 'shift_open_reminder';
}

bool _isShiftEndReminderPayload(Map<String, dynamic> data) {
  final type = _stringValue(data['type']);
  return type == 'shift_end_reminder' ||
      type == 'shift_overdue_reminder' ||
      type == 'shift_open_reminder';
}

Future<void> _resolveShiftReminderFromPayload(Map<String, dynamic> data) async {
  final notificationId = _stringValue(data['notification_id']);
  if (notificationId == null || notificationId.startsWith('local_')) return;
  try {
    await NotificationService().resolveShiftReminderNotification(
      notificationId: notificationId,
    );
  } catch (error) {
    debugPrint(
      '[PushNotificationService] Falha ao resolver lembrete de turno: $error',
    );
  }
}

String? _promotionRequestIdFromPayload(Map<String, dynamic> data) {
  return _stringValue(data['promotion_request_id']) ??
      _stringValue(data['additional_data']);
}

String? _dogNameFromPayload(Map<String, dynamic> data) {
  final direct = _stringValue(data['dog_name']);
  if (direct != null) return direct;
  final title = _stringValue(data['occurrence_title']);
  if (title == null) return null;
  final separator = title.indexOf(' - ');
  if (separator <= 0) return title;
  return title.substring(0, separator).trim();
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

int _notificationIdFor(Map<String, dynamic> data) {
  final source =
      _stringValue(data['notification_id']) ??
      _stringValue(data['occurrence_id']) ??
      jsonEncode(data);
  final digest = sha256.convert(utf8.encode(source)).toString();
  return int.parse(digest.substring(0, 7), radix: 16);
}
