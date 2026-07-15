import 'health_v1_models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SupplementLog — registro de suplementação (Domain Model §2.9).
// ─────────────────────────────────────────────────────────────────────────────

final class SupplementLog {
  SupplementLog({
    required this.id,
    required this.dogId,
    required this.supplementName,
    required num dose,
    required this.unit,
    required DateTime administeredAt,
    required this.recordedBy,
    required this.schemaVersion,
    String? notes,
    String? batchNumber,
    this.protocolId,
    this.nutritionPlanId,
  }) : dose = dose.toDouble(),
       administeredAt = administeredAt,
       notes = notes?.trim(),
       batchNumber = batchNumber?.trim() {
    if (schemaVersion <= 0) {
      throw const HealthDomainException(
        'invalid_schema_version',
        'schema_version deve ser positivo',
      );
    }
    if (supplementName.trim().isEmpty) {
      throw const HealthDomainException(
        'missing_supplement_name',
        'supplement_name é obrigatório',
      );
    }
    if (!dose.isFinite || dose <= 0) {
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
  final String? notes;
  final String? batchNumber;
  final String? protocolId;
  final String? nutritionPlanId;
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
}
