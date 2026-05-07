import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:canil_gcm/features/dogs/domain/dog.dart';

class DogService {
  DogService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  Stream<List<Dog>> getDogs() {
    return _db.collection('dogs').snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => _dogFromData(doc.data(), doc.id))
          .toList();
    });
  }

  Stream<Dog?> watchDog(String id) {
    return _db.collection('dogs').doc(id).snapshots().map((doc) {
      final data = doc.data();
      if (!doc.exists || data == null) return null;
      return _dogFromData(data, doc.id);
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
    final data = <String, dynamic>{};
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

  Dog _dogFromData(Map<String, dynamic> data, String id) {
    final json = Map<String, dynamic>.from(data);
    json['id'] ??= id;
    return Dog.fromJson(json);
  }
}
