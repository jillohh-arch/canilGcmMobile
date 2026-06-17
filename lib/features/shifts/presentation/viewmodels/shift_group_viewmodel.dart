import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:canil_gcm/core/services/handler_identity_service.dart';
import 'package:canil_gcm/features/auth/data/auth_service.dart';
import 'package:canil_gcm/features/shifts/data/shift_group_service.dart';

/// ViewModel para gerenciar o plantão atual do usuário logado.
class ShiftGroupViewModel extends ChangeNotifier {
  final AuthService _authService = AuthService();
  final ShiftGroupService _shiftService = ShiftGroupService();

  StreamSubscription<User?>? _authSubscription;
  String? _boundRa;

  UserShiftInfo? _currentShift;
  bool _isLoading = false;
  String? _error;

  UserShiftInfo? get currentShift => _currentShift;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Verifica se estamos no horário esperado do plantão
  bool get isWithinShiftHours {
    if (_currentShift == null) return false;
    return _currentShift!.isWithinShiftHours();
  }

  /// Verifica se o usuário deveria ter iniciado o turno
  bool get shouldStartShift {
    if (_currentShift == null) return false;
    return _currentShift!.shouldStartShift();
  }

  ShiftGroupViewModel() {
    _authSubscription = _authService.authStateChanges.listen(_bindToUser);
    _bindToUser(_authService.currentUser);
  }

  void _bindToUser(User? user) {
    final ra = HandlerIdentityService.raFromUser(user);
    if (ra == _boundRa) return;

    _boundRa = ra;
    _currentShift = null;

    if (ra == null) {
      notifyListeners();
      return;
    }

    _loadShiftFor(ra);
  }

  Future<void> _loadShiftFor(String ra) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final shiftInfo = await _shiftService.getUserShiftInfo(ra);
      _currentShift = shiftInfo;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Força reload do plantão
  Future<void> refresh() async {
    if (_boundRa != null) {
      await _loadShiftFor(_boundRa!);
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
