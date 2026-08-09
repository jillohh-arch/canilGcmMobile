import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:canil_gcm/features/dogs/domain/weight_record.dart';
import 'package:canil_gcm/features/health/data/weight/weight_assessment_read_adapter.dart';
import 'package:canil_gcm/features/health/domain/weight_collection_policy.dart';

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

  /// Peso atual canônico (WEIGHT-01E-C1).
  ///
  /// Aplica [analyzeWeightCollection] sobre a coleção completa, e não
  /// `orderBy(...).limit(1)`: com `limit(1)` um `malformed`/`unsupported` em
  /// outra posição ficaria invisível, um `invalidated` mais recente impediria
  /// o fallback para o válido anterior e o desempate não seria controlado.
  ///
  /// - bloqueador global (`malformed`/`unsupported`/`entityId` duplicado) →
  ///   [WeightHistoryReadException], sem promover registro anterior;
  /// - `invalidated` mais recente → válido anterior pode ser o atual;
  /// - vazio ou somente `invalidated` → `null`.
  Future<WeightRecord?> getLatest(String dogId) async {
    final snapshot = await _collection(dogId).get();

    final candidates = <WeightCandidate>[];
    final facades = <String, WeightRecord>{};
    for (final doc in snapshot.docs) {
      final result = WeightAssessmentReadAdapter.read(
        documentId: doc.id,
        dogId: dogId,
        data: doc.data(),
      );
      final record = result.record;
      if (record != null) facades[doc.id] = record;
      candidates.add(
        WeightCandidate(
          entityId: doc.id,
          kind: switch (result.kind) {
            WeightReadKind.valid => WeightCandidateKind.valid,
            WeightReadKind.invalidated => WeightCandidateKind.invalidated,
            WeightReadKind.malformed => WeightCandidateKind.malformed,
            WeightReadKind.unsupported => WeightCandidateKind.unsupported,
          },
          assessment: result.assessment,
        ),
      );
    }

    final analysis = analyzeWeightCollection(candidates);
    switch (analysis.kind) {
      case WeightCurrentKind.inconclusive:
        throw WeightHistoryReadException(_blockerReason(analysis.blockers));
      case WeightCurrentKind.none:
        return null;
      case WeightCurrentKind.current:
        // `entityId` é único aqui: duplicidade já teria sido bloqueada acima.
        return facades[analysis.current!.entityId];
    }
  }

  /// Código estável do bloqueio, preservando os motivos históricos.
  static String _blockerReason(List<WeightCurrentBlocker> blockers) {
    if (blockers.contains(WeightCurrentBlocker.malformed)) {
      return 'malformed_weight_record';
    }
    if (blockers.contains(WeightCurrentBlocker.unsupported)) {
      return 'unsupported_weight_schema';
    }
    return 'duplicate_weight_entity_id';
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
