import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:canil_gcm/features/users/domain/user.dart';

class UserService {
  UserService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

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
    if (!doc.exists) return null;
    return UserModel.fromJson(doc.data()!);
  }
}
