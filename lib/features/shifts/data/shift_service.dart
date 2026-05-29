import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:canil_gcm/features/shifts/domain/active_shift_session.dart';
import 'package:canil_gcm/features/shifts/domain/vehicle.dart';

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
    Vehicle? vehicle,
  }) async {
    if (vehicle != null) {
      await _validateVehicleCanBeAssumed(
        vehicle: vehicle,
        dogId: dogId,
        excludingHandlerId: handlerId,
      );
    }

    final activeRef = _activeShiftDoc(handlerId);
    final logRef = _shiftLogs.doc();
    final batch = _db.batch();
    final vehicleFields = _vehicleFields(vehicle);

    batch.set(logRef, {
      'id': logRef.id,
      'handlerId': handlerId,
      'initialDogId': dogId,
      'currentDogId': dogId,
      ...vehicleFields,
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
      ...vehicleFields,
      'status': 'active',
      'startedAt': Timestamp.fromDate(startedAt),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    return batch.commit();
  }

  Future<void> assumeVehicle({
    required String handlerId,
    required String dogId,
    required Vehicle vehicle,
  }) async {
    await _validateVehicleCanBeAssumed(
      vehicle: vehicle,
      dogId: dogId,
      excludingHandlerId: handlerId,
    );

    final activeRef = _activeShiftDoc(handlerId);
    final joinedAt = Timestamp.fromDate(DateTime.now());

    return _db.runTransaction((transaction) async {
      final activeSnapshot = await transaction.get(activeRef);
      final activeData = activeSnapshot.data();
      final shiftId = activeData?['shiftId'] as String?;
      final activeDogId = activeData?['dogId'] as String? ?? dogId;
      if (!activeSnapshot.exists ||
          activeData == null ||
          activeData['status'] != 'active' ||
          activeDogId.isEmpty) {
        throw StateError('Turno ativo nao encontrado para assumir viatura');
      }

      final vehicleFields = {
        ..._vehicleFields(vehicle),
        'vehicle_joined_at': joinedAt,
      };

      transaction.set(activeRef, {
        ...vehicleFields,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (shiftId != null && shiftId.isNotEmpty) {
        transaction.set(_shiftLogs.doc(shiftId), {
          ...vehicleFields,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    });
  }

  Future<List<ActiveShiftSession>> getActiveCrew(String vehicleId) async {
    if (vehicleId.trim().isEmpty) return const [];
    final snapshot = await _db
        .collection('active_shifts')
        .where('vehicle_id', isEqualTo: vehicleId.trim())
        .get();
    final crew = snapshot.docs
        .map((doc) => ActiveShiftSession.fromJson(doc.data()))
        .where((session) => session.isActive)
        .toList();
    crew.sort((a, b) => a.handlerId.compareTo(b.handlerId));
    return crew;
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

  Map<String, dynamic> _vehicleFields(Vehicle? vehicle) {
    if (vehicle == null) {
      return {
        'vehicle_id': null,
        'vehicle_label': null,
        'vehicle_prefix': null,
        'vehicle_model': null,
        'vehicle_unit': null,
        'vehicle_joined_at': null,
      };
    }
    return {
      'vehicle_id': vehicle.id,
      'vehicle_label': vehicle.label,
      'vehicle_prefix': vehicle.prefix,
      'vehicle_model': vehicle.modelName,
      'vehicle_unit': vehicle.unit,
      'vehicle_joined_at': FieldValue.serverTimestamp(),
    };
  }

  Future<void> _validateVehicleCanBeAssumed({
    required Vehicle vehicle,
    required String dogId,
    required String excludingHandlerId,
  }) async {
    if (!vehicle.active) {
      throw StateError('Viatura inativa.');
    }

    final activeCrew = await getActiveCrew(vehicle.id);
    final otherCrew = activeCrew
        .where((session) => session.handlerId != excludingHandlerId)
        .toList();
    if (otherCrew.length >= vehicle.crewSize) {
      throw StateError('${vehicle.label} ja esta com a guarnicao completa.');
    }

    for (final member in otherCrew) {
      if (member.dogId.trim().isNotEmpty && member.dogId != dogId) {
        throw StateError(
          '${vehicle.label} ja esta operando com outro K9 de servico.',
        );
      }
    }
  }
}
