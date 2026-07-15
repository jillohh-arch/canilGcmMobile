import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:canil_gcm/features/health/data/coexistence/summary/health_summary_nutrition_reader.dart';
import 'package:canil_gcm/features/health/data/coexistence/summary/health_summary_recent_records_reader.dart';
import 'package:canil_gcm/features/health/data/coexistence/summary/health_summary_unsafe_sections.dart';
import 'package:canil_gcm/features/health/data/coexistence/summary/health_summary_vaccination_reader.dart';
import 'package:canil_gcm/features/health/data/coexistence/summary/health_summary_weight_reader.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_block_models.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_section_status.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_source.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_source_metadata.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_view_data.dart';
import 'package:canil_gcm/features/nutrition/data/nutrition_service.dart';

/// Fonte concreta **read-only** de coexistência para o Resumo Health v1.
///
/// Agrega fontes legadas/transitórias atuais. **Não** é a projeção canônica
/// final (ADR-004). Pode ser substituída após migração/backfill.
///
/// - Sem writes
/// - Falhas parciais → `unavailable` no bloco
/// - Sem cálculo de readiness / score legado
class CoexistenceHealthSummarySource implements HealthSummarySource {
  CoexistenceHealthSummarySource({
    FirebaseFirestore? firestore,
    NutritionService? nutritionService,
    HealthSummaryWeightReader? weightReader,
    HealthSummaryVaccinationReader? vaccinationReader,
    HealthSummaryNutritionReader? nutritionReader,
    HealthSummaryRecentRecordsReader? recentRecordsReader,
  }) : _weightReader =
           weightReader ?? HealthSummaryWeightReader(firestore: firestore),
       _vaccinationReader =
           vaccinationReader ??
           HealthSummaryVaccinationReader(firestore: firestore),
       _nutritionReader =
           nutritionReader ??
           HealthSummaryNutritionReader(nutritionService: nutritionService),
       _recentRecordsReader =
           recentRecordsReader ??
           HealthSummaryRecentRecordsReader(firestore: firestore);

  final HealthSummaryWeightReader _weightReader;
  final HealthSummaryVaccinationReader _vaccinationReader;
  final HealthSummaryNutritionReader _nutritionReader;
  final HealthSummaryRecentRecordsReader _recentRecordsReader;

  @override
  Stream<HealthSummaryViewData?> watchSummary(String dogId) {
    final normalized = dogId.trim();
    if (normalized.isEmpty) {
      return Stream.error(
        ArgumentError.value(dogId, 'dogId', 'dogId não pode ser vazio'),
      );
    }

    // One-shot stream: controller 2B reconecta via refresh/selectDog.
    // 2E pode evoluir para push contínuo com streams de peso/nutrição.
    return Stream.fromFuture(_loadOnce(normalized));
  }

  Future<HealthSummaryViewData?> _loadOnce(String dogId) async {
    try {
      // Paraleliza leitores independentes; falha parcial não cancela os outros
      // porque cada reader captura erros em SectionData.unavailable.
      // Peso atual + tendência: uma única query (readBundle).
      final weightBundleFuture = _weightReader.readBundle(dogId);
      final vaccinationFuture = _vaccinationReader.read(dogId);
      final nutritionFuture = _nutritionReader.readToday(dogId);
      final recentFuture = _recentRecordsReader.read(dogId);

      final weightBundle = await weightBundleFuture;
      final weight = weightBundle.current;
      final trend = weightBundle.trend;
      final vaccination = await vaccinationFuture;
      final nutrition = await nutritionFuture;
      final recent = await recentFuture;

      // Falha estrutural: todos os blocos *mapeáveis* falharam.
      // Não apresentar dashboard "válido" com 0 fatos e 8 cards unavailable.
      // (readiness/treatments/attention já são unavailable por decisão UNSAFE.)
      if (_allMappableUnavailable(
        weight: weight,
        vaccination: vaccination,
        nutrition: nutrition,
        recent: recent,
      )) {
        final offline = _looksOffline([
          weight.message,
          vaccination.message,
          nutrition.message,
          recent.message,
        ]);
        throw HealthSummarySourceException(
          'Não foi possível carregar o resumo: todas as fontes mapeáveis falharam',
          isOffline: offline,
        );
      }

      return HealthSummaryViewData(
        dogId: dogId,
        readiness: HealthSummaryUnsafeSections.readiness,
        weight: weight,
        vaccination: vaccination,
        treatments: HealthSummaryUnsafeSections.treatments,
        attention: HealthSummaryUnsafeSections.attention,
        nutritionToday: nutrition,
        weightTrend: trend,
        recentRecords: recent,
        metadata: HealthSummarySourceMetadata(
          updatedAt: _deriveUpdatedAt(
            weight: weight,
            trend: trend,
            recent: recent,
          ),
          // APIs legadas não expõem cache de forma confiável; false = "não
          // confirmado como cache", não "confirmado servidor".
          isFromCache: false,
          isOffline: false,
          isStale: false,
        ),
      );
    } on HealthSummarySourceException {
      rethrow;
    } on FirebaseException catch (e) {
      throw HealthSummarySourceException(
        e.message ?? 'Falha de leitura do resumo [${e.code}]',
        isOffline: e.code == 'unavailable',
      );
    }
  }

  /// weight / vaccination / nutrition / recent — blocos que a 2D tenta ler.
  static bool _allMappableUnavailable({
    required HealthSummarySectionData weight,
    required HealthSummarySectionData vaccination,
    required HealthSummarySectionData nutrition,
    required HealthSummarySectionData recent,
  }) {
    return weight.isUnavailable &&
        vaccination.isUnavailable &&
        nutrition.isUnavailable &&
        recent.isUnavailable;
  }

  static bool _looksOffline(List<String?> messages) {
    for (final m in messages) {
      if (m == null) continue;
      final lower = m.toLowerCase();
      if (lower.contains('unavailable') ||
          lower.contains('offline') ||
          lower.contains('network') ||
          lower.contains(
            'failed to get document because the client is offline',
          )) {
        return true;
      }
    }
    return false;
  }

  /// updatedAt = máximo das timestamps disponíveis; sem inventar.
  static DateTime? _deriveUpdatedAt({
    required HealthSummarySectionData<HealthSummaryWeightView> weight,
    required HealthSummarySectionData<HealthSummaryWeightTrendView> trend,
    required HealthSummarySectionData<HealthSummaryRecentRecordsView> recent,
  }) {
    final stamps = <DateTime>[];

    final w = weight.valueOrNull;
    if (w?.measuredAt != null) {
      stamps.add(w!.measuredAt!);
    }

    final t = trend.valueOrNull;
    if (t != null && t.points.isNotEmpty) {
      stamps.add(t.points.last.at);
    }

    final r = recent.valueOrNull;
    if (r != null) {
      for (final item in r.items) {
        if (item.occurredAt != null) stamps.add(item.occurredAt!);
      }
    }

    if (stamps.isEmpty) return null;
    stamps.sort();
    return stamps.last;
  }
}
