import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_commands.dart';
import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_errors.dart';

/// Resultado assíncrono tipado do gateway de Nutrição.
sealed class HealthNutritionMutationResult {
  const HealthNutritionMutationResult();
}

/// Sucesso MealLog (create real, replay ou semantic no-op).
final class CreateMealLogSuccess extends HealthNutritionMutationResult {
  const CreateMealLogSuccess({
    required this.dogId,
    required this.mealId,
    required this.revision,
    required this.wasNoOp,
    required this.operationId,
    this.mealOccurrenceId,
  });

  final String dogId;
  final String mealId;
  final int revision;
  final bool wasNoOp;
  final String operationId;

  /// Presente em planned; null em ad hoc.
  final String? mealOccurrenceId;
}

/// Sucesso SupplementLog.
final class CreateSupplementLogSuccess extends HealthNutritionMutationResult {
  const CreateSupplementLogSuccess({
    required this.dogId,
    required this.supplementLogId,
    required this.revision,
    required this.wasNoOp,
    required this.operationId,
  });

  final String dogId;
  final String supplementLogId;
  final int revision;
  final bool wasNoOp;
  final String operationId;
}

final class HealthNutritionMutationErrorResult
    extends HealthNutritionMutationResult {
  const HealthNutritionMutationErrorResult(this.failure);

  final HealthNutritionMutationFailure failure;
}

/// Porta de mutação canônica de Nutrição (somente creates Gate 3).
///
/// Produção: [FirebaseFunctionsHealthNutritionMutationGateway].
/// Testes: fake / [FailClosedHealthNutritionMutationGateway].
abstract interface class HealthNutritionMutationGateway {
  Future<HealthNutritionMutationResult> createPlannedMealLog(
    CreatePlannedMealLogCommand command,
  );

  Future<HealthNutritionMutationResult> createAdhocMealLog(
    CreateAdhocMealLogCommand command,
  );

  Future<HealthNutritionMutationResult> createSupplementLog(
    CreateSupplementLogCommand command,
  );
}

/// Fail-closed: sem escrita real até composition/testes explícitos.
final class FailClosedHealthNutritionMutationGateway
    implements HealthNutritionMutationGateway {
  const FailClosedHealthNutritionMutationGateway();

  @override
  Future<HealthNutritionMutationResult> createPlannedMealLog(
    CreatePlannedMealLogCommand command,
  ) async => const HealthNutritionMutationErrorResult(
    HealthNutritionMutationWritesNotEnabled(),
  );

  @override
  Future<HealthNutritionMutationResult> createAdhocMealLog(
    CreateAdhocMealLogCommand command,
  ) async => const HealthNutritionMutationErrorResult(
    HealthNutritionMutationWritesNotEnabled(),
  );

  @override
  Future<HealthNutritionMutationResult> createSupplementLog(
    CreateSupplementLogCommand command,
  ) async => const HealthNutritionMutationErrorResult(
    HealthNutritionMutationWritesNotEnabled(),
  );
}
