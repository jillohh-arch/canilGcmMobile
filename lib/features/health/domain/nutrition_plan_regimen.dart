import 'health_v1_models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Regime prescrito embutido em NutritionPlan.supplements[] (D13–D14).
// ≠ SupplementLog (administração pontual). ≠ nutrition_supplements legado.
// ─────────────────────────────────────────────────────────────────────────────

/// Item de regime nutricional prescrito no plano (não é log de administração).
final class NutritionPlanSupplementRegimen {
  NutritionPlanSupplementRegimen({
    required String id,
    required String name,
    required String dose,
    required String unit,
    required String frequency,
    String? instructions,
    this.validFrom,
    this.validUntil,
  }) : id = _require(id, 'supplement_regimen_id'),
       name = _require(name, 'supplement_regimen_name'),
       dose = _require(dose, 'supplement_regimen_dose'),
       unit = _require(unit, 'supplement_regimen_unit'),
       frequency = _require(frequency, 'supplement_regimen_frequency'),
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

  /// Representação prescrita (pode ser textual — regime ≠ dose estruturada do log).
  final String dose;
  final String unit;
  final String frequency;
  final String? instructions;
  final DateTime? validFrom;
  final DateTime? validUntil;

  static String _require(String value, String field) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw HealthDomainException('missing_$field', '$field é obrigatório');
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
