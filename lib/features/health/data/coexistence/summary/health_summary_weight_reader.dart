import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:canil_gcm/features/health/data/weight/weight_assessment_read_adapter.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_block_models.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_section_status.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_user_copy.dart';

/// Amostra mínima de peso para mapeamento (sem model legado na fronteira).
final class HealthSummaryWeightSample {
  const HealthSummaryWeightSample({
    required this.weightKg,
    required this.measuredAt,
  });

  final double weightKg;
  final DateTime measuredAt;
}

/// Leitura read-only de peso a partir de `dogs/{dogId}/weight_records`.
///
/// Autoridade canônica de peso no mobile atual (ADR-006 / WeightHistoryService).
/// Não mescla `weight_history` silenciosamente.
/// Não escreve.
class HealthSummaryWeightReader {
  HealthSummaryWeightReader({
    FirebaseFirestore? firestore,
    Future<List<HealthSummaryWeightSample>> Function(String dogId)? loadSamples,
  }) : _loadSamples =
           loadSamples ??
           ((dogId) => _loadFromFirestore(
             firestore ?? FirebaseFirestore.instance,
             dogId,
           ));

  final Future<List<HealthSummaryWeightSample>> Function(String dogId)
  _loadSamples;

  static const int trendLimit = 30;

  Future<HealthSummarySectionData<HealthSummaryWeightView>> readCurrent(
    String dogId,
  ) async {
    final bundle = await readBundle(dogId);
    return bundle.current;
  }

  Future<HealthSummarySectionData<HealthSummaryWeightTrendView>> readTrend(
    String dogId,
  ) async {
    final bundle = await readBundle(dogId);
    return bundle.trend;
  }

  /// Uma única leitura de `weight_records` → atual + tendência.
  Future<
    ({
      HealthSummarySectionData<HealthSummaryWeightView> current,
      HealthSummarySectionData<HealthSummaryWeightTrendView> trend,
    })
  >
  readBundle(String dogId) async {
    try {
      final samples = await _loadSamples(dogId);
      final valid = _validSorted(samples);
      if (valid.isEmpty) {
        return (
          current:
              const HealthSummarySectionData<
                HealthSummaryWeightView
              >.notRecorded(message: HealthSummaryUserCopy.weightNotRecorded),
          trend:
              const HealthSummarySectionData<
                HealthSummaryWeightTrendView
              >.notRecorded(message: HealthSummaryUserCopy.weightNotRecorded),
        );
      }
      final latest = valid.last;
      final points = valid
          .map(
            (s) => HealthSummaryWeightPoint(
              at: s.measuredAt,
              weightKg: s.weightKg,
            ),
          )
          .toList(growable: false);
      return (
        current: HealthSummarySectionData.available(
          HealthSummaryWeightView(
            weightKg: latest.weightKg,
            measuredAt: latest.measuredAt,
          ),
        ),
        // Meta/BCS não inventados — exigem fonte estruturada própria.
        trend: HealthSummarySectionData.available(
          HealthSummaryWeightTrendView(points: points),
        ),
      );
    } on FirebaseException catch (e) {
      debugPrint(
        '[HealthSummaryWeightReader] unavailable [${e.code}]: ${e.message}',
      );
      final msg = e.code == 'unavailable'
          ? HealthSummaryUserCopy.networkUnavailable
          : HealthSummaryUserCopy.weightUnavailable;
      return (
        current: HealthSummarySectionData<HealthSummaryWeightView>.unavailable(
          message: msg,
        ),
        trend:
            HealthSummarySectionData<HealthSummaryWeightTrendView>.unavailable(
              message: msg,
            ),
      );
    } catch (e) {
      debugPrint('[HealthSummaryWeightReader] unavailable: $e');
      return (
        current:
            const HealthSummarySectionData<HealthSummaryWeightView>.unavailable(
              message: HealthSummaryUserCopy.weightUnavailable,
            ),
        trend:
            const HealthSummarySectionData<
              HealthSummaryWeightTrendView
            >.unavailable(message: HealthSummaryUserCopy.weightUnavailable),
      );
    }
  }

  /// Ordena ascendente e descarta pesos não finitos / não positivos.
  static List<HealthSummaryWeightSample> _validSorted(
    List<HealthSummaryWeightSample> raw,
  ) {
    final list = raw
        .where((s) => s.weightKg.isFinite && s.weightKg > 0)
        .toList(growable: true);
    list.sort((a, b) => a.measuredAt.compareTo(b.measuredAt));
    return list;
  }

  /// Leitura DESC adotando o parser central.
  ///
  /// Política de peso atual (ADR-008 §11.1), aplicada na ordem retornada:
  /// - `valid` → candidato (o summary não carrega autoria, então shapes
  ///   legados sem `recorder` também contam);
  /// - `invalidated` → ignorado como candidato (não bloqueia);
  /// - `malformed`/`unsupported` **antes** do primeiro candidato válido →
  ///   erro controlado (inconclusivo), sem promover registro anterior;
  /// - `malformed`/`unsupported` **depois** de um candidato válido → ignorado
  ///   (não invalida o candidato mais recente).
  static Future<List<HealthSummaryWeightSample>> _loadFromFirestore(
    FirebaseFirestore firestore,
    String dogId,
  ) async {
    final snap = await firestore
        .collection('dogs')
        .doc(dogId)
        .collection('weight_records')
        .orderBy('measured_at', descending: true)
        .limit(trendLimit)
        .get();

    final samples = <HealthSummaryWeightSample>[];
    var seenValid = false;
    for (final doc in snap.docs) {
      final result = WeightAssessmentReadAdapter.read(
        documentId: doc.id,
        dogId: dogId,
        data: doc.data(),
      );
      switch (result.kind) {
        case WeightReadKind.valid:
          final assessment = result.assessment!;
          seenValid = true;
          samples.add(
            HealthSummaryWeightSample(
              weightKg: assessment.weightKg,
              measuredAt: assessment.measuredAt,
            ),
          );
        case WeightReadKind.invalidated:
          continue;
        case WeightReadKind.malformed:
        case WeightReadKind.unsupported:
          if (!seenValid) {
            throw StateError('weight_summary_inconclusive_${result.kind.name}');
          }
          continue;
      }
    }
    return samples;
  }
}
