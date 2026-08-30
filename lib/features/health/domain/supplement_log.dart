import 'health_v1_enums.dart';
import 'health_v1_models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SupplementLog — administração pontual (Domain Model §2.9 / D15–D16).
// ≠ regime em NutritionPlan.supplements[] ≠ nutrition_supplements legado.
// ZERO backfill inventado a partir de regime.
// ─────────────────────────────────────────────────────────────────────────────

final class SupplementLog {
  SupplementLog({
    required String id,
    required String dogId,
    required String supplementName,
    required num dose,
    required this.unit,
    required this.administeredAt,
    required this.recordedBy,
    required this.schemaVersion,
    required this.revision,
    String? notes,
    String? batchNumber,
    this.protocolId,
    this.nutritionPlanId,
    this.supplementRegimenId,
    String? legacySource,
    String? legacyId,
  }) : id = _require(id, 'id'),
       dogId = _require(dogId, 'dog_id'),
       supplementName = _require(supplementName, 'supplement_name'),
       dose = dose.toDouble(),
       notes = notes?.trim(),
       batchNumber = batchNumber?.trim(),
       legacySource = legacySource?.trim(),
       legacyId = legacyId?.trim() {
    if (schemaVersion <= 0) {
      throw const HealthDomainException(
        'invalid_schema_version',
        'schema_version deve ser positivo',
      );
    }
    if (revision < 1) {
      throw const HealthDomainException(
        'invalid_revision',
        'revision deve ser >= 1 para documento canônico',
      );
    }
    if (!this.dose.isFinite || this.dose <= 0) {
      throw const HealthDomainException(
        'invalid_supplement_dose',
        'dose deve ser finita e maior que zero',
      );
    }
  }

  final String id;
  final String dogId;
  final String supplementName;
  final double dose;
  final SupplementDoseUnit unit;
  final DateTime administeredAt;
  final RecordedBy recordedBy;
  final int schemaVersion;
  final int revision;
  final String? notes;
  final String? batchNumber;
  final String? protocolId;
  final String? nutritionPlanId;
  final String? supplementRegimenId;
  final String? legacySource;
  final String? legacyId;

  /// `administered_at` não pode ser futuro (relógio injetado).
  void validateAdministeredAt({required DateTime referenceTime}) {
    if (administeredAt.isAfter(referenceTime)) {
      throw const HealthDomainException(
        'future_administered_at',
        'administered_at não pode estar no futuro',
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

enum SupplementDoseUnit {
  mg,
  g,
  ml,
  scoop,
  tablet,
  drop,
  other;

  String get wireName => switch (this) {
    SupplementDoseUnit.mg => 'mg',
    SupplementDoseUnit.g => 'g',
    SupplementDoseUnit.ml => 'ml',
    SupplementDoseUnit.scoop => 'scoop',
    SupplementDoseUnit.tablet => 'tablet',
    SupplementDoseUnit.drop => 'drop',
    SupplementDoseUnit.other => 'other',
  };

  /// Label amigável para exibição ao usuário em cards e listas.
  /// Não altera o wire value enviado ao backend.
  String get displayLabel => switch (this) {
    SupplementDoseUnit.mg => 'mg',
    SupplementDoseUnit.g => 'g',
    SupplementDoseUnit.ml => 'ml',
    SupplementDoseUnit.scoop => 'scoop',
    SupplementDoseUnit.tablet => 'comprimido',
    SupplementDoseUnit.drop => 'gota',
    SupplementDoseUnit.other => 'outra',
  };

  static ParsedHealthEnum<SupplementDoseUnit> parse(Object? value) =>
      parseHealthEnum<SupplementDoseUnit>(
        value,
        SupplementDoseUnit.values,
        (item) => item.wireName,
      );
}
