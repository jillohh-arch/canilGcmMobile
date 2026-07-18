import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'health_v1_enums.dart';
import 'health_v1_models.dart';
import 'health_v1_value_objects.dart';
import 'meal_schedule_slot.dart';
import 'nutrition_plan_regimen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// NutritionPlan — plano alimentar canônico (Domain Model §2.7 / D1–D5 / D40).
// Mobile: read-only no contrato novo. Writer: backend / Web-originated.
// ─────────────────────────────────────────────────────────────────────────────

enum NutritionPlanStatus {
  active,
  superseded,
  cancelled;

  String get wireName => switch (this) {
    NutritionPlanStatus.active => 'active',
    NutritionPlanStatus.superseded => 'superseded',
    NutritionPlanStatus.cancelled => 'cancelled',
  };

  static ParsedHealthEnum<NutritionPlanStatus> parse(Object? value) =>
      parseHealthEnum<NutritionPlanStatus>(
        value,
        NutritionPlanStatus.values,
        (item) => item.wireName,
      );
}

final class NutritionPlan {
  /// Default de domínio (D27) quando legado não traz timezone.
  static const defaultTimezone = 'America/Sao_Paulo';

  NutritionPlan({
    required String id,
    required String dogId,
    required String foodType,
    required num amountGramsPerDay,
    required this.mealsPerDay,
    required List<MealScheduleSlot> mealSchedule,
    required this.validFrom,
    required String timezone,
    required this.recordedBy,
    required this.status,
    required this.schemaVersion,
    required this.revision,
    this.validUntil,
    this.hydrationMl,
    String? specialInstructions,
    this.professional,
    this.sourceDocument,
    List<String>? attachmentRefs,
    List<NutritionPlanSupplementRegimen>? supplements,
    String? legacySource,
    String? legacyId,
  }) : id = _require(id, 'id'),
       dogId = _require(dogId, 'dog_id'),
       foodType = _require(foodType, 'food_type'),
       amountGramsPerDay = amountGramsPerDay.toDouble(),
       mealSchedule = List.unmodifiable(
         List<MealScheduleSlot>.of(mealSchedule),
       ),
       timezone = _requireTimezone(timezone),
       specialInstructions = specialInstructions?.trim(),
       attachmentRefs = List.unmodifiable(
         List<String>.of(attachmentRefs ?? const []),
       ),
       supplements = List.unmodifiable(
         List<NutritionPlanSupplementRegimen>.of(supplements ?? const []),
       ),
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
    if (!this.amountGramsPerDay.isFinite || this.amountGramsPerDay <= 0) {
      throw const HealthDomainException(
        'invalid_amount',
        'amount_grams_per_day deve ser finito e maior que zero',
      );
    }
    if (mealsPerDay <= 0) {
      throw const HealthDomainException(
        'invalid_meals_per_day',
        'meals_per_day deve ser positivo',
      );
    }
    final hm = hydrationMl;
    if (hm != null && (!hm.isFinite || hm < 0)) {
      throw const HealthDomainException(
        'invalid_hydration',
        'hydration_ml deve ser finito e não negativo',
      );
    }
    final until = validUntil;
    // D4: valid_until == null OR valid_until > valid_from (estrito).
    if (until != null && !until.isAfter(validFrom)) {
      throw const HealthDomainException(
        'inconsistent_validity',
        'valid_until deve ser estritamente posterior a valid_from',
      );
    }
    _assertUniqueSlotIds(this.mealSchedule);
  }

  final String id;
  final String dogId;
  final String foodType;
  final double amountGramsPerDay;
  final int mealsPerDay;
  final List<MealScheduleSlot> mealSchedule;
  final DateTime validFrom;
  final DateTime? validUntil;
  final String timezone;
  final double? hydrationMl;
  final String? specialInstructions;
  final ProfessionalIdentity? professional;
  final HealthDocumentRef? sourceDocument;
  final List<String> attachmentRefs;
  final List<NutritionPlanSupplementRegimen> supplements;
  final RecordedBy recordedBy;
  final NutritionPlanStatus status;
  final int schemaVersion;
  final int revision;
  final String? legacySource;
  final String? legacyId;

  /// Quantidade média por refeição (derivado).
  double get amountPerMeal => amountGramsPerDay / mealsPerDay;

  /// Soma de `target_grams` do schedule (null se schedule vazio).
  double? get scheduleTargetGramsSum {
    if (mealSchedule.isEmpty) return null;
    return mealSchedule.fold<double>(0, (sum, s) => sum + s.targetGrams);
  }

  /// Diagnóstico de coerência — **não** rejeita construção (relatório 5C).
  ///
  /// `meals_per_day` tipicamente == `meal_schedule.length`; soma de
  /// `target_grams` tipicamente == `amount_grams_per_day`. Igualdade absoluta
  /// de gramas **não** é rejeição rígida sem tolerância institucional.
  NutritionPlanCoherence diagnoseCoherence() {
    final sum = scheduleTargetGramsSum;
    return NutritionPlanCoherence(
      mealsPerDayMatchesScheduleLength: mealSchedule.length == mealsPerDay,
      scheduleLength: mealSchedule.length,
      mealsPerDay: mealsPerDay,
      targetGramsSum: sum,
      amountGramsPerDay: amountGramsPerDay,
      targetGramsSumMatchesAmount:
          sum != null && _nearlyEqual(sum, amountGramsPerDay),
    );
  }

  /// Validação temporal de **ativação** com relógio injetado (D40).
  ///
  /// - Parsing/leitura **não** chamam isto implicitamente.
  /// - Não altera o objeto.
  /// - Não cria status `scheduled`.
  ///
  /// Para `status == active`:
  /// - `valid_from <= serverNow`
  /// - `valid_until == null || valid_until > serverNow`
  void validateForActivation(DateTime serverNow) {
    if (status != NutritionPlanStatus.active) {
      return;
    }
    if (validFrom.isAfter(serverNow)) {
      throw const HealthDomainException(
        'future_valid_from',
        'plano active não pode ter valid_from no futuro (D40)',
      );
    }
    final until = validUntil;
    if (until != null && !until.isAfter(serverNow)) {
      throw const HealthDomainException(
        'active_plan_already_expired',
        'plano active não pode nascer já expirado (valid_until <= server_now)',
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

  static String _requireTimezone(String timezone) {
    final name = timezone.trim();
    if (name.isEmpty) {
      throw const HealthDomainException(
        'missing_timezone',
        'timezone é obrigatório',
      );
    }
    _ensureTimeZonesInitialized();
    try {
      tz.getLocation(name);
    } on Exception {
      throw HealthDomainException(
        'invalid_timezone',
        'timezone "$name" não é reconhecido pela base IANA',
      );
    }
    return name;
  }

  static bool _tzReady = false;

  static void _ensureTimeZonesInitialized() {
    if (_tzReady) return;
    tz_data.initializeTimeZones();
    _tzReady = true;
  }

  static void _assertUniqueSlotIds(List<MealScheduleSlot> slots) {
    final seen = <String>{};
    for (final slot in slots) {
      if (!seen.add(slot.id)) {
        throw HealthDomainException(
          'duplicate_meal_schedule_slot_id',
          'meal_schedule.id duplicado: ${slot.id}',
        );
      }
    }
  }

  static bool _nearlyEqual(double a, double b) => (a - b).abs() < 1e-9;
}

/// Diagnóstico de coerência do plano (não é falha de construção).
final class NutritionPlanCoherence {
  const NutritionPlanCoherence({
    required this.mealsPerDayMatchesScheduleLength,
    required this.scheduleLength,
    required this.mealsPerDay,
    required this.targetGramsSum,
    required this.amountGramsPerDay,
    required this.targetGramsSumMatchesAmount,
  });

  final bool mealsPerDayMatchesScheduleLength;
  final int scheduleLength;
  final int mealsPerDay;
  final double? targetGramsSum;
  final double amountGramsPerDay;
  final bool targetGramsSumMatchesAmount;

  bool get isFullyCoherent =>
      mealsPerDayMatchesScheduleLength && targetGramsSumMatchesAmount;
}

/// Política pura de coexistência de planos (máx. 1 active por cão).
final class NutritionPlanConflictPolicy {
  const NutritionPlanConflictPolicy();

  /// Retorna lista vazia quando não há conflitos.
  List<String> evaluate(Iterable<NutritionPlan> plans) {
    final activeByDog = <String, int>{};
    for (final plan in plans) {
      if (plan.status == NutritionPlanStatus.active) {
        activeByDog[plan.dogId] = (activeByDog[plan.dogId] ?? 0) + 1;
      }
    }
    final conflicts = <String>[];
    activeByDog.forEach((dogId, count) {
      if (count > 1) {
        conflicts.add('dog=$dogId activeCount=$count');
      }
    });
    return List.unmodifiable(conflicts);
  }
}
