import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:canil_gcm/core/services/audit_service.dart';
import 'package:canil_gcm/features/dogs/domain/weight_record.dart';

/// Service para gerenciar histórico de peso do cão.
/// Subcoleção: /dogs/{dogId}/weight_history
class WeightHistoryService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _collection(String dogId) =>
      _firestore.collection('dogs').doc(dogId).collection('weight_records');

  CollectionReference<Map<String, dynamic>> _legacyCollection(String dogId) =>
      _firestore.collection('dogs').doc(dogId).collection('weight_history');

  /// Stream do histórico de peso (mais recente primeiro).
  Stream<List<WeightRecord>> watchHistory(String dogId, {int limit = 50}) {
    return _collection(dogId)
        .orderBy('measured_at', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => WeightRecord.fromJson(doc.data(), docId: doc.id))
              .toList(),
        );
  }

  /// Busca histórico por período.
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
    if (limit != null) {
      query = query.limit(limit);
    }

    final snap = await query.get();
    return snap.docs
        .map((doc) => WeightRecord.fromJson(doc.data(), docId: doc.id))
        .toList();
  }

  /// Último peso registrado.
  Future<WeightRecord?> getLatest(String dogId) async {
    final snap = await _collection(
      dogId,
    ).orderBy('measured_at', descending: true).limit(1).get();
    if (snap.docs.isEmpty) return null;
    return WeightRecord.fromJson(
      snap.docs.first.data(),
      docId: snap.docs.first.id,
    );
  }

  /// Registra nova pesagem.
  Future<String> addRecord(String dogId, WeightRecord record) async {
    final docRef = _collection(dogId).doc();
    final entry = AuditService.buildInlineEntry(action: 'created');
    final data = {
      ...record.toJson(),
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
      'audit_trail': [entry],
    };
    await docRef.set(data);
    await _legacyCollection(dogId).doc(docRef.id).set(data);

    // Atualiza peso atual no documento principal do cão
    final dogRef = _firestore.collection('dogs').doc(dogId);
    final dogSnapshot = await dogRef.get();
    final oldWeight = (dogSnapshot.data()?['weight'] as num?)?.toDouble();
    final dogEntry = AuditService.buildInlineEntry(
      action: 'updated',
      fieldName: 'weight',
      oldValue: oldWeight,
      newValue: record.weightKg,
    );
    await dogRef.update({
      'weight': record.weightKg,
      'updatedAt': FieldValue.serverTimestamp(),
      'audit_trail': FieldValue.arrayUnion([dogEntry]),
    });

    return docRef.id;
  }

  /// Estatísticas de peso (min, max, média) no período.
  Future<Map<String, double>> getStats(
    String dogId, {
    DateTime? from,
    DateTime? to,
  }) async {
    final records = await getHistory(dogId, from: from, to: to);
    if (records.isEmpty) {
      return {'min': 0, 'max': 0, 'avg': 0};
    }

    final weights = records.map((r) => r.weightKg).toList();
    final min = weights.reduce((a, b) => a < b ? a : b);
    final max = weights.reduce((a, b) => a > b ? a : b);
    final avg = weights.reduce((a, b) => a + b) / weights.length;

    return {'min': min, 'max': max, 'avg': avg};
  }
}
