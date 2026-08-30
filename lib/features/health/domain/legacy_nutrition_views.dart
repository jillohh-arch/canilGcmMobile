// ─────────────────────────────────────────────────────────────────────────────
// Views de compatibilidade legada (read-only) — NÃO são agregados canônicos.
// §23–§25 / D33 / D16.
// ─────────────────────────────────────────────────────────────────────────────

/// Plano legado incompleto para dual-read.
///
/// **Não** é [NutritionPlan]: não fabrica `meal_schedule`, status machine,
/// timezone canônico nem revision. UI/coexistence devem tratar como fallback.
final class LegacyNutritionPlanView {
  LegacyNutritionPlanView({
    required this.id,
    required this.dogId,
    required this.foodType,
    required this.amountGramsPerDay,
    required this.mealsPerDay,
    required this.vigentFrom,
    required this.legacySource,
    this.vigentUntil,
    this.hydrationMl,
    this.notes,
    this.professionalName,
    this.professionalCrmv,
    this.rawStatus,
    this.legacyId,
  }) : mealScheduleUnavailable = true;

  final String id;
  final String dogId;
  final String foodType;
  final double amountGramsPerDay;
  final int mealsPerDay;
  final DateTime vigentFrom;
  final DateTime? vigentUntil;
  final double? hydrationMl;
  final String? notes;
  final String? professionalName;
  final String? professionalCrmv;

  /// Status bruto do documento legado (se existir) — **não** normalizado
  /// para `NutritionPlanStatus` persistido.
  final String? rawStatus;
  final String legacySource;
  final String? legacyId;

  /// Sempre true: legado não possui slots canônicos (D5/D33).
  final bool mealScheduleUnavailable;

  /// Aviso estável: não apresentar como plano canônico completo.
  String get compatibilityNote =>
      'legacy_plan_view:meal_schedule_unavailable;not_canonical_nutrition_plan';
}

/// Regime “em uso” legado (`nutrition_supplements`) — **≠** SupplementLog.
final class LegacySupplementRegimenView {
  const LegacySupplementRegimenView({
    required this.id,
    required this.dogId,
    required this.name,
    required this.doseText,
    required this.legacySource,
    this.startedAt,
    this.endedAt,
    this.status,
    this.notes,
    this.unitText,
    this.frequencyText,
    this.legacyId,
  });

  final String id;
  final String dogId;
  final String name;

  /// Dose textual original — **não** convertida em dose canônica numérica.
  final String doseText;
  final String? unitText;
  final String? frequencyText;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final String? status;
  final String? notes;
  final String legacySource;
  final String? legacyId;

  /// Nunca possui administeredAt — não é administração.
  bool get isAdministration => false;
}
