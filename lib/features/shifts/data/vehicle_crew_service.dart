import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:canil_gcm/features/shifts/domain/active_shift_session.dart';
import 'package:canil_gcm/features/shifts/domain/vehicle_crew.dart';

class VehicleCrewService {
  VehicleCrewService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _crews =>
      _db.collection('vehicle_crews');

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

  List<VehicleCrewMember> _sortMembers(List<VehicleCrewMember> members) {
    members.sort((a, b) {
      if (a.isTitular != b.isTitular) return a.isTitular ? -1 : 1;
      final aWeight = _statusWeight(a);
      final bWeight = _statusWeight(b);
      if (aWeight != bWeight) return aWeight.compareTo(bWeight);
      final joined = a.joinedAt.compareTo(b.joinedAt);
      if (joined != 0) return joined;
      return a.handlerId.compareTo(b.handlerId);
    });
    return members;
  }

  int _statusWeight(VehicleCrewMember member) {
    if (member.isActive) return 0;
    if (member.isPending) return 1;
    if (member.isDeclined) return 2;
    return 3;
  }
}
