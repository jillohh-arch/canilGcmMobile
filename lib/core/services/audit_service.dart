import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Serviço de trilha de auditoria.
///
/// Grava logs na coleção `auditLogs` do Firestore com o mesmo formato
/// usado pelo portal web, permitindo que o gestor visualize todas as
/// alterações feitas pelo app mobile na tela de Auditoria.
class AuditService {
  static final _firestore = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  /// Registra uma ação de auditoria.
  ///
  /// [action] — tipo da ação: 'create', 'update', 'delete'
  /// [entityType] — domínio: 'incidents', 'health', 'training', 'routine', 'shifts', 'dogs', 'users'
  /// [entityId] — ID do documento afetado
  /// [summary] — descrição legível da ação
  /// [before] — estado anterior (para updates/deletes)
  /// [after] — estado novo (para creates/updates)
  /// [metadata] — dados extras opcionais
  static Future<void> log({
    required String action,
    required String entityType,
    required String entityId,
    required String summary,
    Map<String, dynamic>? before,
    Map<String, dynamic>? after,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final user = _auth.currentUser;
      final email = user?.email ?? 'desconhecido';
      final ra = email.contains('@') ? email.split('@')[0] : email;

      final doc = <String, dynamic>{
        'action': action,
        'entityType': entityType,
        'entityId': entityId,
        'entityPath': '$entityType/$entityId',
        'summary': summary,
        'actor': {
          'uid': user?.uid,
          'email': email,
          'ra': ra,
        },
        'source': 'mobile',
        'clientTime': DateTime.now().toIso8601String(),
        'createdAt': FieldValue.serverTimestamp(),
      };

      if (before != null) doc['before'] = _sanitize(before);
      if (after != null) doc['after'] = _sanitize(after);
      if (metadata != null) doc['metadata'] = _sanitize(metadata);

      await _firestore.collection('auditLogs').add(doc);
    } catch (_) {
      // Auditoria nunca deve bloquear o fluxo principal.
    }
  }

  /// Remove valores nulos e converte Timestamps para ISO strings.
  static Map<String, dynamic> _sanitize(Map<String, dynamic> data) {
    final result = <String, dynamic>{};
    for (final entry in data.entries) {
      final value = entry.value;
      if (value == null) continue;
      if (value is Timestamp) {
        result[entry.key] = value.toDate().toIso8601String();
      } else if (value is DateTime) {
        result[entry.key] = value.toIso8601String();
      } else if (value is Map<String, dynamic>) {
        result[entry.key] = _sanitize(value);
      } else {
        result[entry.key] = value;
      }
    }
    return result;
  }
}
