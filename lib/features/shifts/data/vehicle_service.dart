import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:canil_gcm/features/shifts/domain/vehicle.dart';

class VehicleService {
  VehicleService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _vehicles =>
      _db.collection('vehicles');

  Stream<List<Vehicle>> watchActiveVehicles() {
    return _vehicles.snapshots().map((snapshot) {
      final vehicles = snapshot.docs
          .map((doc) => Vehicle.fromJson(doc.data(), doc.id))
          .where((vehicle) => vehicle.active)
          .toList();
      vehicles.sort((a, b) => a.label.compareTo(b.label));
      return vehicles;
    });
  }

  Stream<Map<String, int>> watchVehicleOccupancies() {
    return _db
        .collection('active_shifts')
        .where('status', isEqualTo: 'active')
        .snapshots()
        .map((snapshot) {
          final counts = <String, int>{};
          for (final doc in snapshot.docs) {
            final vehicleId = doc.data()['vehicle_id']?.toString().trim();
            if (vehicleId == null || vehicleId.isEmpty) continue;
            counts[vehicleId] = (counts[vehicleId] ?? 0) + 1;
          }
          return counts;
        });
  }

  Future<Vehicle?> getById(String id) async {
    if (id.trim().isEmpty) return null;
    final snapshot = await _vehicles.doc(id).get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) return null;
    return Vehicle.fromJson(data, snapshot.id);
  }
}
