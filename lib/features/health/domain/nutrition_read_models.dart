import 'health_v1_models.dart';
import 'legacy_nutrition_views.dart';
import 'meal_occurrence.dart';
import 'meal_schedule_slot.dart';
import 'nutrition_plan.dart';
import 'nutrition_read_state.dart';
import 'supplement_log.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Read models de Nutrição (§26–§27 / D28 / D30 / D36).
// Sem create/save/update. Sem misturar regimen × administration.
// ─────────────────────────────────────────────────────────────────────────────

/// Resolução do plano “ativo” no read model (D3).
///
/// - none → `null` no snapshot
/// - one canonical / one legacy fallback
/// - **conflict** quando >1 `NutritionPlan` com `status=active` (não mascarar)
sealed class NutritionActivePlanRef {
  const NutritionActivePlanRef();
}

final class NutritionActiveCanonicalPlan extends NutritionActivePlanRef {
  const NutritionActiveCanonicalPlan(this.plan);
  final NutritionPlan plan;

  NutritionDataOrigin get origin => NutritionDataOrigin.canonical;
}

final class NutritionActiveLegacyPlan extends NutritionActivePlanRef {
  const NutritionActiveLegacyPlan(this.view);
  final LegacyNutritionPlanView view;

  NutritionDataOrigin get origin => NutritionDataOrigin.legacy;

  /// Nunca se apresenta como NutritionPlan canônico.
  bool get isCanonical => false;
  bool get mealScheduleUnavailable => view.mealScheduleUnavailable;
}

/// Violação D3 detectada na leitura: >1 plano canônico `active` para o cão.
///
/// **Não** escolhe “mais recente” / maior revision / primeiro.
/// A UI futura deve tratar como integridade, não como plano único.
final class NutritionActivePlanIntegrityConflict
    extends NutritionActivePlanRef {
  NutritionActivePlanIntegrityConflict(List<NutritionPlan> activePlans)
    : activePlans = List.unmodifiable(activePlans) {
    if (this.activePlans.length < 2) {
      throw ArgumentError(
        'NutritionActivePlanIntegrityConflict exige >= 2 planos active',
      );
    }
  }

  final List<NutritionPlan> activePlans;

  String get code => 'multiple_active_nutrition_plans';

  int get activeCount => activePlans.length;

  List<String> get activePlanIds =>
      activePlans.map((p) => p.id).toList(growable: false);
}

/// Item de refeição unificado após merge.
final class NutritionMealReadItem {
  const NutritionMealReadItem({
    required this.meal,
    required this.origin,
    required this.mergeKey,
    this.collectionKey,
  });

  final MealLog meal;
  final NutritionDataOrigin origin;
  final String mergeKey;

  /// Collection legada quando aplicável (`feeding_events` / `feedings`).
  final String? collectionKey;

  DateTime get fedAt => meal.fedAt;
  String get id => meal.id;
}

/// Snapshot de coexistência tipado (§27).
final class NutritionCoexistenceSnapshot {
  const NutritionCoexistenceSnapshot({
    required this.dogId,
    required this.canonicalPlans,
    required this.legacyPlans,
    required this.canonicalMeals,
    required this.legacyMeals,
    required this.canonicalSupplementLogs,
    required this.legacySupplementRegimens,
    required this.planSources,
    required this.mealSources,
    required this.mergedMeals,
    required this.activePlan,
    this.mergeDiagnostics = const [],
  });

  final String dogId;
  final List<NutritionPlan> canonicalPlans;
  final List<LegacyNutritionPlanView> legacyPlans;
  final List<MealLog> canonicalMeals;
  final List<MealLog> legacyMeals;

  /// Administrações canônicas — **lista separada** do regime legado.
  final List<SupplementLog> canonicalSupplementLogs;

  /// Regime legado em uso — **nunca** misturado com SupplementLog.
  final List<LegacySupplementRegimenView> legacySupplementRegimens;

  final List<NutritionSourceStatus> planSources;
  final List<NutritionSourceStatus> mealSources;
  final List<NutritionMealReadItem> mergedMeals;
  final NutritionActivePlanRef? activePlan;
  final List<NutritionMergeDiagnostic> mergeDiagnostics;

  bool get hasPlanSourceFailure => planSources.any((s) => s.isFailure);
  bool get hasMealSourceFailure => mealSources.any((s) => s.isFailure);
  bool get isPartiallyFailed => hasPlanSourceFailure || hasMealSourceFailure;
}

/// Visão de "hoje" (foundation — sem UI).
final class NutritionTodayReadModel {
  const NutritionTodayReadModel({
    required this.dogId,
    required this.localServiceDate,
    required this.timezone,
    this.activePlan,
    this.meals = const [],
    this.canonicalSupplementLogs = const [],
    this.legacySupplementRegimens = const [],
  });

  final String dogId;
  final String localServiceDate;
  final String timezone;
  final NutritionActivePlanRef? activePlan;
  final List<NutritionMealReadItem> meals;
  final List<SupplementLog> canonicalSupplementLogs;
  final List<LegacySupplementRegimenView> legacySupplementRegimens;

  int get mealsRecorded => meals.length;

  /// Logs elegíveis para totais diários, sem somar ocorrências ambíguas.
  ///
  /// Os registros continuam preservados em [meals] para histórico/diagnóstico.
  List<NutritionMealReadItem> get mealsForDailyTotals {
    final occurrenceCounts = <String, int>{};
    for (final item in meals) {
      final occurrenceId = item.meal.mealOccurrenceId;
      if (item.origin == NutritionDataOrigin.canonical &&
          item.meal.isPlanned &&
          occurrenceId != null) {
        occurrenceCounts.update(
          occurrenceId,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
    }
    return [
      for (final item in meals)
        if (!_belongsToDuplicateCanonicalOccurrence(item, occurrenceCounts))
          item,
    ];
  }

  /// Slots concluídos por vínculo canônico completo da ocorrência atual.
  ///
  /// Refeições avulsas, legadas, de outro plano/data ou com ocorrência
  /// incompatível não entram no contador. Duplicidade fica fail-closed.
  int get plannedMealsCompleted => plannedSlotViews
      .where((view) => view.status == NutritionSlotDayStatus.completed)
      .length;

  List<NutritionSlotDayView> get plannedSlotViews {
    final p = activePlan;
    if (p is! NutritionActiveCanonicalPlan) return const [];
    return NutritionSlotDayDerivation.derive(
      plan: p.plan,
      mealsForDay: meals,
      localServiceDate: LocalServiceDate.fromIso(localServiceDate),
    );
  }

  int? get mealsPlanned {
    final p = activePlan;
    return switch (p) {
      NutritionActiveCanonicalPlan(:final plan) => plan.mealsPerDay,
      NutritionActiveLegacyPlan(:final view) => view.mealsPerDay,
      NutritionActivePlanIntegrityConflict() => null,
      null => null,
    };
  }

  double? get plannedGramsPerDay {
    final p = activePlan;
    return switch (p) {
      NutritionActiveCanonicalPlan(:final plan) => plan.amountGramsPerDay,
      NutritionActiveLegacyPlan(:final view) => view.amountGramsPerDay,
      NutritionActivePlanIntegrityConflict() => null,
      null => null,
    };
  }

  List<MealScheduleSlot> get schedule {
    final p = activePlan;
    return switch (p) {
      NutritionActiveCanonicalPlan(:final plan) => plan.mealSchedule,
      NutritionActiveLegacyPlan() => const [],
      NutritionActivePlanIntegrityConflict() => const [],
      null => const [],
    };
  }

  bool get hasActivePlanIntegrityConflict =>
      activePlan is NutritionActivePlanIntegrityConflict;

  static bool _belongsToDuplicateCanonicalOccurrence(
    NutritionMealReadItem item,
    Map<String, int> occurrenceCounts,
  ) {
    final occurrenceId = item.meal.mealOccurrenceId;
    return item.origin == NutritionDataOrigin.canonical &&
        item.meal.isPlanned &&
        occurrenceId != null &&
        (occurrenceCounts[occurrenceId] ?? 0) > 1;
  }
}

/// Slot do dia com status derivado (D11) — read-only.
enum NutritionSlotDayStatus { pending, completed }

final class NutritionSlotDayView {
  const NutritionSlotDayView({
    required this.slot,
    required this.status,
    this.meal,
    this.hasOccurrenceConflict = false,
  });

  final MealScheduleSlot slot;
  final NutritionSlotDayStatus status;
  final NutritionMealReadItem? meal;

  /// Mais de um MealLog canônico reivindica a mesma ocorrência esperada.
  ///
  /// Nenhum vencedor é escolhido e um novo registro deve permanecer bloqueado.
  final bool hasOccurrenceConflict;
}

abstract final class NutritionSlotDayDerivation {
  NutritionSlotDayDerivation._();

  static List<NutritionSlotDayView> derive({
    required NutritionPlan plan,
    required Iterable<NutritionMealReadItem> mealsForDay,
    required LocalServiceDate localServiceDate,
  }) {
    return [
      for (final slot in plan.mealSchedule)
        _deriveSlot(
          plan: plan,
          slot: slot,
          mealsForDay: mealsForDay,
          localServiceDate: localServiceDate,
        ),
    ];
  }

  static NutritionSlotDayView _deriveSlot({
    required NutritionPlan plan,
    required MealScheduleSlot slot,
    required Iterable<NutritionMealReadItem> mealsForDay,
    required LocalServiceDate localServiceDate,
  }) {
    final expectedOccurrence = MealOccurrenceId.v1(
      MealOccurrenceKey(
        dogId: plan.dogId,
        planId: plan.id,
        plannedMealId: slot.id,
        localServiceDate: localServiceDate,
      ),
    ).value;

    final matches = <NutritionMealReadItem>[];
    for (final item in mealsForDay) {
      final meal = item.meal;
      if (item.origin != NutritionDataOrigin.canonical || !meal.isPlanned) {
        continue;
      }
      if (meal.dogId != plan.dogId ||
          meal.planId != plan.id ||
          meal.plannedMealId != slot.id ||
          meal.mealOccurrenceId != expectedOccurrence) {
        continue;
      }
      final mealServiceDate = LocalServiceDate.fromInstant(
        meal.fedAt,
        timezone: plan.timezone,
      );
      if (mealServiceDate != localServiceDate) continue;
      matches.add(item);
    }

    if (matches.length == 1) {
      return NutritionSlotDayView(
        slot: slot,
        status: NutritionSlotDayStatus.completed,
        meal: matches.single,
      );
    }
    return NutritionSlotDayView(
      slot: slot,
      status: NutritionSlotDayStatus.pending,
      hasOccurrenceConflict: matches.length > 1,
    );
  }
}
