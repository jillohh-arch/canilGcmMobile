import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';

/// Intenção de mutação de Nutrição transportável fora do lifecycle do controller.
///
/// [HealthNutritionMutationController.dispose] é lifecycle **técnico** e NÃO
/// descarta esta intenção. Somente [HealthNutritionMutationController.discardIntent]
/// (ou sucesso confirmado) encerra semanticamente a intenção.
enum HealthNutritionMutationKind { plannedMeal, adhocMeal, supplement }

/// Snapshot mínimo para restaurar operationId após resultado incerto.
final class HealthNutritionPendingIntent {
  const HealthNutritionPendingIntent({
    required this.operationId,
    required this.intentFingerprint,
    required this.kind,
    this.plannedMealDraft,
  });

  final String operationId;
  final String intentFingerprint;
  final HealthNutritionMutationKind kind;
  final HealthNutritionPendingPlannedMealDraft? plannedMealDraft;

  HealthNutritionPendingIntent copyWith({
    String? operationId,
    String? intentFingerprint,
    HealthNutritionMutationKind? kind,
    HealthNutritionPendingPlannedMealDraft? plannedMealDraft,
  }) {
    return HealthNutritionPendingIntent(
      operationId: operationId ?? this.operationId,
      intentFingerprint: intentFingerprint ?? this.intentFingerprint,
      kind: kind ?? this.kind,
      plannedMealDraft: plannedMealDraft ?? this.plannedMealDraft,
    );
  }
}

/// Payload lógico suficiente para reconstruir exatamente uma tentativa planned.
///
/// É memória de sessão, não outbox persistente; não contém token nem campos de
/// autoridade do backend.
final class HealthNutritionPendingPlannedMealDraft {
  const HealthNutritionPendingPlannedMealDraft({
    required this.dogId,
    required this.planId,
    required this.plannedMealId,
    required this.offeredGrams,
    required this.acceptance,
    required this.fedAt,
    this.consumedGrams,
    this.observations,
  });

  final String dogId;
  final String planId;
  final String plannedMealId;
  final double offeredGrams;
  final double? consumedGrams;
  final ParsedHealthEnum<MealAcceptance> acceptance;
  final DateTime fedAt;
  final String? observations;
}

/// Holder mutável externo ao [ChangeNotifier] — sobrevive a dispose/recriação.
///
/// Composition root deve possuir uma instância por sessão de formulário /
/// entry e reutilizá-la ao reconstruir o controller.
final class HealthNutritionPendingIntentHolder {
  HealthNutritionPendingIntentHolder([this.value]);

  HealthNutritionPendingIntent? value;

  bool get hasPending => value != null && value!.operationId.trim().isNotEmpty;

  void clear() {
    value = null;
  }
}
