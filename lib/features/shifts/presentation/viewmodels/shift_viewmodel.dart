import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:canil_gcm/core/services/handler_identity_service.dart';
import 'package:canil_gcm/features/auth/data/auth_service.dart';
import 'package:canil_gcm/core/services/push_notification_service.dart';
import 'package:canil_gcm/features/shifts/data/shift_group_service.dart';
import 'package:canil_gcm/features/shifts/data/shift_service.dart';
import 'package:canil_gcm/features/shifts/domain/active_shift_session.dart';
import 'package:canil_gcm/features/shifts/domain/shift_group_model.dart';
import 'package:canil_gcm/features/shifts/domain/vehicle.dart';
import 'package:canil_gcm/core/services/audit_service.dart';

class ShiftViewModel extends ChangeNotifier {
  final AuthService _authService = AuthService();
  final ShiftService _shiftService = ShiftService();
  final ShiftGroupService _shiftGroupService = ShiftGroupService();
  final PushNotificationService _pushNotifications = PushNotificationService();

  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<ActiveShiftSession?>? _shiftSubscription;
  Timer? _initialShiftTimer;
  String? _boundRa;

  ActiveShiftSession? _session;
  bool _isLoading = false;
  String? _error;

  ActiveShiftSession? get session => _session;
  String? get activeDogId => _session?.effectiveServiceDogId;
  String? get legacyDogId => _session?.dogId;
  String? get serviceDogId => _session?.serviceDogId ?? _session?.dogId;
  String? get vehicleId => _session?.vehicleId;
  String? get vehicleLabel => _session?.vehicleLabel;
  String? get vehiclePrefix => _session?.vehiclePrefix;
  String? get vehicleModel => _session?.vehicleModel;
  String? get vehicleUnit => _session?.vehicleUnit;
  String? get vehicleCrewId => _session?.vehicleCrewId;
  String? get crewRole => _session?.crewRole;
  String? get crewStatus => _session?.crewStatus;
  DateTime? get shiftStartTime => _session?.startedAt;
  String? get activeShiftId => _session?.shiftId;
  String? get handlerId => _session?.handlerId ?? _boundRa;
  bool get isLoading => _isLoading;
  String? get error => _error;

  bool get hasActiveShift => _session?.isActive ?? false;
  bool get hasVehicle => _session?.hasVehicle ?? false;

  ShiftViewModel() {
    _authSubscription = _authService.authStateChanges.listen(_bindToUser);
    _bindToUser(_authService.currentUser);
  }

  Future<void> startShift(
    String dogId, {
    Vehicle? vehicle,
    String? handlerName,
    String role = 'motorista',
  }) async {
    final resolvedHandlerId = _resolveHandlerId();
    final currentUser = _authService.currentUser;
    final startedAt = DateTime.now();

    _error = null;
    notifyListeners();

    if (resolvedHandlerId == null) {
      _error = 'Usuario nao autenticado para iniciar turno.';
      notifyListeners();
      return;
    }

    try {
      final shiftInfo = await _safeUserShiftInfo(resolvedHandlerId);
      await _shiftService.startShift(
        handlerId: resolvedHandlerId,
        handlerAuthUid: currentUser?.uid,
        handlerEmail: currentUser?.email,
        handlerName: handlerName,
        shiftGroupId: shiftInfo?.group.id,
        shiftGroupCode: shiftInfo?.group.code,
        shiftGroupLabel: shiftInfo?.group.name,
        dogId: dogId,
        startedAt: startedAt,
        vehicle: vehicle,
      );
      _session = ActiveShiftSession(
        handlerId: resolvedHandlerId,
        authUid: currentUser?.uid,
        handlerEmail: currentUser?.email,
        dogId: dogId,
        serviceDogId: dogId.isEmpty ? null : dogId,
        startedAt: startedAt,
        vehicleId: vehicle?.id,
        vehicleLabel: vehicle?.label,
        vehiclePrefix: vehicle?.prefix,
        vehicleModel: vehicle?.modelName,
        vehicleUnit: vehicle?.unit,
        vehicleJoinedAt: vehicle == null ? null : startedAt,
        vehicleCrewId: vehicle?.id,
        crewRole: vehicle == null ? null : role,
        crewStatus: vehicle == null ? null : 'active',
        shiftGroupId: shiftInfo?.group.id,
        shiftGroupCode: shiftInfo?.group.code,
        shiftGroupLabel: shiftInfo?.group.name,
      );
      unawaited(_scheduleEndReminderFor(_session!, shiftInfo: shiftInfo));

      AuditService.log(
        action: 'create',
        entityType: 'shifts',
        entityId: resolvedHandlerId,
        summary: vehicle == null
            ? 'Turno iniciado: condutor $resolvedHandlerId com K9 $dogId'
            : 'Turno iniciado: condutor $resolvedHandlerId com K9 $dogId na ${vehicle.label}',
        after: {
          'handlerId': resolvedHandlerId,
          'dogId': dogId,
          'startedAt': startedAt.toIso8601String(),
          if (vehicle != null) 'vehicle_id': vehicle.id,
          if (vehicle != null) 'vehicle_label': vehicle.label,
        },
      );

      notifyListeners();
    } on FirebaseException catch (e) {
      _error = 'Falha ao sincronizar turno [${e.code}]: ${e.message}';
      notifyListeners();
    } catch (e) {
      _error = 'Falha ao sincronizar turno: $e';
      notifyListeners();
    }
  }

  Future<void> switchDog(String dogId) async {
    final resolvedHandlerId = _resolveHandlerId();

    _error = null;

    if (resolvedHandlerId == null) {
      _error = 'Usuario nao autenticado para trocar K9.';
      notifyListeners();
      return;
    }

    try {
      await _shiftService.switchDog(handlerId: resolvedHandlerId, dogId: dogId);
      _session = _session?.copyWith(
        dogId: dogId,
        serviceDogId: dogId,
        lastDogSwitchAt: DateTime.now(),
      );
      notifyListeners();
    } on FirebaseException catch (e) {
      _error = 'Falha ao sincronizar troca de K9 [${e.code}]: ${e.message}';
      notifyListeners();
    } catch (e) {
      _error = 'Falha ao sincronizar troca de K9: $e';
      notifyListeners();
    }
  }

  Future<void> assumeVehicle(
    Vehicle vehicle, {
    required String role,
    String? name,
  }) async {
    final resolvedHandlerId = _resolveHandlerId();
    final currentUser = _authService.currentUser;
    final activeDogId = _session?.dogId;

    _error = null;
    _setLoading(true);

    if (resolvedHandlerId == null || activeDogId == null) {
      _error = 'Turno ativo nao encontrado para assumir viatura.';
      _setLoading(false);
      return;
    }

    try {
      await _shiftService.assumeVehicle(
        handlerId: resolvedHandlerId,
        handlerAuthUid: currentUser?.uid,
        handlerEmail: currentUser?.email,
        handlerName: name,
        dogId: activeDogId,
        vehicle: vehicle,
        role: role,
      );
      _session = _session?.copyWith(
        authUid: currentUser?.uid,
        handlerEmail: currentUser?.email,
        vehicleId: vehicle.id,
        vehicleLabel: vehicle.label,
        vehiclePrefix: vehicle.prefix,
        vehicleModel: vehicle.modelName,
        vehicleUnit: vehicle.unit,
        vehicleJoinedAt: DateTime.now(),
        vehicleCrewId: vehicle.id,
        crewRole: role,
        crewStatus: 'active',
      );

      AuditService.log(
        action: 'update',
        entityType: 'shifts',
        entityId: resolvedHandlerId,
        summary: 'Viatura assumida: ${vehicle.label}',
        after: {'vehicle_id': vehicle.id, 'vehicle_label': vehicle.label},
      );

      _setLoading(false);
    } on FirebaseException catch (e) {
      _error = 'Falha ao assumir viatura [${e.code}]: ${e.message}';
      _setLoading(false);
    } catch (e) {
      _error = 'Falha ao assumir viatura: $e';
      _setLoading(false);
    }
  }

  Future<List<ActiveShiftSession>> getActiveCrew(String vehicleId) {
    return _shiftService.getActiveCrew(vehicleId);
  }

  /// Libera o posto na guarnição sem encerrar o turno.
  Future<void> leaveVehicle() async {
    final resolvedHandlerId = _resolveHandlerId();

    _error = null;
    _setLoading(true);

    if (resolvedHandlerId == null) {
      _error = 'Usuario nao autenticado.';
      _setLoading(false);
      return;
    }

    try {
      await _shiftService.leaveVehicle(resolvedHandlerId);
      _session = _session?.copyWith(
        vehicleId: null,
        vehicleLabel: null,
        vehiclePrefix: null,
        vehicleModel: null,
        vehicleUnit: null,
        vehicleCrewId: null,
        crewRole: null,
        crewStatus: null,
        vehicleJoinedAt: null,
      );

      AuditService.log(
        action: 'update',
        entityType: 'shifts',
        entityId: resolvedHandlerId,
        summary: 'Posto liberado: condutor $resolvedHandlerId',
      );

      _setLoading(false);
    } on FirebaseException catch (e) {
      _error = 'Falha ao liberar posto [${e.code}]: ${e.message}';
      _setLoading(false);
    } catch (e) {
      _error = 'Falha ao liberar posto: $e';
      _setLoading(false);
    }
  }

  Future<void> endShift() async {
    final resolvedHandlerId = _resolveHandlerId();

    _error = null;
    _setLoading(true);

    if (resolvedHandlerId == null) {
      _clearSession();
      _setLoading(false);
      return;
    }

    try {
      await _shiftService.endShift(resolvedHandlerId);
      unawaited(_pushNotifications.cancelShiftEndReminders());

      AuditService.log(
        action: 'update',
        entityType: 'shifts',
        entityId: resolvedHandlerId,
        summary: 'Turno encerrado: condutor $resolvedHandlerId',
        after: {'endedAt': DateTime.now().toIso8601String()},
      );

      _clearSession();
      _setLoading(false);
    } on FirebaseException catch (e) {
      _error = 'Falha ao encerrar turno [${e.code}]: ${e.message}';
      _setLoading(false);
    } catch (e) {
      _error = 'Falha ao encerrar turno: $e';
      _setLoading(false);
    }
  }

  void _bindToUser(User? user) {
    final ra = HandlerIdentityService.raFromUser(user);
    if (ra == _boundRa) return;

    _boundRa = ra;
    _shiftSubscription?.cancel();
    _shiftSubscription = null;
    _initialShiftTimer?.cancel();
    _initialShiftTimer = null;

    if (ra == null) {
      _clearSession(notify: false);
      _isLoading = false;
      _error = null;
      notifyListeners();
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    _initialShiftTimer?.cancel();
    _initialShiftTimer = Timer(const Duration(seconds: 8), () {
      if (!_isLoading) return;
      _isLoading = false;
      _error = 'Tempo excedido ao carregar turno ativo.';
      notifyListeners();
    });

    _shiftSubscription = _shiftService
        .watchActiveShift(ra)
        .listen(
          (session) {
            _initialShiftTimer?.cancel();
            _initialShiftTimer = null;
            _session = session;
            if (session == null) {
              unawaited(_pushNotifications.cancelShiftEndReminders());
            } else {
              unawaited(_scheduleEndReminderFor(session));
            }
            _isLoading = false;
            _error = null;
            notifyListeners();
          },
          onError: (e) {
            _initialShiftTimer?.cancel();
            _initialShiftTimer = null;
            _clearSession(notify: false);
            _isLoading = false;
            if (e is FirebaseException) {
              _error = 'Falha ao carregar turno ativo [${e.code}]: ${e.message}';
            } else {
              _error = 'Falha ao carregar turno ativo: $e';
            }
            notifyListeners();
          },
        );
  }

  String? _resolveHandlerId() {
    return _boundRa ??
        HandlerIdentityService.raFromUser(_authService.currentUser);
  }

  void _clearSession({bool notify = true}) {
    _session = null;
    // best-effort: falha de plugin de notificação não pode impedir o
    // notifyListeners que vem em seguida.
    unawaited(_safeCancelReminders());
    if (notify) {
      notifyListeners();
    }
  }

  Future<void> _safeCancelReminders() async {
    try {
      await _pushNotifications.cancelShiftEndReminders();
    } catch (e) {
      debugPrint('[ShiftViewModel] falha ao cancelar lembretes: $e');
    }
  }

  Future<void> _scheduleEndReminderFor(
    ActiveShiftSession session, {
    UserShiftInfo? shiftInfo,
  }) async {
    shiftInfo ??= await _safeUserShiftInfo(session.handlerId);
    final group = shiftInfo?.group;
    final window = group == null
        ? null
        : _windowForActiveSession(group, session);
    final expectedEndAt =
        window?.end ?? session.startedAt.add(const Duration(hours: 12));
    final overdueAfter = Duration(
      minutes: group?.notifications.overdueAfterMinutes ?? 30,
    );
    try {
      await _pushNotifications.scheduleShiftEndReminders(
        expectedEndAt: expectedEndAt,
        shiftId: session.shiftId ?? session.handlerId,
        shiftGroupLabel: group?.name ?? 'Turno K9',
        overdueAfter: overdueAfter,
      );
    } catch (e, st) {
      // Notificações locais são best-effort: nunca devem derrubar a sessão
      // do turno. O sintoma típico é `ic_launcher` ausente no Android,
      // mas qualquer falha do plugin de notificações cai aqui.
      debugPrint('[ShiftViewModel] falha ao agendar lembrete: $e');
      debugPrintStack(stackTrace: st, maxFrames: 4);
    }
  }

  Future<UserShiftInfo?> _safeUserShiftInfo(String handlerId) async {
    try {
      return await _shiftGroupService.getUserShiftInfo(handlerId);
    } catch (_) {
      return null;
    }
  }

  ShiftWindow? _windowForActiveSession(
    ShiftGroupModel group,
    ActiveShiftSession session,
  ) {
    final now = DateTime.now();
    final candidates = <DateTime>[
      now,
      now.subtract(const Duration(days: 1)),
      session.startedAt,
      session.startedAt.subtract(const Duration(days: 1)),
    ];

    for (final date in candidates) {
      final window = group.expectedWindowForDate(date);
      if (window == null) continue;
      if (window.contains(now) || window.contains(session.startedAt)) {
        return window;
      }
    }

    return null;
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _shiftSubscription?.cancel();
    _initialShiftTimer?.cancel();
    super.dispose();
  }
}
