import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_errors.dart';
import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_gateway.dart';

/// Resultado de apresentação de uma mutação de Nutrição (Gate 3).
sealed class HealthNutritionMutationUiOutcome {
  const HealthNutritionMutationUiOutcome();
}

/// Mutação remota OK. [refreshFailed] separa falha de callback pós-sucesso.
///
/// [wasNoOp] = true continua sendo **sucesso** (replay / semantic no-op).
final class HealthNutritionMutationUiSuccess
    extends HealthNutritionMutationUiOutcome {
  const HealthNutritionMutationUiSuccess({
    required this.successMessage,
    required this.refreshFailed,
    required this.dogId,
    required this.entityId,
    required this.revision,
    required this.wasNoOp,
    required this.entityKind,
    this.mealOccurrenceId,
    this.refreshWarning,
  });

  factory HealthNutritionMutationUiSuccess.fromMeal({
    required CreateMealLogSuccess remote,
    required bool refreshFailed,
    String? refreshWarning,
  }) {
    return HealthNutritionMutationUiSuccess(
      successMessage: 'Registro salvo com sucesso',
      refreshFailed: refreshFailed,
      dogId: remote.dogId,
      entityId: remote.mealId,
      revision: remote.revision,
      wasNoOp: remote.wasNoOp,
      entityKind: HealthNutritionMutationEntityKind.mealLog,
      mealOccurrenceId: remote.mealOccurrenceId,
      refreshWarning: refreshWarning,
    );
  }

  factory HealthNutritionMutationUiSuccess.fromSupplement({
    required CreateSupplementLogSuccess remote,
    required bool refreshFailed,
    String? refreshWarning,
  }) {
    return HealthNutritionMutationUiSuccess(
      successMessage: 'Registro salvo com sucesso',
      refreshFailed: refreshFailed,
      dogId: remote.dogId,
      entityId: remote.supplementLogId,
      revision: remote.revision,
      wasNoOp: remote.wasNoOp,
      entityKind: HealthNutritionMutationEntityKind.supplementLog,
      refreshWarning: refreshWarning,
    );
  }

  final String successMessage;
  final bool refreshFailed;
  final String? refreshWarning;
  final String dogId;
  final String entityId;
  final int revision;
  final bool wasNoOp;
  final HealthNutritionMutationEntityKind entityKind;
  final String? mealOccurrenceId;

  /// Alias de legibilidade do contrato Gate 3.
  bool get savedAndRefreshed => !refreshFailed;
  bool get savedButRefreshFailed => refreshFailed;
}

enum HealthNutritionMutationEntityKind { mealLog, supplementLog }

final class HealthNutritionMutationUiFailure
    extends HealthNutritionMutationUiOutcome {
  const HealthNutritionMutationUiFailure({
    required this.failure,
    required this.userMessage,
  });

  final HealthNutritionMutationFailure failure;
  final String userMessage;
}

/// Segunda submissão bloqueada (double tap).
final class HealthNutritionMutationUiBlocked
    extends HealthNutritionMutationUiOutcome {
  const HealthNutritionMutationUiBlocked();
}
