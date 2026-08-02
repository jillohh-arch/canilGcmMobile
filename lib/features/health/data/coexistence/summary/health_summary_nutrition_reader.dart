import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:canil_gcm/features/health/data/coexistence/nutrition/coexistence_nutrition_read_source.dart';
import 'package:canil_gcm/features/health/domain/nutrition_read_models.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_block_models.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_section_status.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_user_copy.dart';
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

/// Leitura de alimentação de hoje via leitor canônico de coexistência ou APIs read-only de [NutritionService].
///
/// Não escreve. Não inventa meta. Diferencia zero real de ausência.
class HealthSummaryNutritionReader {
  HealthSummaryNutritionReader({
    NutritionService? nutritionService,
    CoexistenceNutritionReadSource? coexistenceReadSource,
    Future<HealthSummaryNutritionDaySnapshot> Function(String dogId)?
    loadDaySnapshot,
    DateTime Function()? clock,
  }) : _coexistenceReadSource = coexistenceReadSource,
       _clock = clock ?? DateTime.now,
       _loadDaySnapshot =
           loadDaySnapshot ??
           ((dogId) => _loadViaService(
             nutritionService ?? NutritionService(),
             dogId,
             clock ?? DateTime.now,
           ));

  final CoexistenceNutritionReadSource? _coexistenceReadSource;
  final DateTime Function() _clock;
  final Future<HealthSummaryNutritionDaySnapshot> Function(String dogId)
  _loadDaySnapshot;

  Future<HealthSummarySectionData<HealthSummaryNutritionTodayView>> readToday(
    String dogId,
  ) async {
    try {
      if (_coexistenceReadSource != null) {
        return await _readViaCoexistence(dogId);
      }
      return await _readViaSnapshot(dogId);
    } on FirebaseException catch (e) {
      debugPrint(
        '[HealthSummaryNutritionReader] unavailable [${e.code}]: ${e.message}',
      );
      return HealthSummarySectionData.unavailable(
        message: e.code == 'unavailable'
            ? HealthSummaryUserCopy.networkUnavailable
            : HealthSummaryUserCopy.nutritionUnavailable,
      );
    } catch (e) {
      debugPrint('[HealthSummaryNutritionReader] unavailable: $e');
      return const HealthSummarySectionData.unavailable(
        message: HealthSummaryUserCopy.nutritionUnavailable,
      );
    }
  }

  Future<HealthSummarySectionData<HealthSummaryNutritionTodayView>>
  _readViaCoexistence(String dogId) async {
    final result = await _coexistenceReadSource!.loadToday(
      dogId,
      serverNow: _clock().toUtc(),
    );

    if ((result.isData || result.isDegraded) && result.value != null) {
      final today = result.value!;
      final activePlanRef = today.activePlan;
      final meals = today.mealsForDailyTotals;

      if (meals.isEmpty && activePlanRef == null) {
        return const HealthSummarySectionData.notRecorded(
          message: HealthSummaryUserCopy.nutritionNotRecorded,
        );
      }

      double? plannedGrams;
      int? plannedCount;

      if (activePlanRef is NutritionActiveCanonicalPlan) {
        final plan = activePlanRef.plan;
        plannedGrams = plan.amountGramsPerDay;
        plannedCount = plan.mealSchedule.isNotEmpty
            ? plan.mealSchedule.length
            : (plan.mealsPerDay > 0 ? plan.mealsPerDay : null);
      } else if (activePlanRef is NutritionActiveLegacyPlan) {
        final view = activePlanRef.view;
        plannedGrams = view.amountGramsPerDay;
        plannedCount = view.mealsPerDay > 0 ? view.mealsPerDay : null;
      }

      double? offeredTotal;
      double? consumedTotal;

      var anyOffered = false;
      var sumOffered = 0.0;
      var anyConsumed = false;
      var sumConsumed = 0.0;

      for (final item in meals) {
        final o = item.meal.offeredGrams;
        if (o.isFinite) {
          anyOffered = true;
          sumOffered += o;
        }
        final c = item.meal.consumedGrams;
        if (c != null && c.isFinite) {
          anyConsumed = true;
          sumConsumed += c;
        }
      }

      if (anyOffered) offeredTotal = sumOffered;
      if (anyConsumed) consumedTotal = sumConsumed;

      final plannedAmountDouble = plannedGrams?.toDouble();
      final plannedCompleted = today.plannedMealsCompleted;

      return HealthSummarySectionData.available(
        HealthSummaryNutritionTodayView(
          consumedAmount: consumedTotal,
          offeredAmount: offeredTotal,
          plannedAmount: plannedAmountDouble != null && plannedAmountDouble > 0
              ? plannedAmountDouble
              : null,
          mealsRecorded: plannedCompleted,
          mealsPlanned: plannedCount,
          unitLabel: 'g',
        ),
      );
    }

    return _readViaSnapshot(dogId);
  }

  Future<HealthSummarySectionData<HealthSummaryNutritionTodayView>>
  _readViaSnapshot(String dogId) async {
    final snap = await _loadDaySnapshot(dogId);
    final feedings = snap.feedings;
    final prescription = snap.prescription;

    final validFeedings = feedings
        .where((f) => f.amountGrams >= 0)
        .toList(growable: false);

    if (validFeedings.isEmpty && prescription == null) {
      return const HealthSummarySectionData.notRecorded(
        message: HealthSummaryUserCopy.nutritionNotRecorded,
      );
    }

    final consumed = validFeedings.fold<int>(
      0,
      (total, feeding) => total + feeding.amountGrams,
    );
    final planned = prescription?.amountGramsPerDay;
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
