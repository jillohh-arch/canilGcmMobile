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
    final crewFields = vehicle == null
        ? const <String, dynamic>{}
        : _crewFields(crewId: crewId!, role: 'motorista', status: 'active');
    final handlerFields = _handlerIdentityFields(
      authUid: handlerAuthUid,
      email: handlerEmail,
      name: handlerName,
    );
    final shiftGroupFields = _shiftGroupFields(
      shiftGroupId: shiftGroupId,
      shiftGroupCode: shiftGroupCode,
      shiftGroupLabel: shiftGroupLabel,
    );

    // ── shift_logs (criado como ended_at=null) ──
    batch.set(logRef, {
      'id': logRef.id,
      'handlerId': handlerId,
      ...handlerFields,
      ...shiftGroupFields,
      'initialDogId': dogId,
      'currentDogId': dogId,
      'service_dog_id': dogId,
      ...vehicleFields,
      ...crewFields,
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
      ...handlerFields,
      ...shiftGroupFields,
      'dogId': dogId,
      'service_dog_id': dogId,
      ...vehicleFields,
      ...crewFields,
      'status': 'active',
      'startedAt': Timestamp.fromDate(startedAt),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // ── vehicle_crews/{vehicle_id} (abertura limpa — cleared ended_at) ──
    if (vehicle != null && crewId != null) {
      _upsertCrewInBatch(
        batch: batch,
        vehicle: vehicle,
        crewId: crewId,
        serviceDogId: dogId,
        handlerId: handlerId,
        handlerAuthUid: handlerAuthUid,
        handlerEmail: handlerEmail,
        handlerName: handlerName,
        role: 'motorista',
        status: 'active',
        clearEndedAt: true, // abertura limpa ended_at
      );
    }

    try {
      await batch.commit();
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        debugPrint(
          '[ShiftService] batch bloqueado por regras (${e.code}); '
          'gravando só log do turno.',
        );
        await logRef.set({
          'id': logRef.id,
          'handlerId': handlerId,
          ...handlerFields,
          'initialDogId': dogId,
          'currentDogId': dogId,
          'service_dog_id': dogId,
          ...vehicleFields,
          'crew_role': crewFields['crew_role'],
          'crew_status': crewFields['crew_status'],
          'vehicle_crew_id': crewFields['vehicle_crew_id'],
          'status': 'active',
          'startedAt': Timestamp.fromDate(startedAt),
          'endedAt': null,
          'dogSwitches': <Map<String, dynamic>>[],
          'vehicleChanges': <Map<String, dynamic>>[],
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return;
      }
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
  /// - a guarnição já está completa (cargo cheia)
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
    // Validar que a função está livre
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

      final vehicleFields = {
        ..._vehicleFields(vehicle),
        ..._crewFields(crewId: crewId, role: role, status: 'active'),
        ..._handlerIdentityFields(
          authUid: handlerAuthUid,
          email: handlerEmail,
          name: handlerName,
        ),
        'vehicle_joined_at': joinedAt,
      };

      // ── active_shifts ──
      transaction.set(activeRef, {
        ...vehicleFields,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // ── shift_logs (vehicle_changes array) ──
      if (shiftId != null && shiftId.isNotEmpty) {
        final vehicleChange = previousVehicleId != null &&
                previousVehicleId.isNotEmpty &&
                previousVehicleId != vehicle.id
            ? {
                'from_vehicle_id': previousVehicleId,
                'to_vehicle_id': vehicle.id,
                'at': joinedAt,
              }
            : null;

        transaction.set(_shiftLogs.doc(shiftId), {
          ...vehicleFields,
          if (vehicleChange != null)
            'vehicleChanges': FieldValue.arrayUnion([vehicleChange]),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      // ── vehicle_crews/{vehicle_id} — só atualiza, não sobrescreve created_at ──
      transaction.set(_vehicleCrews.doc(crewId), {
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
      }, SetOptions(merge: true));

      // ── members/{ra} ──
      transaction.set(
        _vehicleCrews.doc(crewId).collection('members').doc(handlerId),
        {
          'handler_id': handlerId,
          ..._handlerIdentityFields(
            authUid: handlerAuthUid,
            email: handlerEmail,
            name: handlerName,
          ),
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

  // ──────────────────────────────────────────────────────────
  // END SHIFT  (encerramento individual + Possible crew closure)
  // ──────────────────────────────────────────────────────────

  Future<void> endShift(String handlerId) {
    final activeRef = _activeShiftDoc(handlerId);
    final endedAt = Timestamp.fromDate(DateTime.now());

    return _db.runTransaction((transaction) async {
      final activeSnapshot = await transaction.get(activeRef);
      final activeData = activeSnapshot.data();
      final shiftId = activeData?['shiftId'] as String?;
      final crewId = activeData?['vehicle_crew_id']?.toString().trim();
      final vehicleId = activeData?['vehicle_id']?.toString().trim();
      final dogId = activeData?['service_dog_id']?.toString().trim();

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
            'dog_id': dogId, // snapshot do cão no momento da saída
            'updated_at': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        // ── Verificar se é o ÚLTIMO member ativo → encerrar guarnição ──
        if (vehicleId != null && vehicleId.isNotEmpty) {
          // Lê todos os members para verificar se há outros ativos
          final membersSnapshot = await transaction.get(
            _vehicleCrews.doc(crewId).collection('members'),
          );

          bool hasOtherActive = false;
          for (final doc in membersSnapshot.docs) {
            final data = doc.data();
            final status = data['status']?.toString();
            if (doc.id != handlerId &&
                (status == 'active' || status == 'pending')) {
              hasOtherActive = true;
              break;
            }
          }

          if (!hasOtherActive) {
            // ÚLTIMO member saiu — criar snapshot imutável da guarnição
            _createCrewHistorySnapshot(
              transaction: transaction,
              crewId: crewId,
              vehicleId: vehicleId,
              membersSnapshot: membersSnapshot,
              endedAt: endedAt,
              endedBy: handlerId,
              shiftIds: shiftId != null && shiftId.isNotEmpty
                  ? [shiftId]
                  : <String>[],
            );

            // Marcar guarnição como encerrada
            transaction.set(_vehicleCrews.doc(crewId), {
              'active': false,
              'ended_at': endedAt,
              'updated_at': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          }
        }
      }
    });
  }

  // ──────────────────────────────────────────────────────────
  // ASSUME VEHICLE FROM ANOTHER VEHICLE (troca de viatura)
  // ──────────────────────────────────────────────────────────

  /// Troca de viatura: sai da guarnição atual (se houver) e entra na nova.
  /// Equivalente a: endShift na guarnição atual + assumeVehicle na nova.
  /// Tratamento transacional: detecta se a guarnição de origem fica sem
  /// members ativos e cria o snapshot de histórico.
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

    // Validar nova viatura
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

    return _db.runTransaction((transaction) async {
      final activeSnapshot = await transaction.get(activeRef);
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

      // ── 1) Sair da guarnição anterior ──
      if (previousCrewId != null &&
          previousCrewId.isNotEmpty &&
          previousCrewId != newCrewId) {
        // Marcar saída do member na guarnição anterior
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

        // Verificar se a guarnição anterior ficou sem members ativos
        final prevMembersSnapshot = await transaction.get(
          _vehicleCrews.doc(previousCrewId).collection('members'),
        );

        bool hasOtherActive = false;
        for (final doc in prevMembersSnapshot.docs) {
          final status = doc.data()['status']?.toString();
          if (doc.id != handlerId &&
              (status == 'active' || status == 'pending')) {
            hasOtherActive = true;
            break;
          }
        }

        if (!hasOtherActive) {
          // Fechar guarnição anterior
          _createCrewHistorySnapshot(
            transaction: transaction,
            crewId: previousCrewId,
            vehicleId: previousVehicleId ?? previousCrewId,
            membersSnapshot: prevMembersSnapshot,
            endedAt: transferredAt,
            endedBy: handlerId,
            shiftIds: shiftId != null && shiftId.isNotEmpty
                ? [shiftId]
                : <String>[],
          );

          transaction.set(_vehicleCrews.doc(previousCrewId), {
            'active': false,
            'ended_at': transferredAt,
            'updated_at': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      }

      // ── 2) Entrar na nova guarnição ──
      final vehicleFields = {
        ..._vehicleFields(newVehicle),
        ..._crewFields(crewId: newCrewId, role: newRole, status: 'active'),
        ..._handlerIdentityFields(
          authUid: handlerAuthUid,
          email: handlerEmail,
          name: handlerName,
        ),
        'vehicle_joined_at': transferredAt,
      };

      transaction.set(activeRef, {
        ...vehicleFields,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // ── 3) shift_logs — vehicle_changes array ──
      if (shiftId != null && shiftId.isNotEmpty) {
        final vehicleChange = previousVehicleId != null &&
                previousVehicleId.isNotEmpty &&
                previousVehicleId != newVehicle.id
            ? {
                'from_vehicle_id': previousVehicleId,
                'to_vehicle_id': newVehicle.id,
                'at': transferredAt,
              }
            : null;

        transaction.set(_shiftLogs.doc(shiftId), {
          ...vehicleFields,
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
          ..._handlerIdentityFields(
            authUid: handlerAuthUid,
            email: handlerEmail,
            name: handlerName,
          ),
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
  // PRIVATE — SNAPSHOT DE HISTÓRICO DA GUARNIÇÃO
  // ──────────────────────────────────────────────────────────

  /// Cria o doc em vehicle_crew_history com snapshot imutável da guarnição.
  /// Chamado dentro de transaction quando o último member ativo sai.
  void _createCrewHistorySnapshot({
    required Transaction transaction,
    required String crewId,
    required String vehicleId,
    required QuerySnapshot<Map<String, dynamic>> membersSnapshot,
    required Timestamp endedAt,
    required String endedBy,
    required List<String> shiftIds,
  }) {
    // Ler doc pai da guarnição para metadata
    final crewDoc = transaction.get(_vehicleCrews.doc(crewId));
    final crewData = crewDoc.data();

    final historyRef = _vehicleCrewHistory.doc();
    final startedAt = crewData?['created_at'] as Timestamp?;
    final vehicleLabel = crewData?['vehicle_label']?.toString();
    final vehiclePrefix = crewData?['vehicle_prefix']?.toString();
    final vehicleModel = crewData?['vehicle_model']?.toString();
    final dogChanges = (crewData?['dog_changes'] as List<dynamic>?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList() ??
        <Map<String, dynamic>>[];

    // Montar lista de members completa (todos que passaram pela guarnição)
    final members = membersSnapshot.docs.map((doc) {
      final data = doc.data();
      return {
        'handler_id': doc.id,
        'name': data['name'] ?? data['handler_name'],
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
    required Vehicle vehicle,
    required String crewId,
    required String serviceDogId,
    required String handlerId,
    String? handlerAuthUid,
    String? handlerEmail,
    String? handlerName,
    required String role,
    required String status,
    bool clearEndedAt = false,
  }) {
    final crewDocData = <String, dynamic>{
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
      // Abertura: garante que ended_at não está presente (limpa fossilização)
      crewDocData['ended_at'] = FieldValue.delete();
    }

    batch.set(_vehicleCrews.doc(crewId), crewDocData, SetOptions(merge: true));

    batch.set(
      _vehicleCrews.doc(crewId).collection('members').doc(handlerId),
      {
        'handler_id': handlerId,
        ..._handlerIdentityFields(
          authUid: handlerAuthUid,
          email: handlerEmail,
          name: handlerName,
        ),
        'role': role,
        'status': status,
        'dog_id': serviceDogId,
        'joined_at': FieldValue.serverTimestamp(),
        'responded_at': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
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
    String? name,
  }) {
    return {
      'auth_uid': _nonEmpty(authUid),
      'handler_email': _nonEmpty(email)?.toLowerCase(),
      'name': _nonEmpty(name),
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
