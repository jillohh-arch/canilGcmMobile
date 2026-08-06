import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:canil_gcm/features/dogs/domain/weight_record.dart';
import 'package:canil_gcm/features/health/data/weight/weight_assessment_read_adapter.dart';

/// Falha controlada de leitura de histórico quando um documento em
/// `weight_records` é ilegível (malformed) ou de schema não suportado
/// (unsupported). Carrega apenas códigos técnicos seguros — sem PHI, RA,
/// uid, nome, e-mail ou map documental bruto.
class WeightHistoryReadException implements Exception {
  const WeightHistoryReadException(this.reason);

  /// Código estável do bloqueio (`malformed_weight_record` /
  /// `unsupported_weight_schema`).
  final String reason;

  @override
  String toString() => 'WeightHistoryReadException($reason)';
}

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
          .map((snapshot) => _parseSnapshot(dogId, snapshot));
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
    return _parseSnapshot(dogId, await query.get());
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

  /// Adota o parser central preservando a semântica estrita do histórico:
  /// - `malformed`/`unsupported` → falha controlada do carregamento inteiro
  ///   (não inventa, não reclassifica, não vira histórico parcial silencioso);
  /// - `invalidated` → excluído da lista ordinária (sem hard delete);
  /// - `valid` → incluído, inclusive shapes legados reconhecidos sem `recorder`
  ///   (a pesagem permanece visível; `recordedBy` fica `null`, autoria não é
  ///   inventada). Consistente com summary, recentes e timeline.
  List<WeightRecord> _parseSnapshot(
    String dogId,
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final records = <WeightRecord>[];
    for (final doc in snapshot.docs) {
      final result = WeightAssessmentReadAdapter.read(
        documentId: doc.id,
        dogId: dogId,
        data: doc.data(),
      );
      switch (result.kind) {
        case WeightReadKind.malformed:
          throw const WeightHistoryReadException('malformed_weight_record');
        case WeightReadKind.unsupported:
          throw const WeightHistoryReadException('unsupported_weight_schema');
        case WeightReadKind.invalidated:
          continue;
        case WeightReadKind.valid:
          final record = result.record;
          if (record != null) records.add(record);
      }
    }
    return List.unmodifiable(records);
  }
}
