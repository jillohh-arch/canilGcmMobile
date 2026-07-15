import 'health_v1_models.dart';
import 'health_v1_value_objects.dart';

// ─────────────────────────────────────────────────────────────────────────────
// NutritionPlan — plano alimentar vigente (Domain Model §2.7).
// ─────────────────────────────────────────────────────────────────────────────

enum NutritionPlanStatus {
  active,
  superseded,
  cancelled;

  String get wireName => switch (this) {
    NutritionPlanStatus.active => 'active',
    NutritionPlanStatus.superseded => 'superseded',
    NutritionPlanStatus.cancelled => 'cancelled',
  };
}

final class NutritionPlan {
  NutritionPlan({
    required this.id,
    required this.dogId,
    required this.foodType,
    required num amountGramsPerDay,
    required this.mealsPerDay,
    required this.vigentFrom,
    required this.recordedBy,
    required this.status,
    required this.schemaVersion,
    this.vigentUntil,
    double? hydrationMl,
    String? specialInstructions,
    this.professional,
    this.sourceDocument,
    List<String>? attachmentRefs,
    List<String>? supplementIds,
  }) : amountGramsPerDay = amountGramsPerDay.toDouble(),
       hydrationMl = hydrationMl,
       specialInstructions = specialInstructions?.trim(),
       attachmentRefs = List.unmodifiable(
         List<String>.of(attachmentRefs ?? const []),
       ),
       supplementIds = List.unmodifiable(
         List<String>.of(supplementIds ?? const []),
       ) {
    if (schemaVersion <= 0) {
      throw const HealthDomainException(
        'invalid_schema_version',
        'schema_version deve ser positivo',
      );
    }
    if (!amountGramsPerDay.isFinite || amountGramsPerDay <= 0) {
      throw const HealthDomainException(
        'invalid_amount',
        'amount_grams_per_day deve ser finito e maior que zero',
      );
    }
    if (mealsPerDay <= 0) {
      throw const HealthDomainException(
        'invalid_meals_per_day',
        'meals_per_day deve ser positivo',
      );
    }
    final hm = hydrationMl;
    if (hm != null && hm < 0) {
      throw const HealthDomainException(
        'invalid_hydration',
        'hydration_ml não pode ser negativo',
      );
    }
    final vu = vigentUntil;
    if (vu != null && vu.isBefore(vigentFrom)) {
      throw const HealthDomainException(
        'inconsistent_validity',
        'vigent_until não pode ser anterior a vigent_from',
      );
    }
  }

  final String id;
  final String dogId;
  final String foodType;
  final double amountGramsPerDay;
  final int mealsPerDay;
  final DateTime vigentFrom;
  final DateTime? vigentUntil;
  final double? hydrationMl;
  final String? specialInstructions;
  final ProfessionalIdentity? professional;
  final HealthDocumentRef? sourceDocument;
  final List<String> attachmentRefs;
  final List<String> supplementIds;
  final RecordedBy recordedBy;
  final NutritionPlanStatus status;
  final int schemaVersion;

  /// Quantidade por refeição (valor derivado — Domain Model §2.7).
  double get amountPerMeal => amountGramsPerDay / mealsPerDay;
}

/// Política pura de coexistência de planos.
final class NutritionPlanConflictPolicy {
  const NutritionPlanConflictPolicy();

  /// Retorna lista vazia quando não há conflitos.
  /// Conflito: mais de um `NutritionPlanStatus.active` para o mesmo K9.
  List<String> evaluate(Iterable<NutritionPlan> plans) {
    final activeByDog = <String, int>{};
    for (final plan in plans) {
      if (plan.status == NutritionPlanStatus.active) {
        activeByDog[plan.dogId] = (activeByDog[plan.dogId] ?? 0) + 1;
      }
    }
    final conflicts = <String>[];
    activeByDog.forEach((dogId, count) {
      if (count > 1) {
        conflicts.add('dog=$dogId activeCount=$count');
      }
    });
    return List.unmodifiable(conflicts);
  }
}
