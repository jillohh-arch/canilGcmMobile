import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:canil_gcm/viewmodels/auth_viewmodel.dart';
import 'package:canil_gcm/viewmodels/user_viewmodel.dart';
import '../models/user.dart';
import '../utils/badges_data.dart';
import '../main.dart';
import 'achievement_modal.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

class GamificationListener extends StatefulWidget {
  final Widget child;

  const GamificationListener({super.key, required this.child});

  @override
  State<GamificationListener> createState() => _GamificationListenerState();
}

class _GamificationListenerState extends State<GamificationListener>
    with WidgetsBindingObserver {
  bool _isForeground = true;
  List<String> _knownBadges = [];
  String? _currentRa;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initNotifications();
  }

  void _initNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
          requestSoundPermission: true,
          requestBadgePermission: true,
          requestAlertPermission: true,
        );

    const InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsIOS,
        );

    await flutterLocalNotificationsPlugin.initialize(
      settings: initializationSettings,
    );
    // Notification permission on Android 13+ is required to post notifications
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();

    if (mounted) {
      setState(() {
        _isInitialized = true;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _isForeground = true;
    } else {
      _isForeground = false;
    }
  }

  void _processUsersUpdate(UserViewModel userVM, AuthViewModel authVM) {
    final firebaseUser = authVM.user;
    if (firebaseUser == null ||
        firebaseUser.email == null ||
        userVM.users.isEmpty) {
      return;
    }

    final ra = firebaseUser.email!.split('@').first;

    UserModel? currentUserData;
    try {
      currentUserData = userVM.users.firstWhere((u) => u.ra == ra);
    } catch (_) {
      return;
    }

    if (_currentRa != ra) {
      // Mudou de usuário logado
      _currentRa = ra;
      _knownBadges = List.from(currentUserData.userBadges);
      return;
    }

    final newBadges = currentUserData.userBadges
        .where((b) => !_knownBadges.contains(b))
        .toList();
    if (newBadges.isNotEmpty) {
      for (final badgeId in newBadges) {
        _knownBadges.add(badgeId);
        final badgeDataList = BadgesConfig.getUserBadges([badgeId]);
        if (badgeDataList.isNotEmpty) {
          final badgeObj = badgeDataList.first;
          _triggerBadgeNotification(badgeObj);
        }
      }
    }
  }

  void _triggerBadgeNotification(BadgeData badge) {
    if (_isForeground && globalNavigatorKey.currentContext != null) {
      // Mostrar Modal na tela usando context global
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showDialog(
          context: globalNavigatorKey.currentContext!,
          barrierDismissible: true,
          builder: (ctx) => AchievementModal(badge: badge),
        );
      });
    } else {
      // Disparar Notificação Local
      _showLocalNotification(badge);
    }
  }

  Future<void> _showLocalNotification(BadgeData badge) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
          'gamification_channel',
          'Conquistas K9',
          channelDescription:
              'Notificações de badges do sistema de gamificação',
          importance: Importance.max,
          priority: Priority.high,
          showWhen: true,
          color: Colors.blueAccent,
        );

    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );

    await flutterLocalNotificationsPlugin.show(
      id: badge.id.hashCode,
      title: 'Conquista Desbloqueada! 🏆',
      body: 'Você ganhou a badge: ${badge.name}',
      notificationDetails: platformChannelSpecifics,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) return widget.child;

    return Consumer2<AuthViewModel, UserViewModel>(
      builder: (context, authVM, userVM, childToPass) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _processUsersUpdate(userVM, authVM);
        });
        return childToPass!;
      },
      child: widget.child,
    );
  }
}
