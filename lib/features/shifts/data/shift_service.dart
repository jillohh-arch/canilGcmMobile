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

  CollectionReference<Map<String, dynamic>> get _vehicleCrews {
    return _db.collection('vehicle_crews');
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
    String? handlerAuthUid,
    String? handlerEmail,
    required String dogId,
    required DateTime startedAt,
    Vehicle? vehicle,
  }) async {
    if (vehicle != null) {
      await _validateVehicleCanBeAssumed(
        vehicle: vehicle,
        serviceDogId: dogId,
        excludingHandlerId: handlerId,
      );
    }

    final activeRef = _activeShiftDoc(handlerId);
    final logRef = _shiftLogs.doc();
    final batch = _db.batch();
    final vehicleFields = _vehicleFields(vehicle);
    final crewId = vehicle == null ? null : _crewIdFor(vehicle.id);
    final crewFields = vehicle == null
        ? const <String, dynamic>{}
        : _crewFields(crewId: crewId!, role: 'titular', status: 'titular');
    final handlerFields = _handlerIdentityFields(
      authUid: handlerAuthUid,
      email: handlerEmail,
    );

    batch.set(logRef, {
      'id': logRef.id,
      'handlerId': handlerId,
      ...handlerFields,
      'initialDogId': dogId,
      'currentDogId': dogId,
      'service_dog_id': dogId,
      ...vehicleFields,
      ...crewFields,
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
      ...handlerFields,
      'dogId': dogId,
      'service_dog_id': dogId,
      ...vehicleFields,
      ...crewFields,
      'status': 'active',
      'startedAt': Timestamp.fromDate(startedAt),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (vehicle != null && crewId != null) {
      _upsertCrewInBatch(
        batch: batch,
        vehicle: vehicle,
        crewId: crewId,
        serviceDogId: dogId,
        handlerId: handlerId,
        handlerAuthUid: handlerAuthUid,
        handlerEmail: handlerEmail,
        role: 'titular',
        status: 'titular',
      );
    }

    return batch.commit();
  }

  Future<void> assumeVehicle({
    required String handlerId,
    String? handlerAuthUid,
    String? handlerEmail,
    required String dogId,
    required Vehicle vehicle,
  }) async {
    await _validateVehicleCanBeAssumed(
      vehicle: vehicle,
      serviceDogId: dogId,
      excludingHandlerId: handlerId,
    );

    final activeRef = _activeShiftDoc(handlerId);
    final joinedAt = Timestamp.fromDate(DateTime.now());
    final crewId = _crewIdFor(vehicle.id);

    return _db.runTransaction((transaction) async {
      final activeSnapshot = await transaction.get(activeRef);
      final activeData = activeSnapshot.data();
      final shiftId = activeData?['shiftId'] as String?;
      final activeDogId = activeData?['dogId'] as String? ?? dogId;
      if (!activeSnapshot.exists ||
          activeData == null ||
          activeData['status'] != 'active' ||
          activeDogId.isEmpty) {
        throw StateError('Turno ativo não encontrado para assumir viatura');
      }

      final vehicleFields = {
        ..._vehicleFields(vehicle),
        ..._crewFields(crewId: crewId, role: 'titular', status: 'titular'),
        ..._handlerIdentityFields(authUid: handlerAuthUid, email: handlerEmail),
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

      transaction.set(_vehicleCrews.doc(crewId), {
        'id': crewId,
        'vehicle_id': vehicle.id,
        'vehicle_label': vehicle.label,
        'vehicle_prefix': vehicle.prefix,
        'vehicle_model': vehicle.modelName,
        'vehicle_unit': vehicle.unit,
        'crew_size': vehicle.crewSize,
        'service_dog_id': activeDogId,
        'titular_handler_id': handlerId,
        'active': true,
        'updated_at': FieldValue.serverTimestamp(),
        'created_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      transaction.set(
        _vehicleCrews.doc(crewId).collection('members').doc(handlerId),
        {
          'handler_id': handlerId,
          ..._handlerIdentityFields(
            authUid: handlerAuthUid,
            email: handlerEmail,
          ),
          'role': 'titular',
          'status': 'titular',
          'joined_at': FieldValue.serverTimestamp(),
          'responded_at': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
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

  Future<void> switchDog({
    required String handlerId,
    required String dogId,
  }) async {
    final activeRef = _activeShiftDoc(handlerId);
    final switchedAt = Timestamp.fromDate(DateTime.now());

    final activeSnapshot = await activeRef.get();
    final activeData = activeSnapshot.data();
    final vehicleId = activeData?['vehicle_id']?.toString().trim();
    final activeCrew = vehicleId == null || vehicleId.isEmpty
        ? const <ActiveShiftSession>[]
        : await getActiveCrew(vehicleId);

    return _db.runTransaction((transaction) async {
      final activeSnapshot = await transaction.get(activeRef);
      final activeData = activeSnapshot.data();
      final shiftId = activeData?['shiftId'] as String?;
      final fromDogId =
          activeData?['service_dog_id'] as String? ??
          activeData?['dogId'] as String? ??
          '';
      final transactionVehicleId = activeData?['vehicle_id']?.toString().trim();
      final crewId = activeData?['vehicle_crew_id']?.toString().trim();

      transaction.set(activeRef, {
        'handlerId': handlerId,
        'dogId': dogId,
        'service_dog_id': dogId,
        'status': 'active',
        'lastDogSwitchAt': switchedAt,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      for (final member in activeCrew) {
        if (member.handlerId == handlerId) continue;
        transaction.set(_activeShiftDoc(member.handlerId), {
          'dogId': dogId,
          'service_dog_id': dogId,
          'lastDogSwitchAt': switchedAt,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      if (shiftId != null && shiftId.isNotEmpty) {
        transaction.set(_shiftLogs.doc(shiftId), {
          'currentDogId': dogId,
          'service_dog_id': dogId,
          'dogSwitches': FieldValue.arrayUnion([
            {'dogId': dogId, 'switchedAt': switchedAt},
          ]),
          'dog_changes': FieldValue.arrayUnion([
            {'at': switchedAt, 'from': fromDogId, 'to': dogId},
          ]),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      if (transactionVehicleId != null &&
          transactionVehicleId.isNotEmpty &&
          crewId != null &&
          crewId.isNotEmpty) {
        transaction.set(_vehicleCrews.doc(crewId), {
          'service_dog_id': dogId,
          'updated_at': FieldValue.serverTimestamp(),
          'dog_changes': FieldValue.arrayUnion([
            {'at': switchedAt, 'from': fromDogId, 'to': dogId, 'by': handlerId},
          ]),
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

      final crewId = activeData?['vehicle_crew_id']?.toString().trim();
      if (crewId != null && crewId.isNotEmpty) {
        transaction.set(
          _vehicleCrews.doc(crewId).collection('members').doc(handlerId),
          {
            'status': 'ended',
            'left_at': endedAt,
            'updated_at': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
        if (activeData?['crew_role'] == 'titular') {
          transaction.set(_vehicleCrews.doc(crewId), {
            'active': false,
            'ended_at': endedAt,
            'updated_at': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
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
        'vehicle_crew_id': null,
        'crew_id': null,
        'crew_role': null,
        'crew_status': null,
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

  Map<String, dynamic> _crewFields({
    required String crewId,
    required String role,
    required String status,
  }) {
    return {
      'vehicle_crew_id': crewId,
      'crew_id': crewId,
      'crew_role': role,
      'crew_status': status,
    };
  }

  Map<String, dynamic> _handlerIdentityFields({
    String? authUid,
    String? email,
  }) {
    return {
      'auth_uid': _nonEmpty(authUid),
      'handler_email': _nonEmpty(email)?.toLowerCase(),
    };
  }

  String? _nonEmpty(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  Future<void> _validateVehicleCanBeAssumed({
    required Vehicle vehicle,
    required String serviceDogId,
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
      throw StateError('${vehicle.label} já está com a guarnição completa.');
    }

    final crewSnapshot = await _vehicleCrews.doc(_crewIdFor(vehicle.id)).get();
    final crewData = crewSnapshot.data();
    final existingServiceDogId = crewData?['service_dog_id']?.toString().trim();
    final existingTitular = crewData?['titular_handler_id']?.toString().trim();
    final crewIsActive = crewData?['active'] == true;
    if (crewIsActive &&
        existingTitular != null &&
        existingTitular.isNotEmpty &&
        existingTitular != excludingHandlerId) {
      throw StateError(
        '${vehicle.label} já possui guarnição. Entre somente por convite.',
      );
    }
    if (crewIsActive &&
        existingServiceDogId != null &&
        existingServiceDogId.isNotEmpty &&
        existingServiceDogId != serviceDogId) {
      throw StateError(
        '${vehicle.label} já está operando com outro K9 de serviço.',
      );
    }
  }

  String _crewIdFor(String vehicleId) => vehicleId.trim();

  void _upsertCrewInBatch({
    required WriteBatch batch,
    required Vehicle vehicle,
    required String crewId,
    required String serviceDogId,
    required String handlerId,
    String? handlerAuthUid,
    String? handlerEmail,
    required String role,
    required String status,
  }) {
    batch.set(_vehicleCrews.doc(crewId), {
      'id': crewId,
      'vehicle_id': vehicle.id,
      'vehicle_label': vehicle.label,
      'vehicle_prefix': vehicle.prefix,
      'vehicle_model': vehicle.modelName,
      'vehicle_unit': vehicle.unit,
      'crew_size': vehicle.crewSize,
      'service_dog_id': serviceDogId,
      'titular_handler_id': handlerId,
      'active': true,
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    batch.set(
      _vehicleCrews.doc(crewId).collection('members').doc(handlerId),
      {
        'handler_id': handlerId,
        ..._handlerIdentityFields(authUid: handlerAuthUid, email: handlerEmail),
        'role': role,
        'status': status,
        'joined_at': FieldValue.serverTimestamp(),
        'responded_at': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }
}
