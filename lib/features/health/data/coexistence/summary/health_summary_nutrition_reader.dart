import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:canil_gcm/features/health/presentation/summary/health_summary_block_models.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_section_status.dart';
import 'package:canil_gcm/features/nutrition/data/nutrition_service.dart';
import 'package:canil_gcm/features/nutrition/domain/feeding.dart';
import 'package:canil_gcm/features/nutrition/domain/nutrition_prescription.dart';

/// Snapshot diário de nutrição (fatos, sem refeições individuais no contrato 2B).
final class HealthSummaryNutritionDaySnapshot {
  const HealthSummaryNutritionDaySnapshot({
    required this.feedings,
    this.prescription,
  });

  final List<Feeding> feedings;
  final NutritionPrescription? prescription;
}

/// Leitura de alimentação de hoje via APIs read-only de [NutritionService].
///
/// Não escreve. Não inventa meta. Diferencia zero real de ausência.
class HealthSummaryNutritionReader {
  HealthSummaryNutritionReader({
    NutritionService? nutritionService,
    Future<HealthSummaryNutritionDaySnapshot> Function(String dogId)?
    loadDaySnapshot,
    DateTime Function()? clock,
  }) : _loadDaySnapshot =
           loadDaySnapshot ??
           ((dogId) => _loadViaService(
             nutritionService ?? NutritionService(),
             dogId,
             clock ?? DateTime.now,
           ));

  final Future<HealthSummaryNutritionDaySnapshot> Function(String dogId)
  _loadDaySnapshot;

  Future<HealthSummarySectionData<HealthSummaryNutritionTodayView>> readToday(
    String dogId,
  ) async {
    try {
      final snap = await _loadDaySnapshot(dogId);
      final feedings = snap.feedings;
      final prescription = snap.prescription;

      // Soma real; gramas negativos são ignorados (dado inválido).
      final validFeedings = feedings
          .where((f) => f.amountGrams >= 0)
          .toList(growable: false);

      if (validFeedings.isEmpty && prescription == null) {
        return const HealthSummarySectionData.notRecorded(
          message: 'Nenhum plano ou refeição registrada para hoje',
        );
      }

      // Lista vazia + prescrição ⇒ 0 g consumidos (zero legítimo).
      final consumed = validFeedings.fold<int>(
        0,
        (total, feeding) => total + feeding.amountGrams,
      );
      final planned = prescription?.amountGramsPerDay;
      // Meta inválida (≤0) não é exposta como plano real.
      final plannedSafe = (planned != null && planned > 0) ? planned : null;
      final mealsPlanned = prescription == null
          ? null
          : (prescription.mealsPerDay > 0 ? prescription.mealsPerDay : null);
      final mealsRecorded = validFeedings.length;

      return HealthSummarySectionData.available(
        HealthSummaryNutritionTodayView(
          consumedAmount: consumed.toDouble(),
          plannedAmount: plannedSafe?.toDouble(),
          mealsRecorded: mealsRecorded,
          mealsPlanned: mealsPlanned,
          unitLabel: 'g',
        ),
      );
    } on FirebaseException catch (e) {
      return HealthSummarySectionData.unavailable(
        message: e.message ?? 'Falha ao ler nutrição [${e.code}]',
      );
    } catch (e) {
      return HealthSummarySectionData.unavailable(
        message: 'Falha ao ler nutrição: $e',
      );
    }
  }

  static Future<HealthSummaryNutritionDaySnapshot> _loadViaService(
    NutritionService service,
    String dogId,
    DateTime Function() clock,
  ) async {
    final now = clock();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));
    final feedings = await service.getFeedings(dogId, from: start, to: end);
    final prescription = await service.getActivePrescription(dogId);
    return HealthSummaryNutritionDaySnapshot(
      feedings: feedings,
      prescription: prescription,
    );
  }
}
