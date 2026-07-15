import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:canil_gcm/features/health/data/coexistence/summary/health_summary_date_parse.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_block_models.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_section_status.dart';

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
              >.notRecorded(message: 'Nenhuma pesagem registrada'),
          trend:
              const HealthSummarySectionData<
                HealthSummaryWeightTrendView
              >.notRecorded(message: 'Sem histórico de peso'),
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
      final msg = e.message ?? 'Falha ao ler peso [${e.code}]';
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
      final msg = 'Falha ao ler peso: $e';
      return (
        current: HealthSummarySectionData<HealthSummaryWeightView>.unavailable(
          message: msg,
        ),
        trend:
            HealthSummarySectionData<HealthSummaryWeightTrendView>.unavailable(
              message: msg,
            ),
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
    for (final doc in snap.docs) {
      final data = doc.data();
      final kgRaw = data['weight_kg'];
      final kg = kgRaw is num ? kgRaw.toDouble() : null;
      final at = HealthSummaryDateParse.tryParse(data['measured_at']);
      if (kg == null || at == null) continue;
      samples.add(HealthSummaryWeightSample(weightKg: kg, measuredAt: at));
    }
    return samples;
  }
}
