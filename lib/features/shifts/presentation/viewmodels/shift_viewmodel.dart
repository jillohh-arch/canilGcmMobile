import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:canil_gcm/features/shifts/domain/active_shift_session.dart';
import 'package:canil_gcm/services/gamification_service.dart';
import 'package:canil_gcm/services/handler_identity_service.dart';
import 'package:canil_gcm/features/shifts/data/shift_service.dart';

class ShiftViewModel extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ShiftService _shiftService = ShiftService();

  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<ActiveShiftSession?>? _shiftSubscription;
  String? _boundRa;

  ActiveShiftSession? _session;
  bool _isLoading = false;
  String? _error;

  ActiveShiftSession? get session => _session;
  String? get activeDogId => _session?.dogId;
  DateTime? get shiftStartTime => _session?.startedAt;
  String? get activeShiftId => _session?.shiftId;
  String? get handlerId => _session?.handlerId ?? _boundRa;
  bool get isLoading => _isLoading;
  String? get error => _error;

  bool get hasActiveShift => _session?.isActive ?? false;

  ShiftViewModel() {
    _authSubscription = _auth.authStateChanges().listen(_bindToUser);
    _bindToUser(_auth.currentUser);
  }

  Future<void> startShift(String dogId) async {
    final resolvedHandlerId = _resolveHandlerId();
    final startedAt = DateTime.now();

    _error = null;
    _setLoading(true);

    if (resolvedHandlerId == null) {
      _error = 'Usuario nao autenticado para iniciar turno.';
      _setLoading(false);
      return;
    }

    try {
      await _shiftService.startShift(
        handlerId: resolvedHandlerId,
        dogId: dogId,
        startedAt: startedAt,
      );
      await GamificationService().evaluateShiftStart(resolvedHandlerId);
      _session = ActiveShiftSession(
        handlerId: resolvedHandlerId,
        dogId: dogId,
        startedAt: startedAt,
      );
      _setLoading(false);
    } catch (e) {
      _error = 'Falha ao sincronizar turno: $e';
      _setLoading(false);
    }
  }

  Future<void> switchDog(String dogId) async {
    final resolvedHandlerId = _resolveHandlerId();

    _error = null;
    if (_session != null) {
      _session = _session!.copyWith(
        dogId: dogId,
        lastDogSwitchAt: DateTime.now(),
      );
      notifyListeners();
    }

    if (resolvedHandlerId == null) {
      _error = 'Usuario nao autenticado para trocar K9.';
      notifyListeners();
      return;
    }

    try {
      await _shiftService.switchDog(handlerId: resolvedHandlerId, dogId: dogId);
    } catch (e) {
      _error = 'Falha ao sincronizar troca de K9: $e';
      notifyListeners();
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
      _clearSession();
      _setLoading(false);
    } catch (e) {
      _error = 'Falha ao sincronizar encerramento de turno: $e';
      _setLoading(false);
    }
  }

  void _bindToUser(User? user) {
    final ra = HandlerIdentityService.raFromUser(user);
    if (ra == _boundRa) return;

    _boundRa = ra;
    _shiftSubscription?.cancel();
    _shiftSubscription = null;

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

    _shiftSubscription = _shiftService
        .watchActiveShift(ra)
        .listen(
          (session) {
            _session = session;
            _isLoading = false;
            _error = null;
            notifyListeners();
          },
          onError: (e) {
            _clearSession(notify: false);
            _isLoading = false;
            _error = 'Falha ao carregar turno ativo: $e';
            notifyListeners();
          },
        );
  }

  String? _resolveHandlerId() {
    return _boundRa ?? HandlerIdentityService.raFromUser(_auth.currentUser);
  }

  void _clearSession({bool notify = true}) {
    _session = null;
    if (notify) {
      notifyListeners();
    }
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _shiftSubscription?.cancel();
    super.dispose();
  }
}
