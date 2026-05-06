import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:canil_gcm/services/auth_service.dart';

class AuthViewModel extends ChangeNotifier {
  final AuthService _authService = AuthService();

  User? _user;
  bool _isLoading = false;
  String? _errorMessage;

  User? get user => _user;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  AuthViewModel() {
    _authService.authStateChanges.listen((User? user) {
      _user = user;
      notifyListeners();
    });
  }

  Future<bool> signInWithRaAndPassword(String ra, String password) async {
    _setLoading(true);
    try {
      await _authService.signInWithRaAndPassword(ra, password);
      _setLoading(false);
      return true;
    } on FirebaseAuthException catch (e) {
      _handleError(_translateFirebaseAuthError(e));
      return false;
    } catch (e) {
      _handleError('Erro inesperado ao realizar login. Tente novamente.');
      return false;
    }
  }

  Future<void> signOut() async {
    await _authService.signOut();
    _user = null;
    notifyListeners();
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    _errorMessage = null;
    notifyListeners();
  }

  void _handleError(String message) {
    _isLoading = false;
    _errorMessage = message;
    notifyListeners();
  }

  String _translateFirebaseAuthError(FirebaseAuthException error) {
    switch (error.code) {
      case 'invalid-email':
        return 'R.A. ou e-mail em formato inválido.';
      case 'user-disabled':
        return 'Este usuário está desativado. Procure o administrador.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'R.A. ou senha inválidos.';
      case 'too-many-requests':
        return 'Muitas tentativas de acesso. Aguarde alguns minutos e tente novamente.';
      case 'network-request-failed':
        return 'Falha de conexão. Verifique a internet e tente novamente.';
      case 'operation-not-allowed':
        return 'Login por senha não está habilitado para este projeto.';
      default:
        return 'Não foi possível realizar o login. Verifique os dados e tente novamente.';
    }
  }
}
