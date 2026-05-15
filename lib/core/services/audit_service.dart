import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Serviço de trilha de auditoria transversal.
///
/// Grava logs na coleção `auditLogs` do Firestore com o mesmo formato
/// usado pelo portal web, permitindo que o gestor visualize todas as
/// alterações feitas pelo app mobile na tela de Auditoria.
///
/// Responsabilidades:
/// - Registrar criação, atualização e exclusão de entidades
/// - Suportar soft delete com motivo obrigatório
/// - Registrar mudanças de campo individuais (trilha inline)
/// - Nunca bloquear o fluxo principal (fire-and-forget)
class AuditService {
  static final _firestore = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  /// Registra uma ação de auditoria.
  ///
  /// [action] — tipo da ação: 'created', 'updated', 'deleted'
  /// [entityType] — domínio: 'occurrence', 'event', 'training', 'health',
  ///   'feeding', 'weight', 'command', 'vaccination', 'conditioning',
  ///   'detection_line', 'specialty', 'dogs', 'users', 'shifts'
  /// [entityId] — ID do documento afetado
  /// [summary] — descrição legível da ação
  /// [before] — estado anterior (para updates/deletes)
  /// [after] — estado novo (para creates/updates)
  /// [metadata] — dados extras opcionais
  /// [fieldName] — campo específico alterado (para updates granulares)
  /// [reason] — motivo (obrigatório em delete e regressão de estágio)
  static Future<void> log({
    required String action,
    required String entityType,
    required String entityId,
    required String summary,
    Map<String, dynamic>? before,
    Map<String, dynamic>? after,
    Map<String, dynamic>? metadata,
    String? fieldName,
    String? reason,
  }) async {
    try {
      final actor = _buildActor();

      final doc = <String, dynamic>{
        'action': action,
        'entity_type': entityType,
        'entity_id': entityId,
        'entity_path': '$entityType/$entityId',
        'summary': summary,
        'actor': actor,
        'source': 'mobile',
        'client_time': DateTime.now().toIso8601String(),
        'performed_at': FieldValue.serverTimestamp(),
        // Campos legados mantidos para compatibilidade com painel React
        'entityType': entityType,
        'entityId': entityId,
        'entityPath': '$entityType/$entityId',
        'createdAt': FieldValue.serverTimestamp(),
      };

      if (before != null) doc['before'] = _sanitize(before);
      if (after != null) doc['after'] = _sanitize(after);
      if (metadata != null) doc['metadata'] = _sanitize(metadata);
      if (fieldName != null) doc['field_name'] = fieldName;
      if (reason != null) doc['reason'] = reason;

      await _firestore.collection('auditLogs').add(doc);
    } catch (_) {
      // Auditoria nunca deve bloquear o fluxo principal.
    }
  }

  /// Registra uma atualização de campo específico.
  /// Útil para trilha inline em cards/timelines.
  static Future<void> logFieldChange({
    required String entityType,
    required String entityId,
    required String fieldName,
    required dynamic oldValue,
    required dynamic newValue,
    String? reason,
  }) async {
    await log(
      action: 'updated',
      entityType: entityType,
      entityId: entityId,
      summary: 'Campo "$fieldName" alterado',
      fieldName: fieldName,
      before: {'value': oldValue},
      after: {'value': newValue},
      reason: reason,
    );
  }

  /// Registra soft delete com motivo obrigatório.
  /// Marca o documento como deletado sem removê-lo fisicamente.
  static Future<void> logSoftDelete({
    required String entityType,
    required String entityId,
    required String reason,
    required DocumentReference docRef,
    Map<String, dynamic>? beforeState,
  }) async {
    // Marca o documento como soft-deleted
    await docRef.update({
      '_deleted': true,
      '_deleted_at': FieldValue.serverTimestamp(),
      '_deleted_by': _auth.currentUser?.uid,
      '_delete_reason': reason,
    });

    // Registra no audit log
    await log(
      action: 'deleted',
      entityType: entityType,
      entityId: entityId,
      summary: 'Registro excluído: $reason',
      before: beforeState,
      reason: reason,
    );
  }

  /// Registra regressão de estágio (ex: comando voltou de 'consolidated' para 'developing').
  /// Motivo é obrigatório em regressões.
  static Future<void> logRegression({
    required String entityType,
    required String entityId,
    required String fieldName,
    required String fromStage,
    required String toStage,
    required String reason,
  }) async {
    await log(
      action: 'updated',
      entityType: entityType,
      entityId: entityId,
      summary: 'Regressão: $fieldName de "$fromStage" para "$toStage"',
      fieldName: fieldName,
      before: {'stage': fromStage},
      after: {'stage': toStage},
      reason: reason,
      metadata: {'is_regression': true},
    );
  }

  /// Busca histórico de auditoria de uma entidade específica.
  /// Retorna lista ordenada por data (mais recente primeiro).
  static Future<List<AuditEntry>> getHistory({
    required String entityType,
    required String entityId,
    int limit = 50,
  }) async {
    try {
      final snap = await _firestore
          .collection('auditLogs')
          .where('entity_type', isEqualTo: entityType)
          .where('entity_id', isEqualTo: entityId)
          .orderBy('performed_at', descending: true)
          .limit(limit)
          .get();

      return snap.docs
          .map((doc) => AuditEntry.fromJson(doc.data(), docId: doc.id))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Gera uma entrada de trilha de auditoria inline para ser armazenada
  /// diretamente no documento (array audit_trail).
  static Map<String, dynamic> buildInlineEntry({
    required String action,
    String? fieldName,
    dynamic oldValue,
    dynamic newValue,
    String? reason,
  }) {
    final actor = _buildActor();
    return {
      'action': action,
      'performed_by': actor['uid'],
      'performed_at': DateTime.now().toIso8601String(),
      if (fieldName != null) 'field_name': fieldName,
      if (oldValue != null) 'old_value': oldValue,
      if (newValue != null) 'new_value': newValue,
      if (reason != null) 'reason': reason,
    };
  }

  // ─── Helpers ──────────────────────────────────────────────────────

  static Map<String, dynamic> _buildActor() {
    final user = _auth.currentUser;
    final email = user?.email ?? 'desconhecido';
    final ra = email.contains('@') ? email.split('@')[0] : email;
    return {
      'uid': user?.uid,
      'email': email,
      'ra': ra,
    };
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
      } else if (value is List) {
        result[entry.key] = value.map((item) {
          if (item is Map<String, dynamic>) return _sanitize(item);
          if (item is Timestamp) return item.toDate().toIso8601String();
          if (item is DateTime) return item.toIso8601String();
          return item;
        }).toList();
      } else {
        result[entry.key] = value;
      }
    }
    return result;
  }
}

/// Entrada de auditoria lida do Firestore.
class AuditEntry {
  final String? id;
  final String action;
  final String entityType;
  final String entityId;
  final String summary;
  final Map<String, dynamic>? actor;
  final String? fieldName;
  final Map<String, dynamic>? before;
  final Map<String, dynamic>? after;
  final String? reason;
  final DateTime? performedAt;

  AuditEntry({
    this.id,
    required this.action,
    required this.entityType,
    required this.entityId,
    required this.summary,
    this.actor,
    this.fieldName,
    this.before,
    this.after,
    this.reason,
    this.performedAt,
  });

  factory AuditEntry.fromJson(Map<String, dynamic> json, {String? docId}) {
    return AuditEntry(
      id: docId,
      action: json['action'] as String? ?? '',
      entityType: json['entity_type'] as String? ?? json['entityType'] as String? ?? '',
      entityId: json['entity_id'] as String? ?? json['entityId'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      actor: json['actor'] as Map<String, dynamic>?,
      fieldName: json['field_name'] as String?,
      before: json['before'] as Map<String, dynamic>?,
      after: json['after'] as Map<String, dynamic>?,
      reason: json['reason'] as String?,
      performedAt: _toDateTime(json['performed_at'] ?? json['createdAt']),
    );
  }

  /// Nome legível do ator.
  String get actorName {
    if (actor == null) return 'Desconhecido';
    final ra = actor!['ra'] as String?;
    return ra != null ? 'RA $ra' : actor!['email'] as String? ?? 'Desconhecido';
  }

  /// Verifica se é uma regressão.
  bool get isRegression =>
      action == 'updated' &&
      (before?['stage'] != null || reason != null);

  static DateTime? _toDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}