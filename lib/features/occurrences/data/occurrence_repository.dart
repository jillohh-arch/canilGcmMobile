import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:canil_gcm/core/services/audit_service.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_nature.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_result.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_status.dart';

class OccurrenceRepository {
  final FirebaseFirestore _firestore;

  OccurrenceRepository(this._firestore);

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('occurrences');

  Future<Occurrence> create(Occurrence occurrence) async {
    final docRef = _collection.doc(occurrence.id);
    final now = DateTime.now();

    final entry = AuditService.buildInlineEntry(action: 'created');
    final data = occurrence
        .copyWith(createdAt: now, updatedAt: now, auditTrail: [entry])
        .toMap();

    await docRef.set(data);

    AuditService.log(
      action: 'created',
      entityType: 'occurrence',
      entityId: occurrence.id,
      summary: 'Ocorrência criada: ${occurrence.typeName}',
      after: {
        'type_code': occurrence.typeCode,
        'status': occurrence.status.toMap(),
        'dog_id': occurrence.dogId,
      },
    );

    return occurrence.copyWith(
      createdAt: now,
      updatedAt: now,
      auditTrail: [entry],
    );
  }

  Future<void> update(String id, Map<String, dynamic> updates) async {
    final docRef = _collection.doc(id);
    final snap = await docRef.get();
    if (!snap.exists) return;

    final currentData = snap.data()!;
    final normalizedUpdates = Map<String, dynamic>.from(updates);
    if (_isFinalized(currentData) &&
        !_isAllowedFinalizedUpdate(normalizedUpdates)) {
      throw StateError(
        'Ocorrencia finalizada permite apenas metadados de PDF e auditoria.',
      );
    }

    // Campos que não devem gerar entrada de auditoria (temporários/internos)
    const _noAuditFields = {
      'updated_at',
      'audit_trail',
      'finalization_draft',
      'status',
    };

    final entries = <Map<String, dynamic>>[];

    for (final key in normalizedUpdates.keys) {
      if (_noAuditFields.contains(key)) continue;
      final oldValue = currentData[key];
      final newValue = normalizedUpdates[key];
      if (oldValue != newValue) {
        entries.add(
          AuditService.buildInlineEntry(
            action: 'updated',
            fieldName: key,
            oldValue: _serializeForAudit(oldValue),
            newValue: _serializeForAudit(newValue),
          ),
        );
      }
    }

    normalizedUpdates['updated_at'] = FieldValue.serverTimestamp();
    if (entries.isNotEmpty) {
      normalizedUpdates['audit_trail'] = FieldValue.arrayUnion(entries);
    }

    await docRef.update(normalizedUpdates);
  }

  /// Salva draft de finalização de forma leve (sem ler o documento).
  /// Usado pelo auto-save do wizard — não gera audit trail.
  Future<void> saveDraft(String id, Map<String, dynamic> draft) async {
    final docRef = _collection.doc(id);
    await docRef.update({
      'status': OccurrenceStatus.finalizing.toMap(),
      'finalization_draft': draft,
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  Future<void> softDelete(String id, String userId, String reason) async {
    final docRef = _collection.doc(id);

    final entry = AuditService.buildInlineEntry(
      action: 'deleted',
      reason: reason,
    );

    await docRef.update({
      'deleted_at': FieldValue.serverTimestamp(),
      'deleted_by': userId,
      'delete_reason': reason,
      'deleted_reason': reason,
      'updated_at': FieldValue.serverTimestamp(),
      'audit_trail': FieldValue.arrayUnion([entry]),
    });

    AuditService.log(
      action: 'deleted',
      entityType: 'occurrence',
      entityId: id,
      summary: 'Ocorrência excluída: $reason',
      metadata: {'reason': reason},
    );
  }

  Future<void> finalize({
    required String id,
    required String integrityHash,
    required String finalReport,
    required List<OccurrenceResult> results,
    required Map<String, dynamic>? details,
    List<String> finalizationPhotos = const [],
  }) async {
    final docRef = _collection.doc(id);
    final entry = AuditService.buildInlineEntry(action: 'finalized');

    debugPrint('[OccurrenceRepo] finalize: iniciando para $id');

    final updateData = <String, dynamic>{
      'status': OccurrenceStatus.finalized.toMap(),
      'finalized_at': FieldValue.serverTimestamp(),
      'integrity_hash': integrityHash,
      'final_report': finalReport,
      'results': results.map((r) => r.toMap()).toList(),
      'details': details,
      'finalization_photos': finalizationPhotos,
      'finalization_draft': FieldValue.delete(),
      'updated_at': FieldValue.serverTimestamp(),
      'audit_trail': FieldValue.arrayUnion([entry]),
    };

    // Usar update (não set/merge) para garantir que o documento existe
    // e preservar campos existentes (incluindo audit_trail anterior via arrayUnion)
    // Timeout de 15s para não travar em conexão instável
    final future = docRef.update(updateData);

    try {
      await future.timeout(const Duration(seconds: 15));
      debugPrint('[OccurrenceRepo] finalize: confirmado pelo servidor');
    } on TimeoutException {
      // O write foi enfileirado localmente — será sincronizado quando online
      debugPrint('[OccurrenceRepo] finalize: timeout — write enfileirado localmente');
    }

    AuditService.log(
      action: 'finalized',
      entityType: 'occurrence',
      entityId: id,
      summary: 'Ocorrência finalizada',
      after: {
        'integrity_hash': integrityHash,
        'results': results.map((r) => r.toMap()).toList(),
      },
    );
  }

  Future<void> recordPdfAccess({
    required String id,
    required String action,
    String? pdfUrl,
  }) async {
    final docRef = _collection.doc(id);
    final entry = AuditService.buildInlineEntry(action: action);
    final access = {
      'at': DateTime.now().toIso8601String(),
      'by': entry['performed_by'],
      'by_name': entry['by_name'],
      'by_ra': entry['by_ra'],
      'ip': 'client-unavailable',
      'action': action,
      if (pdfUrl?.trim().isNotEmpty == true) 'pdf_url': pdfUrl,
    };

    await docRef.update({
      'pdf_access_log': FieldValue.arrayUnion([access]),
      'audit_trail': FieldValue.arrayUnion([entry]),
    });

    AuditService.log(
      action: action,
      entityType: 'occurrence',
      entityId: id,
      summary: action == 'pdf_shared'
          ? 'PDF da ocorrencia compartilhado'
          : 'PDF da ocorrencia acessado',
      metadata: access,
    );
  }

  Future<Occurrence?> getById(String id) async {
    final snap = await _collection.doc(id).get();
    if (!snap.exists) return null;

    final occ = Occurrence.fromMap(snap.data()!, id);
    if (occ.isDeleted) return null;
    return occ;
  }

  Stream<List<Occurrence>> watchByDog(String dogId) {
    return _collection.where('dog_id', isEqualTo: dogId).snapshots().map((
      snap,
    ) {
      final occurrences =
          snap.docs
              .map((doc) => Occurrence.fromMap(doc.data(), doc.id))
              .where((occ) => !occ.isDeleted)
              .toList()
            ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
      return occurrences;
    });
  }

  Stream<Occurrence?> watchOpen(String dogId) {
    return _collection.where('dog_id', isEqualTo: dogId).snapshots().map((
      snap,
    ) {
      final open =
          snap.docs
              .map((doc) => Occurrence.fromMap(doc.data(), doc.id))
              .where((occ) => !occ.isDeleted && occ.status.isOpen)
              .toList()
            ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      if (open.isEmpty) return null;
      return open.first;
    });
  }

  Future<Occurrence?> findOpen(String dogId) async {
    final snap = await _collection.where('dog_id', isEqualTo: dogId).get();
    final open =
        snap.docs
            .map((doc) => Occurrence.fromMap(doc.data(), doc.id))
            .where((occ) => !occ.isDeleted && occ.status.isOpen)
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (open.isEmpty) return null;
    return open.first;
  }

  Future<List<OccurrenceNature>> getOccurrenceNatures() async {
    try {
      final configured = await _getOccurrenceNaturesFrom('occurrence_types');
      if (configured.isNotEmpty) return configured;
    } catch (_) {
      // Mantem a tela funcional se a colecao nova ainda nao estiver populada.
    }

    try {
      return _getOccurrenceNaturesFrom('occurrence_natures');
    } catch (_) {
      return OccurrenceNatureSeed.items;
    }
  }

  Future<List<OccurrenceNature>> _getOccurrenceNaturesFrom(
    String collectionName,
  ) async {
    final snapshot = await _firestore
        .collection(collectionName)
        .where('active', isEqualTo: true)
        .get();

    final natures = snapshot.docs.map((doc) {
      final data = doc.data();
      return OccurrenceNature.fromJson({
        ...data,
        'code': data['code'] ?? data['id'] ?? doc.id,
      });
    }).toList();

    natures.sort((a, b) {
      final byGroup = a.group.compareTo(b.group);
      if (byGroup != 0) return byGroup;
      return a.name.compareTo(b.name);
    });
    return natures;
  }

  static dynamic _serializeForAudit(dynamic value) {
    if (value is Timestamp) return value.toDate().toIso8601String();
    if (value is DateTime) return value.toIso8601String();
    return value;
  }

  static bool _isFinalized(Map<String, dynamic> data) {
    final status = data['status']?.toString();
    return status == OccurrenceStatus.finalized.toMap();
  }

  static bool _isAllowedFinalizedUpdate(Map<String, dynamic> updates) {
    const allowed = {
      'pdf_export_url',
      'pdf_generated_at',
      'pdf_access_log',
      'audit_trail',
      'updated_at',
    };
    return updates.keys.every(allowed.contains);
  }
}
