import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/user.dart';
import '../services/firestore_service.dart';
import '../services/handler_identity_service.dart';

class UserViewModel extends ChangeNotifier {
  final FirestoreService _firestoreService = FirestoreService();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<List<UserModel>>? _usersSubscription;
  String? _boundRa;

  List<UserModel> _users = [];
  bool _isLoading = false;
  bool _hasLoadedInitialData = false;
  String? _error;

  List<UserModel> get users => _users;
  bool get isLoading => _isLoading;
  bool get hasLoadedInitialData => _hasLoadedInitialData;
  String? get error => _error;

  UserViewModel() {
    _authSubscription = _auth.authStateChanges().listen(_bindToUser);
    _bindToUser(_auth.currentUser);
  }

  void _bindToUser(User? user) {
    final ra = HandlerIdentityService.raFromUser(user);
    if (ra == _boundRa && _usersSubscription != null) return;

    _boundRa = ra;
    _usersSubscription?.cancel();
    _usersSubscription = null;
    _users = [];
    _error = null;
    _hasLoadedInitialData = false;

    if (ra == null) {
      _setLoading(false);
      return;
    }

    _listenToUsers();
  }

  void _listenToUsers() {
    _setLoading(true);
    _usersSubscription = _firestoreService.getUsers().listen(
      (usersData) {
        _users = usersData;
        _hasLoadedInitialData = true;
        _setLoading(false);
      },
      onError: (e) {
        _error = e.toString();
        _hasLoadedInitialData = true;
        _setLoading(false);
      },
    );
  }

  UserModel? findByRa(String? ra) {
    if (ra == null || ra.trim().isEmpty) return null;
    for (final user in _users) {
      if (user.ra == ra) return user;
    }
    return null;
  }

  bool hasUserForRa(String? ra) => findByRa(ra) != null;

  String displayNameFor({
    required String? ra,
    User? firebaseUser,
    String fallback = 'Condutor',
  }) {
    final user = findByRa(ra);
    final callsign = user?.callsign.trim();
    if (callsign != null && callsign.isNotEmpty) return callsign;

    final firebaseName = firebaseUser?.displayName?.trim();
    if (firebaseName != null && firebaseName.isNotEmpty) {
      return firebaseName;
    }

    if (ra != null && ra.trim().isNotEmpty) return 'RA ${ra.trim()}';
    return fallback;
  }

  Future<void> saveUser(UserModel user) async {
    try {
      await _firestoreService.saveUser(user);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      throw Exception('Falha ao salvar: $e');
    }
  }

  Future<void> grantBadge(String ra, String badgeId) async {
    try {
      final userIndex = _users.indexWhere((u) => u.ra == ra);
      if (userIndex != -1) {
        final user = _users[userIndex];
        if (!user.userBadges.contains(badgeId)) {
          final updatedUser = user.copyWith(
            userBadges: [...user.userBadges, badgeId],
          );
          await _firestoreService.saveUser(updatedUser);
        }
      }
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> deleteUser(String ra) async {
    try {
      await _firestoreService.deleteUser(ra);
    } catch (e) {
      _error = e.toString();
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
    _usersSubscription?.cancel();
    super.dispose();
  }
}
