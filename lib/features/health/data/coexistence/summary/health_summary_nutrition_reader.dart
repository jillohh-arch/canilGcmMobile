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

/// Leitura de alimentação de hoje via leitor canônico de coexistência.
///
/// O contrato legado permanece aceito no construtor durante a transição,
/// mas sem uma projeção normativa ele falha fechado e não publica "hoje".
class HealthSummaryNutritionReader {
  HealthSummaryNutritionReader({
    NutritionService? nutritionService,
    CoexistenceNutritionReadSource? coexistenceReadSource,
    Future<HealthSummaryNutritionDaySnapshot> Function(String dogId)?
    loadDaySnapshot,
    DateTime Function()? clock,
  }) : _coexistenceReadSource = coexistenceReadSource,
       _clock = clock ?? DateTime.now;

  final CoexistenceNutritionReadSource? _coexistenceReadSource;
  final DateTime Function() _clock;

  Future<HealthSummarySectionData<HealthSummaryNutritionTodayView>> readToday(
    String dogId,
  ) async {
    try {
      if (_coexistenceReadSource != null) {
        return await _readViaCoexistence(dogId);
      }
      return await _readViaSnapshot();
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

      final view = HealthSummaryNutritionTodayView(
        consumedAmount: consumedTotal,
        offeredAmount: offeredTotal,
        plannedAmount: plannedAmountDouble != null && plannedAmountDouble > 0
            ? plannedAmountDouble
            : null,
        mealsRecorded: plannedCompleted,
        mealsPlanned: plannedCount,
        unitLabel: 'g',
      );
      if (result.isDegraded) {
        return HealthSummarySectionData.degraded(
          view,
          message:
              result.message ?? 'Dados de nutrição parcialmente disponíveis.',
        );
      }
      return HealthSummarySectionData.available(view);
    }

    if (result.isEmpty) {
      return const HealthSummarySectionData.notRecorded(
        message: HealthSummaryUserCopy.nutritionNotRecorded,
      );
    }

    return const HealthSummarySectionData.unavailable(
      message: HealthSummaryUserCopy.nutritionUnavailable,
    );
  }

  Future<HealthSummarySectionData<HealthSummaryNutritionTodayView>>
  _readViaSnapshot() async {
    // O snapshot legado não possui contexto normativo suficiente para ser
    // convertido em "hoje" sem reconstruir filtros/contadores paralelos.
    // Fail-closed: somente o caminho coexistente com loadToday pode publicar
    // dados diários.
    return const HealthSummarySectionData.unavailable(
      message: HealthSummaryUserCopy.nutritionUnavailable,
    );
  }
}
