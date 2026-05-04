import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user.dart';
import '../models/dog.dart';
import '../models/occurrence_nature.dart';
import '../models/routine_model.dart';
import 'gamification_service.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // --- Users CRUD ---
  Stream<List<UserModel>> getUsers() {
    return _db.collection('users').snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => UserModel.fromJson(doc.data()))
          .toList();
    });
  }

  Future<void> saveUser(UserModel user) async {
    await _db
        .collection('users')
        .doc(user.ra)
        .set(user.toJson(), SetOptions(merge: true));
  }

  Future<void> deleteUser(String ra) async {
    await _db.collection('users').doc(ra).delete();
  }

  Future<UserModel?> getUser(String ra) async {
    final doc = await _db.collection('users').doc(ra).get();
    if (doc.exists) {
      return UserModel.fromJson(doc.data()!);
    }
    return null;
  }

  // --- Dogs CRUD ---
  Stream<List<Dog>> getDogs() {
    return _db.collection('dogs').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => Dog.fromJson(doc.data())).toList();
    });
  }

  Future<void> saveDog(Dog dog) async {
    await _db
        .collection('dogs')
        .doc(dog.id)
        .set(dog.toJson(), SetOptions(merge: true));
  }

  Future<void> updateDogWeight(String id, double weight) async {
    await _db.collection('dogs').doc(id).set({
      'weight': weight,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteDog(String id) async {
    await _db.collection('dogs').doc(id).delete();
  }

  Future<void> updateDogDates(
    String id, {
    DateTime? lastTrainingDate,
    DateTime? lastVaccineDate,
    DateTime? lastBathDate,
    double? weight,
  }) async {
    final Map<String, dynamic> data = {};
    if (lastTrainingDate != null) {
      data['lastTrainingDate'] = lastTrainingDate.toIso8601String();
    }
    if (lastVaccineDate != null) {
      data['lastVaccineDate'] = lastVaccineDate.toIso8601String();
    }
    if (lastBathDate != null) {
      data['lastBathDate'] = lastBathDate.toIso8601String();
    }
    if (weight != null) {
      data['weight'] = weight;
    }

    if (data.isNotEmpty) {
      await _db.collection('dogs').doc(id).set(data, SetOptions(merge: true));
    }
  }

  // --- Incidents CRUD ---
  Future<void> saveIncident(dynamic incident) async {
    await _db.collection('incidents').doc(incident.id).set(incident.toJson());
  }

  Future<void> deleteIncident(String id) async {
    await _db.collection('incidents').doc(id).delete();
  }

  Future<List<dynamic>> getIncidents({String? dogId}) async {
    Query query = _db.collection('incidents');
    if (dogId != null) {
      query = query.where('dogId', isEqualTo: dogId);
    }
    // final snapshot = await query.orderBy('date', descending: true).get();
    final snapshot = await query.get(); // Deixe assim apenas para testar

    return snapshot.docs.map((doc) {
      final data = Map<String, dynamic>.from(doc.data() as Map);
      data['id'] = doc.id;
      return data;
    }).toList();
  }

  Future<List<dynamic>> getOpenIncidents({String? dogId}) async {
    final snapshot = await _db
        .collection('incidents')
        .where('status', whereIn: ['Em andamento', 'Aberta'])
        .get();

    return snapshot.docs
        .map((doc) {
          final data = Map<String, dynamic>.from(doc.data());
          data['id'] = doc.id;
          return data;
        })
        .where((data) => dogId == null || data['dogId'] == dogId)
        .toList();
  }

  Future<List<OccurrenceNature>> getOccurrenceNatures() async {
    final snapshot = await _db
        .collection('occurrence_natures')
        .where('active', isEqualTo: true)
        .get();

    final natures =
        snapshot.docs
            .map((doc) {
              final data = Map<String, dynamic>.from(doc.data());
              data['code'] ??= doc.id;
              return OccurrenceNature.fromJson(data);
            })
            .where((nature) => nature.name.trim().isNotEmpty)
            .toList()
          ..sort((a, b) => a.code.compareTo(b.code));

    return natures;
  }

  // --- Routines CRUD ---
  Future<void> addRoutine(RoutineModel routine) async {
    final docRef = _db.collection('routines').doc();
    await docRef.set(routine.toJson()..['id'] = docRef.id);

    // GAMIFICATION TRIGGER
    if (routine.handlerId.isNotEmpty) {
      await GamificationService().evaluateRoutine(routine.handlerId);
    }
  }

  Future<void> updateRoutine(RoutineModel routine) async {
    if (routine.id == null) return;
    await _db.collection('routines').doc(routine.id).update(routine.toJson());
  }

  Future<void> deleteRoutine(String id) async {
    await _db.collection('routines').doc(id).delete();
  }

  Stream<List<RoutineModel>> getRoutines({String? dogId}) {
    Query query = _db.collection('routines');
    if (dogId != null) {
      query = query.where('dogId', isEqualTo: dogId);
    }
    return query.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        return RoutineModel.fromJson(
          Map<String, dynamic>.from(doc.data() as Map),
          doc.id,
        );
      }).toList();
    });
  }
}
