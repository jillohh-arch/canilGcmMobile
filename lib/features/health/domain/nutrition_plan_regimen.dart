import 'health_v1_models.dart';
import 'supplement_log.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Regime prescrito embutido em NutritionPlan.supplements[] (D13–D14).
// ≠ SupplementLog (administração pontual). ≠ nutrition_supplements legado.
// ─────────────────────────────────────────────────────────────────────────────

/// Item de regime nutricional prescrito no plano (não é log de administração).
/// Contrato canônico Health v1:
/// - dose: número finito e positivo
/// - unit: SupplementDoseUnit canônico
final class NutritionPlanSupplementRegimen {
  NutritionPlanSupplementRegimen({
    required String id,
    required String name,
    required num dose,
    required SupplementDoseUnit unit,
    required String frequency,
    String? instructions,
    this.validFrom,
    this.validUntil,
  }) : id = _requireId(id),
       name = _requireName(name),
       dose = _requireDose(dose),
       unit = unit,
       frequency = _requireFrequency(frequency),
       instructions = instructions?.trim() {
    final until = validUntil;
    final from = validFrom;
    if (until != null && from != null && !until.isAfter(from)) {
      throw const HealthDomainException(
        'inconsistent_regimen_validity',
        'supplement regimen valid_until deve ser > valid_from quando ambos presentes',
      );
    }
  }

  final String id;
  final String name;

  /// Dose numérica finita e positiva.
  final num dose;

  /// Unidade canônica.
  final SupplementDoseUnit unit;

  final String frequency;
  final String? instructions;
  final DateTime? validFrom;
  final DateTime? validUntil;

  static String _requireId(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw const HealthDomainException(
        'missing_supplement_regimen_id',
        'supplement_regimen_id é obrigatório',
      );
    }
    return trimmed;
  }

  static String _requireName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw const HealthDomainException(
        'missing_supplement_regimen_name',
        'supplement_regimen_name é obrigatório',
      );
    }
    return trimmed;
  }

  static num _requireDose(num value) {
    if (!value.isFinite || value <= 0) {
      throw const HealthDomainException(
        'invalid_regimen_dose',
        'supplement_regimen_dose deve ser número finito e positivo',
      );
    }
    return value;
  }

  static String _requireFrequency(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw const HealthDomainException(
        'missing_supplement_regimen_frequency',
        'supplement_regimen_frequency é obrigatório',
      );
    }
    return trimmed;
  }

  @override
  bool operator ==(Object other) =>
      other is NutritionPlanSupplementRegimen &&
      other.id == id &&
      other.name == name &&
      other.dose == dose &&
      other.unit == unit &&
      other.frequency == frequency &&
      other.instructions == instructions &&
      other.validFrom == validFrom &&
      other.validUntil == validUntil;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    dose,
    unit,
    frequency,
    instructions,
    validFrom,
    validUntil,
  );
}
