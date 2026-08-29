import 'package:canil_gcm/features/health/domain/health_nutrition_mutation_errors.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/supplement_log.dart';

/// Comandos de intenção do cliente para mutações canônicas de Nutrição (5D Gate 3).
///
/// Refletem D41: **sem** campos server-authoritative
/// (period planejado, scheduled_for, meal_occurrence_id, recorded_by, …).
///
/// [operationId] é obrigatório e atua como chave de idempotência estável.

/// Create MealLog planejado.
final class CreatePlannedMealLogCommand {
  CreatePlannedMealLogCommand({
    required String dogId,
    required String planId,
    required String plannedMealId,
    required num offeredGrams,
    required this.acceptance,
    required this.fedAt,
    required String operationId,
    num? consumedGrams,
    String? observations,
    List<String>? attachmentRefs,
  }) : dogId = _require(dogId, 'dogId'),
       planId = _require(planId, 'planId'),
       plannedMealId = _require(plannedMealId, 'plannedMealId'),
       offeredGrams = offeredGrams.toDouble(),
       consumedGrams = consumedGrams?.toDouble(),
       observations = observations?.trim(),
       attachmentRefs = _normalizeAttachments(attachmentRefs),
       operationId = _require(operationId, 'operationId') {
    if (!this.offeredGrams.isFinite || this.offeredGrams <= 0) {
      throw const HealthNutritionMutationValidation(
        'offeredGrams deve ser finito e maior que zero.',
      );
    }
    if (acceptance.isAbsent || acceptance.value == null) {
      throw const HealthNutritionMutationValidation(
        'acceptance é obrigatório.',
      );
    }
    _assertMealQuantities(
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
  final List<String> attachmentRefs;
  final String operationId;

  /// Fingerprint local da intenção (sem operationId) — só controller.
  String intentFingerprint() {
    return [
      'planned',
      dogId,
      planId,
      plannedMealId,
      offeredGrams.toString(),
      consumedGrams?.toString() ?? '',
      acceptance.value!.wireName,
      fedAt.toUtc().toIso8601String(),
      observations ?? '',
      attachmentRefs.join(','),
    ].join('|');
  }
}

/// Create MealLog avulso.
final class CreateAdhocMealLogCommand {
  CreateAdhocMealLogCommand({
    required String dogId,
    required this.period,
    required num offeredGrams,
    required this.acceptance,
    required this.fedAt,
    required String operationId,
    num? consumedGrams,
    String? observations,
    List<String>? attachmentRefs,
  }) : dogId = _require(dogId, 'dogId'),
       offeredGrams = offeredGrams.toDouble(),
       consumedGrams = consumedGrams?.toDouble(),
       observations = observations?.trim(),
       attachmentRefs = _normalizeAttachments(attachmentRefs),
       operationId = _require(operationId, 'operationId') {
    if (period.isAbsent || period.value == null) {
      throw const HealthNutritionMutationValidation(
        'period é obrigatório em refeição avulsa.',
      );
    }
    if (!this.offeredGrams.isFinite || this.offeredGrams <= 0) {
      throw const HealthNutritionMutationValidation(
        'offeredGrams deve ser finito e maior que zero.',
      );
    }
    if (acceptance.isAbsent || acceptance.value == null) {
      throw const HealthNutritionMutationValidation(
        'acceptance é obrigatório.',
      );
    }
    _assertMealQuantities(
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
  final List<String> attachmentRefs;
  final String operationId;

  String intentFingerprint() {
    return [
      'adhoc',
      dogId,
      period.value!.wireName,
      offeredGrams.toString(),
      consumedGrams?.toString() ?? '',
      acceptance.value!.wireName,
      fedAt.toUtc().toIso8601String(),
      observations ?? '',
      attachmentRefs.join(','),
    ].join('|');
  }
}

/// Create SupplementLog pontual.
final class CreateSupplementLogCommand {
  CreateSupplementLogCommand({
    required String dogId,
    required String supplementName,
    required num dose,
    required this.unit,
    required this.administeredAt,
    required String operationId,
    String? nutritionPlanId,
    String? supplementRegimenId,
    String? notes,
    String? batchNumber,
    String? protocolId,
  }) : dogId = _require(dogId, 'dogId'),
       supplementName = _require(supplementName, 'supplementName'),
       dose = dose.toDouble(),
       nutritionPlanId = nutritionPlanId?.trim(),
       supplementRegimenId = supplementRegimenId?.trim(),
       notes = notes?.trim(),
       batchNumber = batchNumber?.trim(),
       protocolId = protocolId?.trim(),
       operationId = _require(operationId, 'operationId') {
    if (!this.dose.isFinite || this.dose <= 0) {
      throw const HealthNutritionMutationValidation(
        'dose deve ser finita e maior que zero.',
      );
    }
    if (unit.isAbsent || unit.value == null) {
      throw const HealthNutritionMutationValidation('unit é obrigatório.');
    }
    // Regimen exige plano (fail-closed local; backend é autoridade final).
    final regimen = this.supplementRegimenId;
    final plan = this.nutritionPlanId;
    if (regimen != null &&
        regimen.isNotEmpty &&
        (plan == null || plan.isEmpty)) {
      throw const HealthNutritionMutationValidation(
        'supplementRegimenId exige nutritionPlanId.',
        detailCode: 'supplement_regimen_requires_plan',
      );
    }
  }

  final String dogId;
  final String supplementName;
  final double dose;
  final ParsedHealthEnum<SupplementDoseUnit> unit;
  final DateTime administeredAt;
  final String? nutritionPlanId;
  final String? supplementRegimenId;
  final String? notes;
  final String? batchNumber;
  final String? protocolId;
  final String operationId;

  String intentFingerprint() {
    return [
      'supplement',
      dogId,
      supplementName,
      dose.toString(),
      unit.value!.wireName,
      administeredAt.toUtc().toIso8601String(),
      nutritionPlanId ?? '',
      supplementRegimenId ?? '',
      notes ?? '',
      batchNumber ?? '',
      protocolId ?? '',
    ].join('|');
  }
}

String _require(String value, String field) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw HealthNutritionMutationValidation('$field é obrigatório.');
  }
  return trimmed;
}

List<String> _normalizeAttachments(List<String>? raw) {
  if (raw == null || raw.isEmpty) return const [];
  final out = <String>[];
  for (final item in raw) {
    final s = item.trim();
    if (s.isNotEmpty) out.add(s);
  }
  return List.unmodifiable(out);
}

void _assertMealQuantities({
  required double offeredGrams,
  required double? consumedGrams,
  required ParsedHealthEnum<MealAcceptance> acceptance,
}) {
  try {
    MealLog.validateQuantityInvariantsPublic(
      offeredGrams: offeredGrams,
      consumedGrams: consumedGrams,
      acceptance: acceptance,
    );
  } on HealthDomainException catch (e) {
    throw HealthNutritionMutationValidation(e.message);
  }
}
