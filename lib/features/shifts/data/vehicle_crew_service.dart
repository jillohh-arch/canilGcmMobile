import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:canil_gcm/features/shifts/domain/active_shift_session.dart';
import 'package:canil_gcm/features/shifts/domain/vehicle_crew.dart';

class VehicleCrewService {
  VehicleCrewService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _crews =>
      _db.collection('vehicle_crews');

  // ──────────────────────────────────────────────────────────
  // WATCH / GET
  // ──────────────────────────────────────────────────────────

  Stream<VehicleCrew?> watchCrew(String crewId) {
    if (crewId.trim().isEmpty) {
      return Stream.value(null);
    }
    return _crews.doc(crewId).snapshots().map((snapshot) {
      final data = snapshot.data();
      if (!snapshot.exists || data == null) return null;
      return VehicleCrew.fromJson(data, snapshot.id);
    });
  }

  Future<VehicleCrew?> getCrew(String crewId) async {
    if (crewId.trim().isEmpty) return null;
    final snapshot = await _crews.doc(crewId.trim()).get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) return null;
    return VehicleCrew.fromJson(data, snapshot.id);
  }

  Stream<List<VehicleCrewMember>> watchMembers(String crewId) {
    if (crewId.trim().isEmpty) {
      return Stream.value(const []);
    }
    return _crews
        .doc(crewId)
        .collection('members')
        .snapshots()
        .map(
          (snapshot) => _sortMembers(
            snapshot.docs
                .map((doc) => VehicleCrewMember.fromJson(doc.data()))
                .where((member) => member.handlerId.isNotEmpty)
                .toList(),
          ),
        );
  }

  Future<List<VehicleCrewMember>> getMembers(String crewId) async {
    if (crewId.trim().isEmpty) return const [];
    final snapshot = await _crews
        .doc(crewId.trim())
        .collection('members')
        .get();
    return _sortMembers(
      snapshot.docs
          .map((doc) => VehicleCrewMember.fromJson(doc.data()))
          .where((member) => member.handlerId.isNotEmpty)
          .toList(),
    );
  }

  /// Retorna todos os members que já passaram pela guarnição
  /// (ativos e encerrados), ordenados por joinedAt.
  Future<List<VehicleCrewMember>> getAllMembers(String crewId) async {
    if (crewId.trim().isEmpty) return const [];
    final snapshot = await _crews
        .doc(crewId.trim())
        .collection('members')
        .orderBy('joined_at', descending: false)
        .get();
    return snapshot.docs
        .map((doc) => VehicleCrewMember.fromJson(doc.data()))
        .where((member) => member.handlerId.isNotEmpty)
        .toList();
  }

  /// Retorna o estado operacional da guarnição:
  /// - 'operational': tem motorista + encarregado
  /// - 'incomplete': tem membros mas falta motorista ou encarregado
  /// - 'empty': sem membros ativos
  Future<String> getCrewOperationalStatus(String crewId) async {
    final members = await getMembers(crewId);
    final active = members.where((m) => m.isActive).toList();

    if (active.isEmpty) return 'empty';

    final hasMotorista =
        active.any((m) => m.role == 'motorista');
    final hasEncarregado =
        active.any((m) => m.role == 'encarregado');

    return (hasMotorista && hasEncarregado) ? 'operational' : 'incomplete';
  }

  Stream<List<ActiveShiftSession>> watchAvailableHandlers({
    required String crewId,
    required String currentHandlerId,
  }) {
    return _db
        .collection('active_shifts')
        .where('status', isEqualTo: 'active')
        .snapshots()
        .map((snapshot) {
          final handlers = snapshot.docs
              .map((doc) => ActiveShiftSession.fromJson(doc.data()))
              .where((session) => session.handlerId != currentHandlerId)
              .where(
                (session) =>
                    !session.hasVehicle || session.vehicleCrewId == crewId,
              )
              .toList();
          handlers.sort((a, b) => a.handlerId.compareTo(b.handlerId));
          return handlers;
        });
  }

  // ──────────────────────────────────────────────────────────
  // PRIVATE
  // ──────────────────────────────────────────────────────────

  /// Ordena members com prioridade: ativos primeiro, depois por papel
  /// (motorista > encarregado > auxiliares > k9), depois por joinedAt.
  List<VehicleCrewMember> _sortMembers(List<VehicleCrewMember> members) {
    members.sort((a, b) {
      // Ativos primeiro
      if (a.isActive != b.isActive) return a.isActive ? -1 : 1;

      // Prioridade de papel
      final aPriority = _rolePriority(a.role);
      final bPriority = _rolePriority(b.role);
      if (aPriority != bPriority) return aPriority.compareTo(bPriority);

      // joinedAt
      final joined = a.joinedAt.compareTo(b.joinedAt);
      if (joined != 0) return joined;

      return a.handlerId.compareTo(b.handlerId);
    });
    return members;
  }

  int _rolePriority(String role) {
    switch (role) {
      case 'motorista':
        return 0;
      case 'encarregado':
        return 1;
      case 'auxiliar_1':
        return 2;
      case 'auxiliar_2':
        return 3;
      case 'k9':
        return 4;
      default:
        return 99; // indefinido por enquanto
    }
  }
}
