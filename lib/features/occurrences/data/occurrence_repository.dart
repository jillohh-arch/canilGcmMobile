import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:canil_gcm/core/services/audit_service.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence.dart';
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
        .copyWith(
          createdAt: now,
          updatedAt: now,
          auditTrail: [entry],
        )
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
    final entries = <Map<String, dynamic>>[];

    for (final key in updates.keys) {
      if (key == 'updated_at' || key == 'audit_trail') continue;
      final oldValue = currentData[key];
      final newValue = updates[key];
      if (oldValue != newValue) {
        entries.add(AuditService.buildInlineEntry(
          action: 'updated',
          fieldName: key,
          oldValue: _serializeForAudit(oldValue),
          newValue: _serializeForAudit(newValue),
        ));
      }
    }

    updates['updated_at'] = FieldValue.serverTimestamp();
    if (entries.isNotEmpty) {
      updates['audit_trail'] = FieldValue.arrayUnion(entries);
    }

    await docRef.update(updates);
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
  }) async {
    final docRef = _collection.doc(id);

    final entry = AuditService.buildInlineEntry(action: 'finalized');

    await docRef.update({
      'status': OccurrenceStatus.finalized.toMap(),
      'finalized_at': FieldValue.serverTimestamp(),
      'integrity_hash': integrityHash,
      'final_report': finalReport,
      'results': results.map((r) => r.toMap()).toList(),
      'details': details,
      'updated_at': FieldValue.serverTimestamp(),
      'audit_trail': FieldValue.arrayUnion([entry]),
    });

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

  Future<Occurrence?> getById(String id) async {
    final snap = await _collection.doc(id).get();
    if (!snap.exists) return null;

    final occ = Occurrence.fromMap(snap.data()!, id);
    if (occ.isDeleted) return null;
    return occ;
  }

  Stream<List<Occurrence>> watchByDog(String dogId) {
    return _collection
        .where('dog_id', isEqualTo: dogId)
        .where('deleted_at', isNull: true)
        .orderBy('started_at', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => Occurrence.fromMap(doc.data(), doc.id))
            .toList());
  }

  Stream<Occurrence?> watchOpen(String dogId) {
    return _collection
        .where('dog_id', isEqualTo: dogId)
        .where('status', whereIn: ['in_progress', 'finalizing'])
        .where('deleted_at', isNull: true)
        .limit(1)
        .snapshots()
        .map((snap) {
      if (snap.docs.isEmpty) return null;
      final doc = snap.docs.first;
      return Occurrence.fromMap(doc.data(), doc.id);
    });
  }

  Future<Occurrence?> findOpen(String dogId) async {
    final snap = await _collection
        .where('dog_id', isEqualTo: dogId)
        .where('status', whereIn: ['in_progress', 'finalizing'])
        .where('deleted_at', isNull: true)
        .limit(1)
        .get();

    if (snap.docs.isEmpty) return null;
    final doc = snap.docs.first;
    return Occurrence.fromMap(doc.data(), doc.id);
  }

  static dynamic _serializeForAudit(dynamic value) {
    if (value is Timestamp) return value.toDate().toIso8601String();
    if (value is DateTime) return value.toIso8601String();
    return value;
  }
}
