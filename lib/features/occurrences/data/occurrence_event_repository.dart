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

  DocumentReference<Map<String, dynamic>> _occurrence(String occurrenceId) =>
      _firestore.collection('occurrences').doc(occurrenceId);

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
    final occurrenceEntry = AuditService.buildInlineEntry(
      action: 'event_created',
      fieldName: 'events.${event.id}',
      newValue: {
        'title': event.title,
        'category': event.category.toMap(),
        'timestamp': event.timestamp.toIso8601String(),
      },
    );

    final batch = _firestore.batch();
    batch.set(docRef, data);
    batch.update(_occurrence(event.occurrenceId), {
      'updated_at': FieldValue.serverTimestamp(),
      'audit_trail': FieldValue.arrayUnion([occurrenceEntry]),
    });
    await batch.commit();

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
    final occurrenceEntries = <Map<String, dynamic>>[];

    for (final key in updates.keys) {
      if (key == 'updated_at' || key == 'audit_trail') continue;
      final oldValue = currentData[key];
      final newValue = updates[key];
      if (oldValue != newValue) {
        final oldAuditValue = _serializeForAudit(oldValue);
        final newAuditValue = _serializeForAudit(newValue);
        entries.add(
          AuditService.buildInlineEntry(
            action: 'updated',
            fieldName: key,
            oldValue: oldAuditValue,
            newValue: newAuditValue,
          ),
        );
        occurrenceEntries.add(
          AuditService.buildInlineEntry(
            action: 'event_updated',
            fieldName: 'events.$eventId.$key',
            oldValue: oldAuditValue,
            newValue: newAuditValue,
          ),
        );
      }
    }

    updates['updated_at'] = FieldValue.serverTimestamp();
    if (entries.isNotEmpty) {
      updates['audit_trail'] = FieldValue.arrayUnion(entries);
    }

    final batch = _firestore.batch();
    batch.update(docRef, updates);
    if (occurrenceEntries.isNotEmpty) {
      batch.update(_occurrence(occurrenceId), {
        'updated_at': FieldValue.serverTimestamp(),
        'audit_trail': FieldValue.arrayUnion(occurrenceEntries),
      });
    }
    await batch.commit();
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

    final batch = _firestore.batch();
    batch.update(docRef, {
      'deleted_at': FieldValue.serverTimestamp(),
      'deleted_by': userId,
      'delete_reason': reason,
      'deleted_reason': reason,
      'updated_at': FieldValue.serverTimestamp(),
      'audit_trail': FieldValue.arrayUnion([entry]),
    });
    batch.update(_occurrence(occurrenceId), {
      'updated_at': FieldValue.serverTimestamp(),
      'audit_trail': FieldValue.arrayUnion([
        AuditService.buildInlineEntry(
          action: 'event_deleted',
          fieldName: 'events.$eventId',
          reason: reason,
        ),
      ]),
    });
    await batch.commit();
  }

  Stream<List<OccurrenceEvent>> watchByOccurrence(String occurrenceId) {
    return _events(occurrenceId).snapshots().map(
      (snap) =>
          snap.docs
              .map(
                (doc) => OccurrenceEvent.fromMap(
                  doc.data(),
                  doc.id,
                  occurrenceId: occurrenceId,
                ),
              )
              .where((e) => !e.isDeleted)
              .toList()
            ..sort((a, b) => b.timestamp.compareTo(a.timestamp)),
    );
  }

  Future<List<OccurrenceEvent>> listByOccurrence(String occurrenceId) async {
    final snap = await _events(occurrenceId).get();

    return snap.docs
        .map(
          (doc) => OccurrenceEvent.fromMap(
            doc.data(),
            doc.id,
            occurrenceId: occurrenceId,
          ),
        )
        .where((e) => !e.isDeleted)
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
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
    final snap = await _occurrence(occurrenceId).get();
    final status = snap.data()?['status']?.toString();
    if (status == null) {
      throw StateError('Ocorrencia nao encontrada.');
    }
    if (status == 'awaiting_signatures' ||
        status == 'finalized' ||
        status == 'finalized_with_pending' ||
        status == 'canceled') {
      throw StateError('Ocorrencia bloqueada nao permite editar eventos.');
    }
  }
}
