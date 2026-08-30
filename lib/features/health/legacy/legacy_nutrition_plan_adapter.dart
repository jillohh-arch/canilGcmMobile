import '../domain/legacy_nutrition_views.dart';
import 'legacy_health_adapters.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Adapter legado nutritional_prescriptions / nutrition_prescriptions.
// §23: NÃO fabrica NutritionPlan canônico (sem meal_schedule/status/tz/revision).
// ZERO Firebase. ZERO write.
// ─────────────────────────────────────────────────────────────────────────────

/// Produz [LegacyNutritionPlanView] de compatibilidade read-only.
final class LegacyNutritionPlanAdapter {
  const LegacyNutritionPlanAdapter();

  LegacyParseResult<LegacyNutritionPlanView> parse({
    required String sourceId,
    required String dogId,
    required Map<String, Object?> data,
    String legacySource = 'nutritional_prescriptions',
  }) {
    final issues = <LegacyParseIssue>[];
    if (sourceId.trim().isEmpty) {
      issues.add(_error('missing', 'source_id', 'Identificador ausente'));
    }
    if (dogId.trim().isEmpty) {
      issues.add(_error('missing', 'dog_id', 'K9 ausente'));
    }

    final foodType = _nonEmpty(data, const [
      'food_type',
      'foodType',
      'racao',
      'food',
    ]);
    final amount = _number(data, const [
      'amount_grams_per_day',
      'amountGramsPerDay',
      'daily_amount',
    ]);
    final meals = _number(data, const [
      'meals_per_day',
      'mealsPerDay',
      'meals',
    ]);
    final vigentFrom = LegacyDateParser.parse(
      data['vigent_from'] ??
          data['vigentFrom'] ??
          data['valid_from'] ??
          data['created_at'],
    );
    final vigentUntil = LegacyDateParser.parse(
      data['vigent_until'] ?? data['vigentUntil'] ?? data['valid_until'],
    );

    if (foodType == null) {
      issues.add(_error('missing', 'food_type', 'Tipo de alimento ausente'));
    }
    if (amount == null || !amount.toDouble().isFinite || amount <= 0) {
      issues.add(
        _error('invalid_number', 'amount_grams_per_day', 'Quantidade inválida'),
      );
    }
    final mealsInt = meals?.toInt();
    if (meals == null || mealsInt == null || mealsInt <= 0) {
      issues.add(
        _error('invalid_number', 'meals_per_day', 'meals_per_day inválido'),
      );
    }
    if (!vigentFrom.hasValue) {
      issues.add(
        _error(vigentFrom.issues.first.code, 'vigent_from', 'Data inválida'),
      );
    }
    if (vigentUntil.state == LegacyParseState.failure) {
      issues.add(
        _error(
          vigentUntil.issues.first.code,
          'vigent_until',
          'vigent_until inválido',
        ),
      );
    }

    if (issues.isNotEmpty) return LegacyParseResult.failure(issues);

    final warnings = <LegacyParseIssue>[
      const LegacyParseIssue(
        code: 'meal_schedule_unavailable',
        field: 'meal_schedule',
        severity: LegacyIssueSeverity.warning,
        message:
            'Plano legado sem meal_schedule canônico; view de compatibilidade apenas',
      ),
    ];

    final view = LegacyNutritionPlanView(
      id: sourceId,
      dogId: dogId,
      foodType: foodType!,
      amountGramsPerDay: amount!.toDouble(),
      mealsPerDay: mealsInt!,
      vigentFrom: vigentFrom.value!,
      vigentUntil: vigentUntil.hasValue ? vigentUntil.value : null,
      hydrationMl: _number(data, const ['hydration_ml'])?.toDouble(),
      notes: _nonEmpty(data, const [
        'special_instructions',
        'notes',
        'observations',
      ]),
      professionalName: _nonEmpty(data, const [
        'vet_name',
        'professional_name',
        'vetName',
      ]),
      professionalCrmv: _nonEmpty(data, const [
        'vet_crmv',
        'crmv',
        'professional_crmv',
      ]),
      rawStatus: _nonEmpty(data, const ['status']),
      legacySource: legacySource,
      legacyId: sourceId,
    );

    assert(view.mealScheduleUnavailable, 'legado nunca inventa schedule');
    return LegacyParseResult.partial(view, warnings);
  }
}

LegacyParseIssue _error(String code, String field, String message) =>
    LegacyParseIssue(
      code: code,
      field: field,
      severity: LegacyIssueSeverity.error,
      message: message,
    );

String? _nonEmpty(Map data, List<String> keys) {
  for (final key in keys) {
    final v = data[key]?.toString().trim();
    if (v != null && v.isNotEmpty) return v;
  }
  return null;
}

num? _number(Map data, List<String> keys) {
  for (final key in keys) {
    final value = data[key];
    if (value is num) return value;
    if (value is String) {
      final parsed = num.tryParse(value.replaceAll(',', '.'));
      if (parsed != null) return parsed;
    }
  }
  return null;
}
