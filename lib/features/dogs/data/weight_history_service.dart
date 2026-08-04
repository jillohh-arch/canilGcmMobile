import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:canil_gcm/features/dogs/domain/weight_record.dart';

/// Reader exclusivo de `dogs/{dogId}/weight_records`.
class WeightHistoryService {
  WeightHistoryService({FirebaseFirestore? firestore})
    : _firestoreOverride = firestore;

  final FirebaseFirestore? _firestoreOverride;

  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _collection(String dogId) =>
      _firestore.collection('dogs').doc(dogId).collection('weight_records');

  Stream<List<WeightRecord>> watchHistory(String dogId, {int limit = 50}) {
    try {
      return _collection(dogId)
          .orderBy('measured_at', descending: true)
          .limit(limit)
          .snapshots()
          .map(_parseSnapshot);
    } catch (error, stackTrace) {
      return Stream<List<WeightRecord>>.error(error, stackTrace);
    }
  }

  Future<List<WeightRecord>> getHistory(
    String dogId, {
    DateTime? from,
    DateTime? to,
    int? limit,
  }) async {
    Query<Map<String, dynamic>> query = _collection(
      dogId,
    ).orderBy('measured_at', descending: true);
    if (from != null) {
      query = query.where(
        'measured_at',
        isGreaterThanOrEqualTo: Timestamp.fromDate(from),
      );
    }
    if (to != null) {
      query = query.where('measured_at', isLessThan: Timestamp.fromDate(to));
    }
    if (limit != null) query = query.limit(limit);
    return _parseSnapshot(await query.get());
  }

  Future<WeightRecord?> getLatest(String dogId) async {
    final records = await getHistory(dogId, limit: 1);
    return records.isEmpty ? null : records.first;
  }

  Future<Map<String, double>> getStats(
    String dogId, {
    DateTime? from,
    DateTime? to,
  }) async {
    final records = await getHistory(dogId, from: from, to: to);
    if (records.isEmpty) return {'min': 0, 'max': 0, 'avg': 0};
    final weights = records.map((record) => record.weightKg).toList();
    return {
      'min': weights.reduce((a, b) => a < b ? a : b),
      'max': weights.reduce((a, b) => a > b ? a : b),
      'avg': weights.reduce((a, b) => a + b) / weights.length,
    };
  }

  List<WeightRecord> _parseSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) => snapshot.docs
      .map((doc) => WeightRecord.fromJson(doc.data(), docId: doc.id))
      .toList(growable: false);
}
