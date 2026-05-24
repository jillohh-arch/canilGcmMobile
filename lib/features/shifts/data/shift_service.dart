import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:canil_gcm/features/shifts/domain/active_shift_session.dart';

class ShiftService {
  ShiftService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _activeShiftDoc(String handlerId) {
    return _db.collection('active_shifts').doc(handlerId);
  }

  CollectionReference<Map<String, dynamic>> get _shiftLogs {
    return _db.collection('shift_logs');
  }

  Stream<ActiveShiftSession?> watchActiveShift(String handlerId) {
    return _activeShiftDoc(handlerId).snapshots().map((snapshot) {
      final data = snapshot.data();
      if (!snapshot.exists || data == null) return null;

      final session = ActiveShiftSession.fromJson(data);
      if (!session.isActive) return null;
      return session;
    });
  }

  Future<void> startShift({
    required String handlerId,
    required String dogId,
    required DateTime startedAt,
  }) {
    final activeRef = _activeShiftDoc(handlerId);
    final logRef = _shiftLogs.doc();
    final batch = _db.batch();

    batch.set(logRef, {
      'id': logRef.id,
      'handlerId': handlerId,
      'initialDogId': dogId,
      'currentDogId': dogId,
      'status': 'active',
      'startedAt': Timestamp.fromDate(startedAt),
      'endedAt': null,
      'dogSwitches': <Map<String, dynamic>>[],
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    batch.set(activeRef, {
      'shiftId': logRef.id,
      'handlerId': handlerId,
      'dogId': dogId,
      'status': 'active',
      'startedAt': Timestamp.fromDate(startedAt),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    return batch.commit();
  }

  Future<void> switchDog({required String handlerId, required String dogId}) {
    final activeRef = _activeShiftDoc(handlerId);
    final switchedAt = Timestamp.fromDate(DateTime.now());

    return _db.runTransaction((transaction) async {
      final activeSnapshot = await transaction.get(activeRef);
      final activeData = activeSnapshot.data();
      final shiftId = activeData?['shiftId'] as String?;
      final fromDogId = activeData?['dogId'] as String? ?? '';

      transaction.set(activeRef, {
        'handlerId': handlerId,
        'dogId': dogId,
        'status': 'active',
        'lastDogSwitchAt': switchedAt,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (shiftId != null && shiftId.isNotEmpty) {
        transaction.set(_shiftLogs.doc(shiftId), {
          'currentDogId': dogId,
          'dogSwitches': FieldValue.arrayUnion([
            {'dogId': dogId, 'switchedAt': switchedAt},
          ]),
          'dog_changes': FieldValue.arrayUnion([
            {'at': switchedAt, 'from': fromDogId, 'to': dogId},
          ]),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    });
  }

  Future<void> endShift(String handlerId) {
    final activeRef = _activeShiftDoc(handlerId);
    final endedAt = Timestamp.fromDate(DateTime.now());

    return _db.runTransaction((transaction) async {
      final activeSnapshot = await transaction.get(activeRef);
      final activeData = activeSnapshot.data();
      final shiftId = activeData?['shiftId'] as String?;

      transaction.set(activeRef, {
        'status': 'ended',
        'endedAt': endedAt,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (shiftId != null && shiftId.isNotEmpty) {
        transaction.set(_shiftLogs.doc(shiftId), {
          'status': 'ended',
          'endedAt': endedAt,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    });
  }
}
