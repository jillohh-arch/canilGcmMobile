import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:canil_gcm/features/shifts/domain/active_shift_session.dart';
import 'package:canil_gcm/features/shifts/domain/vehicle.dart';
import 'package:canil_gcm/features/shifts/domain/vehicle_crew.dart';

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

  CollectionReference<Map<String, dynamic>> get _vehicleCrewHistory {
    return _db.collection('vehicle_crew_history');
  }

  // ──────────────────────────────────────────────────────────
  // WATCH / GET
  // ──────────────────────────────────────────────────────────

  Stream<ActiveShiftSession?> watchActiveShift(String handlerId) {
    return _activeShiftDoc(handlerId).snapshots().map((snapshot) {
      final data = snapshot.data();
      if (!snapshot.exists || data == null) return null;

      final session = ActiveShiftSession.fromJson({
        ...data,
        'handlerId': snapshot.id,
      });
      if (!session.isActive) return null;
      return session;
    });
  }

  Future<List<ActiveShiftSession>> getActiveCrew(String vehicleId) async {
    if (vehicleId.trim().isEmpty) return const [];
    final snapshot = await _db
        .collection('active_shifts')
        .where('vehicle_id', isEqualTo: vehicleId.trim())
        .get();
    final crew = snapshot.docs
        .map(
          (doc) => ActiveShiftSession.fromJson({
            ...doc.data(),
            'handlerId': doc.id,
          }),
        )
        .where((session) => session.isActive)
        .toList();
    crew.sort((a, b) => a.handlerId.compareTo(b.handlerId));
    return crew;
  }

  /// Retorna true se ainda há members ativos (status active/pending) na
  /// guarnição, exceto o handler especificado.
  Future<bool> _crewHasOtherActiveMembers({
    required String crewId,
    required String excludingHandlerId,
  }) async {
    final snapshot = await _vehicleCrews
        .doc(crewId)
        .collection('members')
        .where('status', whereIn: ['active', 'pending'])
        .get();
    return snapshot.docs.any((doc) => doc.id != excludingHandlerId);
  }

  /// Lê todos os members de uma guarnição (ativos e encerrados).
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _getAllMembers(
    String crewId,
  ) async {
    final snapshot = await _vehicleCrews
        .doc(crewId)
        .collection('members')
        .get();
    return snapshot.docs.toList();
  }

  // ──────────────────────────────────────────────────────────
  // START SHIFT  (abertura de turno + abertura de guarnição)
  // ──────────────────────────────────────────────────────────

  Future<void> startShift({
    required String handlerId,
    String? handlerAuthUid,
    String? handlerEmail,
    String? handlerName,
    String? shiftGroupId,
    String? shiftGroupCode,
    String? shiftGroupLabel,
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
    final crewDocFields = vehicle == null
        ? <String, dynamic>{}
        : _crewDocFields(
            crewId: crewId!,
            vehicle: vehicle,
            serviceDogId: dogId,
            handlerId: handlerId,
            handlerAuthUid: handlerAuthUid,
            handlerEmail: handlerEmail,
            handlerName: handlerName,
            role: 'motorista',
            status: 'active',
            clearEndedAt: true,
          );
    // active_shifts/shift_logs: auth_uid + handler_email (SEM name — não whitelisted)
    final handlerFieldsBasic = {
      'auth_uid': _nonEmpty(handlerAuthUid),
      'handler_email': _nonEmpty(handlerEmail)?.toLowerCase(),
    };
    // members: auth_uid + handler_email + name
    final handlerFieldsWithName = {
      'auth_uid': _nonEmpty(handlerAuthUid),
      'handler_email': _nonEmpty(handlerEmail)?.toLowerCase(),
      'name': _nonEmpty(handlerName),
    };
    final shiftGroupFields = _shiftGroupFields(
      shiftGroupId: shiftGroupId,
      shiftGroupCode: shiftGroupCode,
      shiftGroupLabel: shiftGroupLabel,
    );

    // ── shift_logs ──
    batch.set(logRef, {
      'id': logRef.id,
      'handlerId': handlerId,
      ...handlerFieldsBasic,
      ...shiftGroupFields,
      'initialDogId': dogId,
      'currentDogId': dogId,
      'service_dog_id': dogId,
      ...vehicleFields,
      'vehicle_crew_id': crewId,
      'crew_id': crewId,
      'crew_role': 'motorista',
      'crew_status': 'active',
      'status': 'active',
      'startedAt': Timestamp.fromDate(startedAt),
      'endedAt': null,
      'dogSwitches': <Map<String, dynamic>>[],
      'vehicleChanges': <Map<String, dynamic>>[],
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // ── active_shifts ──
    batch.set(activeRef, {
      'shiftId': logRef.id,
      'handlerId': handlerId,
      ...handlerFieldsBasic,
      ...shiftGroupFields,
      'dogId': dogId,
      'service_dog_id': dogId,
      ...vehicleFields,
      'vehicle_crew_id': crewId,
      'crew_id': crewId,
      'crew_role': 'motorista',
      'crew_status': 'active',
      'status': 'active',
      'startedAt': Timestamp.fromDate(startedAt),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // ── vehicle_crews/{vehicle_id} ──
    if (vehicle != null && crewId != null) {
      _upsertCrewInBatch(
        batch: batch,
        crewDocFields: crewDocFields,
        handlerId: handlerId,
        handlerFields: handlerFieldsWithName,
        role: 'motorista',
        status: 'active',
        dogId: dogId,
        crewId: crewId,
      );
    }

    // ── DEBUG: payload completo antes do commit ──
    debugPrint('[ShiftService] >>> BATCH PAYLOAD');
    debugPrint('[ShiftService] 1. shift_logs: ${
      {
        'id': logRef.id,
        'handlerId': handlerId,
        ...handlerFieldsBasic,
        ...shiftGroupFields,
        'initialDogId': dogId,
        'currentDogId': dogId,
        'service_dog_id': dogId,
        ...vehicleFields,
        'vehicle_crew_id': crewId,
        'crew_id': crewId,
        'crew_role': 'motorista',
        'crew_status': 'active',
        'status': 'active',
        'startedAt': startedAt,
        'endedAt': null,
        'dogSwitches': <Map<String, dynamic>>[],
        'vehicleChanges': <Map<String, dynamic>>[],
      }
    }');
    debugPrint('[ShiftService] 2. active_shifts: ${
      {
        'shiftId': logRef.id,
        'handlerId': handlerId,
        ...handlerFieldsBasic,
        ...shiftGroupFields,
        'dogId': dogId,
        'service_dog_id': dogId,
        ...vehicleFields,
        'vehicle_crew_id': crewId,
        'crew_id': crewId,
        'crew_role': 'motorista',
        'crew_status': 'active',
        'status': 'active',
        'startedAt': startedAt,
      }
    }');
    if (vehicle != null && crewId != null) {
      debugPrint('[ShiftService] 3. vehicle_crews/$crewId: $crewDocFields');
      debugPrint('[ShiftService] 4. members/$handlerId: ${
        {
          'handler_id': handlerId,
          ...handlerFieldsWithName,
          'role': 'motorista',
          'status': 'active',
          'dog_id': dogId,
        }
      }');
    }
    debugPrint('[ShiftService] <<< FIM PAYLOAD');

    try {
      await batch.commit();
    } on FirebaseException catch (e) {
      debugPrint('[ShiftService] batch bloqueado [${e.code}]: ${e.message}');
      rethrow;
    }
  }

  // ──────────────────────────────────────────────────────────
  // ASSUME VEHICLE  (adesão a guarnição ativa)
  // ──────────────────────────────────────────────────────────

  /// Assumir uma função na guarnição da viatura [vehicle].
  ///
  /// Lança [StateError] se:
  /// - a função já está ocupada por outro member ativo
  /// - a guarnição já está completa
  /// - a guarnição já tem cão de serviço diferente
  Future<void> assumeVehicle({
    required String handlerId,
    String? handlerAuthUid,
    String? handlerEmail,
    String? handlerName,
    required String dogId,
    required Vehicle vehicle,
    required String role,
  }) async {
    if (!CrewRole.isValid(role)) {
      throw StateError(
        'Função inválida: $role. Valores permitidos: ${CrewRole.valuesList}',
      );
    }

    await _validateVehicleCanBeAssumed(
      vehicle: vehicle,
      serviceDogId: dogId,
      excludingHandlerId: handlerId,
    );
    await _validateRoleIsFree(
      vehicleId: vehicle.id,
      role: role,
      excludingHandlerId: handlerId,
    );

    final activeRef = _activeShiftDoc(handlerId);
    final joinedAt = Timestamp.fromDate(DateTime.now());
    final crewId = _crewIdFor(vehicle.id);

    return _db.runTransaction((transaction) async {
      final activeSnapshot = await transaction.get(activeRef);
      final activeData = activeSnapshot.data();
      final shiftId = activeData?['shiftId'] as String?;
      final previousVehicleId = activeData?['vehicle_id'] as String?;
      final activeDogId =
          activeData?['service_dog_id']?.toString().trim() ??
          activeData?['serviceDogId']?.toString().trim() ??
          activeData?['dogId']?.toString().trim() ??
          activeData?['currentDogId']?.toString().trim() ??
          dogId;
      if (!activeSnapshot.exists ||
          activeData == null ||
          activeData['status'] != 'active' ||
          activeDogId.isEmpty) {
        throw StateError('Turno ativo não encontrado para assumir viatura');
      }

      final vehicleFields = _vehicleFields(vehicle);
      final crewFields =
          _crewFields(crewId: crewId, role: role, status: 'active');
      // active_shifts/shift_logs: sem 'name'
      final handlerFieldsBasic = {
        'auth_uid': _nonEmpty(handlerAuthUid),
        'handler_email': _nonEmpty(handlerEmail)?.toLowerCase(),
      };
      // members: com 'name'
      final handlerFieldsWithName = {
        'auth_uid': _nonEmpty(handlerAuthUid),
        'handler_email': _nonEmpty(handlerEmail)?.toLowerCase(),
        'name': _nonEmpty(handlerName),
      };
      final vehicleChange = previousVehicleId != null &&
              previousVehicleId.isNotEmpty &&
              previousVehicleId != vehicle.id
          ? {
              'from_vehicle_id': previousVehicleId,
              'to_vehicle_id': vehicle.id,
              'at': joinedAt,
            }
          : null;

      // ── active_shifts ──
      transaction.set(activeRef, {
        ...vehicleFields,
        ...crewFields,
        ...handlerFieldsBasic,
        'vehicle_joined_at': joinedAt,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // ── shift_logs (vehicleChanges array) ──
      if (shiftId != null && shiftId.isNotEmpty) {
        transaction.set(_shiftLogs.doc(shiftId), {
          ...vehicleFields,
          ...crewFields,
          ...handlerFieldsBasic,
          'vehicle_joined_at': joinedAt,
          if (vehicleChange != null)
            'vehicleChanges': FieldValue.arrayUnion([vehicleChange]),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      // ── vehicle_crews/{vehicle_id} — só atualiza, não sobrescreve created_at ──
      final crewDocData = <String, dynamic>{
        'id': crewId,
        'vehicle_id': vehicle.id,
        'vehicle_label': vehicle.label,
        'vehicle_prefix': vehicle.prefix,
        'vehicle_model': vehicle.modelName,
        'vehicle_unit': vehicle.unit,
        'crew_size': vehicle.crewSize,
        'service_dog_id': activeDogId,
        'titular_handler_id': _nonEmpty(activeData['titular_handler_id']) ??
            handlerId,
        'active': true,
        'updated_at': FieldValue.serverTimestamp(),
        // ended_at: NÃO toca — só abertura limpa (startShift)
        // created_at: NÃO sobrescreve — só abertura limpa (startShift)
      };
      transaction.set(
        _vehicleCrews.doc(crewId),
        crewDocData,
        SetOptions(merge: true),
      );

      // ── members/{ra} ──
      transaction.set(
        _vehicleCrews.doc(crewId).collection('members').doc(handlerId),
        {
          'handler_id': handlerId,
          ...handlerFieldsWithName,
          'role': role,
          'status': 'active',
          'dog_id': activeDogId,
          'joined_at': FieldValue.serverTimestamp(),
          'responded_at': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  // ──────────────────────────────────────────────────────────
  // SWITCH DOG
  // ──────────────────────────────────────────────────────────

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
      final transactionVehicleId =
          activeData?['vehicle_id']?.toString().trim();
      final crewId = activeData?['vehicle_crew_id']?.toString().trim();

      transaction.set(activeRef, {
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

  // ──────────────────────────────────────────────────────────
  // END SHIFT  (encerramento individual + possible crew closure)
  // ──────────────────────────────────────────────────────────

  Future<void> endShift(String handlerId) async {
    final activeRef = _activeShiftDoc(handlerId);
    final endedAt = Timestamp.fromDate(DateTime.now());

    // Phase 1: ler estado antes da transaction
    final activeSnapshot = await activeRef.get();
    final activeData = activeSnapshot.data();
    final shiftId = activeData?['shiftId'] as String?;
    final crewId = activeData?['vehicle_crew_id']?.toString().trim();
    final vehicleId = activeData?['vehicle_id']?.toString().trim();
    final dogId = activeData?['service_dog_id']?.toString().trim();

    // Verificar se é o último member ativo da guarnição
    final bool closeCrew =
        crewId != null &&
        crewId.isNotEmpty &&
        vehicleId != null &&
        vehicleId.isNotEmpty &&
        !(await _crewHasOtherActiveMembers(
          crewId: crewId,
          excludingHandlerId: handlerId,
        ));

    // Phase 2: ler members e doc pai antes da transaction (para o snapshot)
    final List<QueryDocumentSnapshot<Map<String, dynamic>>>? allMembers =
        closeCrew ? await _getAllMembers(crewId) : null;
    final DocumentSnapshot<Map<String, dynamic>>? crewDoc =
        closeCrew ? await _vehicleCrews.doc(crewId).get() : null;

    // Phase 3: transaction atômica
    return _db.runTransaction((transaction) async {
      // ── active_shifts — marca como ended ──
      transaction.set(activeRef, {
        'status': 'ended',
        'endedAt': endedAt,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // ── shift_logs ──
      if (shiftId != null && shiftId.isNotEmpty) {
        transaction.set(_shiftLogs.doc(shiftId), {
          'status': 'ended',
          'endedAt': endedAt,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      // ── vehicle_crews/{crewId}/members/{handlerId} — marca saída ──
      if (crewId != null && crewId.isNotEmpty) {
        transaction.set(
          _vehicleCrews.doc(crewId).collection('members').doc(handlerId),
          {
            'status': 'ended',
            'left_at': endedAt,
            'dog_id': dogId,
            'updated_at': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        if (closeCrew) {
          // Criar snapshot imutável da guarnição
          _writeCrewHistorySnapshot(
            transaction: transaction,
            crewId: crewId,
            vehicleId: vehicleId,
            membersDocs: allMembers ?? [],
            crewData: crewDoc?.data(),
            endedAt: endedAt,
            endedBy: handlerId,
            shiftIds:
                shiftId != null && shiftId.isNotEmpty ? [shiftId] : <String>[],
          );

          // Marcar guarnição como encerrada
          transaction.set(_vehicleCrews.doc(crewId), {
            'active': false,
            'ended_at': endedAt,
            'updated_at': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      }
    });
  }

  // ──────────────────────────────────────────────────────────
  // TRANSFER TO VEHICLE  (troca de viatura)
  // ──────────────────────────────────────────────────────────

  /// Troca de viatura: sai da guarnição atual e entra na nova.
  /// Detecta se a guarnição de origem fica sem members ativos e cria o
  /// snapshot de histórico.
  Future<void> transferToVehicle({
    required String handlerId,
    required String dogId,
    required Vehicle newVehicle,
    required String newRole,
    String? handlerAuthUid,
    String? handlerEmail,
    String? handlerName,
  }) async {
    if (!CrewRole.isValid(newRole)) {
      throw StateError(
        'Função inválida: $newRole. Valores permitidos: ${CrewRole.valuesList}',
      );
    }

    await _validateVehicleCanBeAssumed(
      vehicle: newVehicle,
      serviceDogId: dogId,
      excludingHandlerId: handlerId,
    );
    await _validateRoleIsFree(
      vehicleId: newVehicle.id,
      role: newRole,
      excludingHandlerId: handlerId,
    );

    final activeRef = _activeShiftDoc(handlerId);
    final newCrewId = _crewIdFor(newVehicle.id);
    final transferredAt = Timestamp.fromDate(DateTime.now());

    // Phase 1: ler estado antes da transaction
    final activeSnapshot = await activeRef.get();
    final activeData = activeSnapshot.data();
    final shiftId = activeData?['shiftId'] as String?;
    final previousCrewId =
        activeData?['vehicle_crew_id']?.toString().trim();
    final previousVehicleId =
        activeData?['vehicle_id']?.toString().trim();

    if (!activeSnapshot.exists ||
        activeData == null ||
        activeData['status'] != 'active') {
      throw StateError('Turno ativo não encontrado');
    }

    // Verificar se a guarnição anterior vai ficar sem members ativos
    final bool closePreviousCrew = previousCrewId != null &&
        previousCrewId.isNotEmpty &&
        previousCrewId != newCrewId &&
        !(await _crewHasOtherActiveMembers(
          crewId: previousCrewId,
          excludingHandlerId: handlerId,
        ));

    // Phase 2: ler dados para o snapshot da guarnição anterior
    final List<QueryDocumentSnapshot<Map<String, dynamic>>>?
        previousMembersDocs =
        closePreviousCrew ? await _getAllMembers(previousCrewId) : null;
    final DocumentSnapshot<Map<String, dynamic>>? previousCrewDoc =
        closePreviousCrew
            ? await _vehicleCrews.doc(previousCrewId).get()
            : null;

    // Phase 3: transaction atômica
    return _db.runTransaction((transaction) async {
      // ── 1) Sair da guarnição anterior ──
      if (previousCrewId != null &&
          previousCrewId.isNotEmpty &&
          previousCrewId != newCrewId) {
        transaction.set(
          _vehicleCrews.doc(previousCrewId).collection('members').doc(handlerId),
          {
            'status': 'ended',
            'left_at': transferredAt,
            'dog_id': dogId,
            'updated_at': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        if (closePreviousCrew) {
          _writeCrewHistorySnapshot(
            transaction: transaction,
            crewId: previousCrewId,
            vehicleId: previousVehicleId ?? previousCrewId,
            membersDocs: previousMembersDocs ?? [],
            crewData: previousCrewDoc?.data(),
            endedAt: transferredAt,
            endedBy: handlerId,
            shiftIds:
                shiftId != null && shiftId.isNotEmpty ? [shiftId] : <String>[],
          );

          transaction.set(_vehicleCrews.doc(previousCrewId), {
            'active': false,
            'ended_at': transferredAt,
            'updated_at': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      }

      // ── 2) Entrar na nova guarnição ──
      final vehicleFields = _vehicleFields(newVehicle);
      final crewFields =
          _crewFields(crewId: newCrewId, role: newRole, status: 'active');
      // active_shifts/shift_logs: sem 'name'
      final handlerFieldsBasic = {
        'auth_uid': _nonEmpty(handlerAuthUid),
        'handler_email': _nonEmpty(handlerEmail)?.toLowerCase(),
      };
      // members: com 'name'
      final handlerFieldsWithName = {
        'auth_uid': _nonEmpty(handlerAuthUid),
        'handler_email': _nonEmpty(handlerEmail)?.toLowerCase(),
        'name': _nonEmpty(handlerName),
      };
      final vehicleChange = previousVehicleId != null &&
              previousVehicleId.isNotEmpty &&
              previousVehicleId != newVehicle.id
          ? {
              'from_vehicle_id': previousVehicleId,
              'to_vehicle_id': newVehicle.id,
              'at': transferredAt,
            }
          : null;

      transaction.set(activeRef, {
        ...vehicleFields,
        ...crewFields,
        ...handlerFieldsBasic,
        'vehicle_joined_at': transferredAt,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // ── 3) shift_logs — vehicleChanges array ──
      if (shiftId != null && shiftId.isNotEmpty) {
        transaction.set(_shiftLogs.doc(shiftId), {
          ...vehicleFields,
          ...crewFields,
          ...handlerFieldsBasic,
          'vehicle_joined_at': transferredAt,
          if (vehicleChange != null)
            'vehicleChanges': FieldValue.arrayUnion([vehicleChange]),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      // ── 4) vehicle_crews/{newCrewId} — só atualiza (adesão) ──
      transaction.set(_vehicleCrews.doc(newCrewId), {
        'id': newCrewId,
        'vehicle_id': newVehicle.id,
        'vehicle_label': newVehicle.label,
        'vehicle_prefix': newVehicle.prefix,
        'vehicle_model': newVehicle.modelName,
        'vehicle_unit': newVehicle.unit,
        'crew_size': newVehicle.crewSize,
        'service_dog_id': dogId,
        'active': true,
        'updated_at': FieldValue.serverTimestamp(),
        // NÃO sobrescreve created_at nem ended_at aqui
      }, SetOptions(merge: true));

      transaction.set(
        _vehicleCrews.doc(newCrewId).collection('members').doc(handlerId),
        {
          'handler_id': handlerId,
          ...handlerFieldsWithName,
          'role': newRole,
          'status': 'active',
          'dog_id': dogId,
          'joined_at': FieldValue.serverTimestamp(),
          'responded_at': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  // ──────────────────────────────────────────────────────────
  // PRIVATE — VALIDAÇÕES
  // ──────────────────────────────────────────────────────────

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

    final crewSnapshot =
        await _vehicleCrews.doc(_crewIdFor(vehicle.id)).get();
    final crewData = crewSnapshot.data();
    final existingServiceDogId =
        crewData?['service_dog_id']?.toString().trim();
    final existingTitular =
        crewData?['titular_handler_id']?.toString().trim();
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

  /// Verifica que [role] não está ocupado por outro member ativo na
  /// guarnição de [vehicleId].
  Future<void> _validateRoleIsFree({
    required String vehicleId,
    required String role,
    required String excludingHandlerId,
  }) async {
    final membersSnapshot = await _vehicleCrews
        .doc(_crewIdFor(vehicleId))
        .collection('members')
        .where('role', isEqualTo: role)
        .where('status', whereIn: ['active', 'pending'])
        .get();

    for (final doc in membersSnapshot.docs) {
      if (doc.id != excludingHandlerId) {
        throw StateError(
          'A função "$role" já está ocupada na guarnição.',
        );
      }
    }
  }

  // ──────────────────────────────────────────────────────────
  // PRIVATE — WRITE SNAPSHOT DE HISTÓRICO DA GUARNIÇÃO
  // ──────────────────────────────────────────────────────────

  /// Escreve o doc em vehicle_crew_history com snapshot imutável da guarnição.
  /// Chamado dentro de runTransaction — usa transaction.set().
  void _writeCrewHistorySnapshot({
    required Transaction transaction,
    required String crewId,
    required String vehicleId,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> membersDocs,
    required Map<String, dynamic>? crewData,
    required Timestamp endedAt,
    required String endedBy,
    required List<String> shiftIds,
  }) {
    final historyRef = _vehicleCrewHistory.doc();
    final startedAt = crewData?['created_at'] as Timestamp?;
    final vehicleLabel = crewData?['vehicle_label']?.toString();
    final vehiclePrefix = crewData?['vehicle_prefix']?.toString();
    final vehicleModel = crewData?['vehicle_model']?.toString();
    final dogChanges = (crewData?['dog_changes'] as List<dynamic>?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList() ??
        <Map<String, dynamic>>[];

    final members = membersDocs.map((doc) {
      final data = doc.data();
      return {
        'handler_id': doc.id,
        'role': data['role'] ?? '',
        'joined_at': data['joined_at'],
        'left_at': data['left_at'],
        'dog_id': data['dog_id'],
      };
    }).toList();

    transaction.set(historyRef, {
      'id': historyRef.id,
      'vehicle_id': vehicleId,
      'vehicle_label': vehicleLabel,
      'vehicle_prefix': vehiclePrefix,
      'vehicle_model': vehicleModel,
      'period': {
        'started_at': startedAt ?? FieldValue.serverTimestamp(),
        'ended_at': endedAt,
      },
      'members': members,
      'dog_changes': dogChanges,
      'ended_by': endedBy,
      'shift_ids': shiftIds,
      'created_at': FieldValue.serverTimestamp(),
    });
  }

  // ──────────────────────────────────────────────────────────
  // PRIVATE — HELPERS
  // ──────────────────────────────────────────────────────────

  String _crewIdFor(String vehicleId) => vehicleId.trim();

  void _upsertCrewInBatch({
    required WriteBatch batch,
    required Map<String, dynamic> crewDocFields,
    required String handlerId,
    required Map<String, dynamic> handlerFields,
    required String role,
    required String status,
    required String dogId,
    required String crewId,
  }) {
    batch.set(_vehicleCrews.doc(crewId), crewDocFields, SetOptions(merge: true));
    batch.set(
      _vehicleCrews.doc(crewId).collection('members').doc(handlerId),
      {
        'handler_id': handlerId,
        ...handlerFields,
        'role': role,
        'status': status,
        'dog_id': dogId,
        'joined_at': FieldValue.serverTimestamp(),
        'responded_at': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  /// Retorna os campos para o doc vehicle_crews/{crewId}.
  /// Se [clearEndedAt] é true, remove ended_at ( FieldValue.delete()).
  Map<String, dynamic> _crewDocFields({
    required String crewId,
    required Vehicle vehicle,
    required String serviceDogId,
    required String handlerId,
    String? handlerAuthUid,
    String? handlerEmail,
    String? handlerName,
    required String role,
    required String status,
    bool clearEndedAt = false,
  }) {
    final fields = <String, dynamic>{
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
    };
    if (clearEndedAt) {
      fields['ended_at'] = FieldValue.delete();
    }
    return fields;
  }

  Map<String, dynamic> _vehicleFields(Vehicle? vehicle) {
    if (vehicle == null) {
      return const {
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

  Map<String, dynamic> _shiftGroupFields({
    String? shiftGroupId,
    String? shiftGroupCode,
    String? shiftGroupLabel,
  }) {
    return {
      if (_nonEmpty(shiftGroupId) != null)
        'shift_group_id': _nonEmpty(shiftGroupId),
      if (_nonEmpty(shiftGroupCode) != null)
        'shift_group_code': _nonEmpty(shiftGroupCode),
      if (_nonEmpty(shiftGroupLabel) != null)
        'shift_group_label': _nonEmpty(shiftGroupLabel),
    };
  }

  String? _nonEmpty(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }
}
