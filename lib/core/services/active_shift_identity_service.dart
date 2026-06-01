import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'handler_identity_service.dart';

class ActiveShiftIdentity {
  final String handlerId;
  final String? dogId;

  const ActiveShiftIdentity({required this.handlerId, this.dogId});
}

class ActiveShiftIdentityService {
  const ActiveShiftIdentityService._();

  static Future<ActiveShiftIdentity?> resolve({
    required FirebaseFirestore firestore,
    FirebaseAuth? auth,
    String? preferredRa,
  }) async {
    User? user;
    try {
      user = (auth ?? FirebaseAuth.instance).currentUser;
    } catch (_) {
      user = null;
    }

    final emailRa = HandlerIdentityService.raFromUser(user);
    final candidates = <String>{
      if (preferredRa?.trim().isNotEmpty == true) preferredRa!.trim(),
      if (emailRa?.trim().isNotEmpty == true) emailRa!.trim(),
    };

    for (final ra in candidates) {
      final identity = await _fromActiveShiftDoc(firestore, ra);
      if (identity != null) return identity;
    }

    final uid = user?.uid.trim();
    if (uid != null && uid.isNotEmpty) {
      final identity = await _fromActiveShiftQuery(
        firestore.collection('active_shifts').where('auth_uid', isEqualTo: uid),
      );
      if (identity != null) return identity;
    }

    final email = user?.email?.trim().toLowerCase();
    if (email != null && email.isNotEmpty) {
      return _fromActiveShiftQuery(
        firestore
            .collection('active_shifts')
            .where('handler_email', isEqualTo: email),
      );
    }

    return null;
  }

  static Future<ActiveShiftIdentity?> _fromActiveShiftDoc(
    FirebaseFirestore firestore,
    String ra,
  ) async {
    try {
      final doc = await firestore.collection('active_shifts').doc(ra).get();
      final data = doc.data();
      if (!doc.exists || data == null || data['status'] != 'active') {
        return null;
      }
      return _identityFromData(doc.id, data, preferDocumentId: true);
    } catch (_) {
      return null;
    }
  }

  static Future<ActiveShiftIdentity?> _fromActiveShiftQuery(
    Query<Map<String, dynamic>> query,
  ) async {
    try {
      final snapshot = await query.limit(10).get();
      for (final doc in snapshot.docs) {
        final data = doc.data();
        if (data['status'] == 'active') {
          return _identityFromData(doc.id, data);
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static ActiveShiftIdentity _identityFromData(
    String fallbackHandlerId,
    Map<String, dynamic> data, {
    bool preferDocumentId = false,
  }) {
    final documentHandlerId = _text(fallbackHandlerId);
    final payloadHandlerId = _text(data['handlerId']);
    final handlerId = preferDocumentId || _looksLikeRa(documentHandlerId)
        ? (documentHandlerId ?? payloadHandlerId ?? '')
        : (payloadHandlerId ?? documentHandlerId ?? '');
    return ActiveShiftIdentity(
      handlerId: handlerId,
      dogId: _text(data['service_dog_id']) ?? _text(data['dogId']),
    );
  }

  static String? _text(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static bool _looksLikeRa(String? value) {
    return value != null && RegExp(r'^\d{3,}$').hasMatch(value);
  }
}
