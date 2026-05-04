import 'package:firebase_auth/firebase_auth.dart';

class HandlerIdentityService {
  static String? raFromUser(User? user) => raFromEmail(user?.email);

  static String? raFromEmail(String? email) {
    if (email == null || email.isEmpty) return null;

    return email
        .replaceAll('@canilgcm.com', '')
        .replaceAll('@gcm.com.br', '')
        .trim();
  }
}
