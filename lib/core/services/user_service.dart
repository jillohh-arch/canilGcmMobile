import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:canil_gcm/core/services/handler_identity_service.dart';

class UserService {
  static final UserService _instance = UserService._internal();
  factory UserService() => _instance;
  UserService._internal();

  final CollectionReference<Map<String, dynamic>> _usersCollection =
      FirebaseFirestore.instance.collection('users');

  Stream<List<Map<String, dynamic>>> getAllHandlers() {
    return _usersCollection.orderBy('ra').snapshots().map((snapshot) {
      return snapshot.docs.map(_handlerFromDoc).toList();
    });
  }

  Stream<List<Map<String, dynamic>>> searchHandlers(String query) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return getAllHandlers();
    }

    return getAllHandlers().map((handlers) {
      return handlers.where((handler) {
        final ra = handler['ra'].toString().toLowerCase();
        final name = handler['name'].toString().toLowerCase();
        final callsign = handler['callsign'].toString().toLowerCase();
        return ra.contains(normalizedQuery) ||
            name.contains(normalizedQuery) ||
            callsign.contains(normalizedQuery);
      }).toList();
    });
  }

  Future<Map<String, dynamic>?> getHandlerByRa(String ra) async {
    final doc = await _usersCollection.doc(ra).get();
    if (!doc.exists) return null;
    return _handlerFromDoc(doc);
  }

  bool isHandlerInTeam({
    required List<Map<String, dynamic>> team,
    required String handlerId,
  }) {
    return team.any((member) => member['handler_id'] == handlerId);
  }

  Map<String, dynamic> _handlerFromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    return _handlerFromData(doc.data(), doc.id);
  }

  Map<String, dynamic> _handlerFromData(Map<String, dynamic>? data, String id) {
    final value = data ?? const <String, dynamic>{};
    final ra = (value['ra'] ?? id).toString().trim();
    return {
      'ra': ra,
      'name': value['name'] ?? '',
      'callsign': value['callsign'] ?? '',
      'imageUrl': value['photoUrl'] ?? value['image_url'] ?? '',
      'email':
          value['email'] ??
          value['handler_email'] ??
          HandlerIdentityService.emailFromRa(ra),
      'authUid': value['authUid'] ?? value['auth_uid'] ?? value['uid'],
    };
  }
}
