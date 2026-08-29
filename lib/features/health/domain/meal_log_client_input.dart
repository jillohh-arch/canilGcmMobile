import 'health_v1_enums.dart';
import 'health_v1_models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// D41 — Input de cliente vs campos server-derived (domain puro, ZERO transporte).
// Não é DTO de callable. Não permite fingir autoridade de campos derivados.
// ─────────────────────────────────────────────────────────────────────────────

/// Campos que o **cliente** pode fornecer para MealLog **planejado** (futuro).
///
/// Exclui deliberadamente: period, scheduledFor, prescriptionAmountAtTime,
/// mealOccurrenceId, recordedBy, recordedAt, revision, schemaVersion.
final class PlannedMealClientInput {
  PlannedMealClientInput({
    required String dogId,
    required String planId,
    required String plannedMealId,
    required num offeredGrams,
    required this.acceptance,
    required this.fedAt,
    num? consumedGrams,
    String? observations,
  }) : dogId = _require(dogId, 'dog_id'),
       planId = _require(planId, 'plan_id'),
       plannedMealId = _require(plannedMealId, 'planned_meal_id'),
       offeredGrams = offeredGrams.toDouble(),
       consumedGrams = consumedGrams?.toDouble(),
       observations = observations?.trim() {
    // Reutiliza invariantes D42 sem montar MealLog completo (sem server fields).
    MealLog.validateQuantityInvariantsPublic(
      offeredGrams: this.offeredGrams,
      consumedGrams: this.consumedGrams,
      acceptance: acceptance,
    );
  }

  final String dogId;
  final String planId;
  final String plannedMealId;
  final double offeredGrams;
  final double? consumedGrams;
  final ParsedHealthEnum<MealAcceptance> acceptance;
  final DateTime fedAt;
  final String? observations;

  /// Validação temporal com relógio injetado — não usa DateTime.now().
  void validateFedAt({required DateTime referenceNow}) {
    if (fedAt.isAfter(referenceNow)) {
      throw const HealthDomainException(
        'future_fed_at',
        'fed_at não pode estar no futuro',
      );
    }
  }

  static String _require(String value, String field) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw HealthDomainException('missing_$field', '$field é obrigatório');
    }
    return trimmed;
  }
}

/// Campos que o **cliente** pode fornecer para MealLog **avulso**.
///
/// Sem planId / plannedMealId / mealOccurrenceId.
final class AdHocMealClientInput {
  AdHocMealClientInput({
    required String dogId,
    required this.period,
    required num offeredGrams,
    required this.acceptance,
    required this.fedAt,
    num? consumedGrams,
    String? observations,
  }) : dogId = _require(dogId, 'dog_id'),
       offeredGrams = offeredGrams.toDouble(),
       consumedGrams = consumedGrams?.toDouble(),
       observations = observations?.trim() {
    if (period.isAbsent) {
      throw const HealthDomainException(
        'missing_period',
        'period é obrigatório em refeição avulsa',
      );
    }
    MealLog.validateQuantityInvariantsPublic(
      offeredGrams: this.offeredGrams,
      consumedGrams: this.consumedGrams,
      acceptance: acceptance,
    );
  }

  final String dogId;
  final ParsedHealthEnum<MealPeriod> period;
  final double offeredGrams;
  final double? consumedGrams;
  final ParsedHealthEnum<MealAcceptance> acceptance;
  final DateTime fedAt;
  final String? observations;

  void validateFedAt({required DateTime referenceNow}) {
    if (fedAt.isAfter(referenceNow)) {
      throw const HealthDomainException(
        'future_fed_at',
        'fed_at não pode estar no futuro',
      );
    }
  }

  static String _require(String value, String field) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw HealthDomainException('missing_$field', '$field é obrigatório');
    }
    return trimmed;
  }
}

/// Catálogo documental dos campos **server-derived** em MealLog planejado (D41).
///
/// Uso: testes de contrato e documentação. Não transporta rede.
abstract final class PlannedMealServerDerivedFields {
  PlannedMealServerDerivedFields._();

  static const fields = <String>{
    'period',
    'scheduled_for',
    'prescription_amount_at_time',
    'meal_occurrence_id',
    'recorded_by',
    'recorded_at',
    'revision',
    'schema_version',
  };

  static const clientFields = <String>{
    'dog_id',
    'plan_id',
    'planned_meal_id',
    'offered_grams',
    'consumed_grams',
    'acceptance',
    'fed_at',
    'observations',
  };

  /// Garante que o input de cliente não declara autoridade sobre derivados.
  static bool isClientAuthorityField(String wireName) =>
      clientFields.contains(wireName);

  static bool isServerDerivedField(String wireName) =>
      fields.contains(wireName);
}
