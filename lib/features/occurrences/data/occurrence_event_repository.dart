import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:canil_gcm/core/services/audit_service.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event.dart';

class OccurrenceEventRepository {
  final FirebaseFirestore _firestore;

  OccurrenceEventRepository(this._firestore);

  CollectionReference<Map<String, dynamic>> _events(String occurrenceId) =>
      _firestore
          .collection('occurrences')
          .doc(occurrenceId)
          .collection('events');

  Future<OccurrenceEvent> create(OccurrenceEvent event) async {
    await _ensureOccurrenceMutable(event.occurrenceId);
    final colRef = _events(event.occurrenceId);
    final docRef = colRef.doc(event.id);
    final now = DateTime.now();

    final entry = AuditService.buildInlineEntry(action: 'created');
    final auditTrail = event.auditTrail.isNotEmpty
        ? event.auditTrail
        : <Map<String, dynamic>>[entry];
    final data = event
        .copyWith(createdAt: now, updatedAt: now, auditTrail: auditTrail)
        .toMap();

    await docRef.set(data);

    return event.copyWith(
      createdAt: now,
      updatedAt: now,
      auditTrail: auditTrail,
    );
  }

  Future<void> update(
    String occurrenceId,
    String eventId,
    Map<String, dynamic> updates,
  ) async {
    await _ensureOccurrenceMutable(occurrenceId);
    final docRef = _events(occurrenceId).doc(eventId);
    final snap = await docRef.get();
    if (!snap.exists) return;

    final currentData = snap.data()!;
    final entries = <Map<String, dynamic>>[];

    for (final key in updates.keys) {
      if (key == 'updated_at' || key == 'audit_trail') continue;
      final oldValue = currentData[key];
      final newValue = updates[key];
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

    updates['updated_at'] = FieldValue.serverTimestamp();
    if (entries.isNotEmpty) {
      updates['audit_trail'] = FieldValue.arrayUnion(entries);
    }

    await docRef.update(updates);
  }

  Future<void> softDelete(
    String occurrenceId,
    String eventId,
    String userId,
    String reason,
  ) async {
    await _ensureOccurrenceMutable(occurrenceId);
    final docRef = _events(occurrenceId).doc(eventId);

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
  }

  Stream<List<OccurrenceEvent>> watchByOccurrence(String occurrenceId) {
    return _events(occurrenceId)
        .where('deleted_at', isNull: true)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map(
                (doc) => OccurrenceEvent.fromMap(
                  doc.data(),
                  doc.id,
                  occurrenceId: occurrenceId,
                ),
              )
              .toList(),
        );
  }

  Future<List<OccurrenceEvent>> listByOccurrence(String occurrenceId) async {
    final snap = await _events(occurrenceId)
        .where('deleted_at', isNull: true)
        .orderBy('timestamp', descending: true)
        .get();

    return snap.docs
        .map(
          (doc) => OccurrenceEvent.fromMap(
            doc.data(),
            doc.id,
            occurrenceId: occurrenceId,
          ),
        )
        .toList();
  }

  Future<OccurrenceEvent?> getById(String occurrenceId, String eventId) async {
    final snap = await _events(occurrenceId).doc(eventId).get();
    if (!snap.exists) return null;

    final event = OccurrenceEvent.fromMap(
      snap.data()!,
      eventId,
      occurrenceId: occurrenceId,
    );
    if (event.isDeleted) return null;
    return event;
  }

  Future<int> countByOccurrence(String occurrenceId) async {
    final snap = await _events(
      occurrenceId,
    ).where('deleted_at', isNull: true).count().get();
    return snap.count ?? 0;
  }

  static dynamic _serializeForAudit(dynamic value) {
    if (value is Timestamp) return value.toDate().toIso8601String();
    if (value is DateTime) return value.toIso8601String();
    return value;
  }

  Future<void> _ensureOccurrenceMutable(String occurrenceId) async {
    final snap = await _firestore
        .collection('occurrences')
        .doc(occurrenceId)
        .get();
    final status = snap.data()?['status']?.toString();
    if (status == 'finalized') {
      throw StateError('Ocorrencia finalizada nao permite editar eventos.');
    }
  }
}
