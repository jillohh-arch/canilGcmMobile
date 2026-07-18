import 'health_v1_enums.dart';
import 'health_v1_models.dart';
import 'meal_schedule_slot.dart';
import 'nutrition_plan.dart';
import 'nutrition_plan_regimen.dart';
import 'supplement_log.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Parsers de mapas → domínio canônico (puro Dart, ZERO Firebase).
// Recebem dados já lidos; falham com [HealthDomainException] em integridade.
// ─────────────────────────────────────────────────────────────────────────────

/// Helpers compartilhados de parsing defensivo (sem Timestamp SDK).
abstract final class NutritionFieldParse {
  NutritionFieldParse._();

  static String? nonEmptyString(Object? value) {
    if (value == null) return null;
    final s = value.toString().trim();
    return s.isEmpty ? null : s;
  }

  static num? number(Object? value) {
    if (value is num) return value;
    if (value is String) {
      return num.tryParse(value.replaceAll(',', '.'));
    }
    return null;
  }

  static int? positiveInt(Object? value) {
    final n = number(value);
    if (n == null || !n.isFinite) return null;
    final i = n.toInt();
    if (i != n) return null;
    return i;
  }

  /// DateTime, ISO-8601 string, ou map `{seconds|_seconds, nanoseconds|_nanoseconds}`.
  static DateTime? dateTime(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) {
      final t = value.trim();
      if (t.isEmpty) return null;
      return DateTime.tryParse(t);
    }
    if (value is Map) {
      final seconds = value.containsKey('seconds')
          ? value['seconds']
          : value['_seconds'];
      final nanos = value.containsKey('nanoseconds')
          ? value['nanoseconds']
          : value['_nanoseconds'] ?? 0;
      if (seconds is! num || nanos is! num) return null;
      if (!seconds.isFinite || !nanos.isFinite) return null;
      final micros =
          BigInt.from(seconds.toInt()) * BigInt.from(1000000) +
          BigInt.from(nanos.toInt() ~/ 1000);
      if (!micros.isValidInt) return null;
      return DateTime.fromMicrosecondsSinceEpoch(micros.toInt(), isUtc: true);
    }
    // Timestamp-like duck typing (ex.: fake em testes com toDate()).
    try {
      final converted = (value as dynamic).toDate();
      if (converted is DateTime) return converted;
    } catch (_) {
      // ignore — não é timestamp-like
    }
    return null;
  }

  static RecordedBy? recordedBy(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, Object?>.from(raw);
    final uid = nonEmptyString(map['uid'] ?? map['id']);
    final name = nonEmptyString(map['name']);
    final role = nonEmptyString(map['internal_role'] ?? map['role']);
    if (uid == null || name == null || role == null) return null;
    try {
      return RecordedBy(uid: uid, name: name, internalRole: role);
    } on HealthDomainException {
      return null;
    }
  }

  static List<String> stringList(Object? raw) {
    if (raw is! List) return const [];
    final out = <String>[];
    for (final item in raw) {
      final s = nonEmptyString(item);
      if (s != null) out.add(s);
    }
    return out;
  }
}

/// Parser canônico de documento `nutrition_plans` (map já materializado).
abstract final class NutritionPlanDocumentParser {
  NutritionPlanDocumentParser._();

  static NutritionPlan parse({
    required String id,
    required String dogId,
    required Map<String, Object?> data,
  }) {
    final foodType = NutritionFieldParse.nonEmptyString(data['food_type']);
    if (foodType == null) {
      throw const HealthDomainException(
        'missing_food_type',
        'food_type é obrigatório',
      );
    }

    final amount = NutritionFieldParse.number(data['amount_grams_per_day']);
    if (amount == null) {
      throw const HealthDomainException(
        'missing_amount_grams_per_day',
        'amount_grams_per_day é obrigatório',
      );
    }

    final meals = NutritionFieldParse.positiveInt(data['meals_per_day']);
    if (meals == null || meals <= 0) {
      throw const HealthDomainException(
        'invalid_meals_per_day',
        'meals_per_day inválido',
      );
    }

    final validFrom = NutritionFieldParse.dateTime(data['valid_from']);
    if (validFrom == null) {
      throw const HealthDomainException(
        'missing_valid_from',
        'valid_from é obrigatório',
      );
    }
    final validUntil = NutritionFieldParse.dateTime(data['valid_until']);

    final timezone =
        NutritionFieldParse.nonEmptyString(data['timezone']) ??
        NutritionPlan.defaultTimezone;

    final statusParsed = NutritionPlanStatus.parse(data['status']);
    if (!statusParsed.isKnown || statusParsed.value == null) {
      throw HealthDomainException(
        'invalid_status',
        'status de plano inválido: ${statusParsed.raw}',
      );
    }

    final recordedBy = NutritionFieldParse.recordedBy(data['recorded_by']);
    if (recordedBy == null) {
      throw const HealthDomainException(
        'missing_recorded_by',
        'recorded_by é obrigatório',
      );
    }

    final schema = NutritionFieldParse.positiveInt(data['schema_version']);
    if (schema == null || schema <= 0) {
      throw const HealthDomainException(
        'invalid_schema_version',
        'schema_version inválido',
      );
    }

    final revision = NutritionFieldParse.positiveInt(data['revision']);
    if (revision == null || revision < 1) {
      throw const HealthDomainException(
        'invalid_revision',
        'revision inválido',
      );
    }

    final schedule = _parseSchedule(data['meal_schedule']);
    final supplements = _parseSupplements(data['supplements']);

    final hydration = NutritionFieldParse.number(data['hydration_ml']);

    return NutritionPlan(
      id: id,
      dogId: dogId,
      foodType: foodType,
      amountGramsPerDay: amount,
      mealsPerDay: meals,
      mealSchedule: schedule,
      validFrom: validFrom,
      validUntil: validUntil,
      timezone: timezone,
      recordedBy: recordedBy,
      status: statusParsed.value!,
      schemaVersion: schema,
      revision: revision,
      hydrationMl: hydration?.toDouble(),
      specialInstructions: NutritionFieldParse.nonEmptyString(
        data['special_instructions'],
      ),
      attachmentRefs: NutritionFieldParse.stringList(data['attachment_refs']),
      supplements: supplements,
      legacySource: NutritionFieldParse.nonEmptyString(data['legacy_source']),
      legacyId: NutritionFieldParse.nonEmptyString(data['legacy_id']),
    );
  }

  static List<MealScheduleSlot> _parseSchedule(Object? raw) {
    if (raw == null) return const [];
    if (raw is! List) {
      throw const HealthDomainException(
        'invalid_meal_schedule',
        'meal_schedule deve ser array',
      );
    }
    final slots = <MealScheduleSlot>[];
    for (var i = 0; i < raw.length; i++) {
      final item = raw[i];
      if (item is! Map) {
        throw HealthDomainException(
          'invalid_meal_schedule_slot',
          'meal_schedule[$i] deve ser map',
        );
      }
      final map = Map<String, Object?>.from(item);
      final id = NutritionFieldParse.nonEmptyString(map['id']);
      if (id == null) {
        throw HealthDomainException(
          'missing_meal_schedule_slot_id',
          'meal_schedule[$i].id ausente',
        );
      }
      final period = MealPeriodWire.parseCanonical(map['period']);
      final timeRaw = NutritionFieldParse.nonEmptyString(map['scheduled_time']);
      if (timeRaw == null) {
        throw HealthDomainException(
          'missing_scheduled_time',
          'meal_schedule[$i].scheduled_time ausente',
        );
      }
      final target = NutritionFieldParse.number(map['target_grams']);
      if (target == null) {
        throw HealthDomainException(
          'missing_target_grams',
          'meal_schedule[$i].target_grams ausente',
        );
      }
      slots.add(
        MealScheduleSlot(
          id: id,
          period: period,
          scheduledTime: ScheduledTimeOfDay(timeRaw),
          targetGrams: target,
        ),
      );
    }
    return slots;
  }

  static List<NutritionPlanSupplementRegimen> _parseSupplements(Object? raw) {
    if (raw == null) return const [];
    if (raw is! List) {
      throw const HealthDomainException(
        'invalid_supplements',
        'supplements deve ser array',
      );
    }
    final out = <NutritionPlanSupplementRegimen>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final map = Map<String, Object?>.from(item);
      final id = NutritionFieldParse.nonEmptyString(map['id']);
      final name = NutritionFieldParse.nonEmptyString(map['name']);
      final dose = NutritionFieldParse.nonEmptyString(map['dose']);
      final unit = NutritionFieldParse.nonEmptyString(map['unit']);
      final frequency = NutritionFieldParse.nonEmptyString(map['frequency']);
      if (id == null ||
          name == null ||
          dose == null ||
          unit == null ||
          frequency == null) {
        throw const HealthDomainException(
          'invalid_supplement_regimen',
          'supplement regimen incompleto (id/name/dose/unit/frequency)',
        );
      }
      out.add(
        NutritionPlanSupplementRegimen(
          id: id,
          name: name,
          dose: dose,
          unit: unit,
          frequency: frequency,
          instructions: NutritionFieldParse.nonEmptyString(map['instructions']),
          validFrom: NutritionFieldParse.dateTime(map['valid_from']),
          validUntil: NutritionFieldParse.dateTime(map['valid_until']),
        ),
      );
    }
    return out;
  }
}

/// Parser canônico de documento `meal_logs`.
abstract final class MealLogDocumentParser {
  MealLogDocumentParser._();

  static MealLog parse({
    required String id,
    required String dogId,
    required Map<String, Object?> data,
  }) {
    final period = MealPeriodWire.parseCanonical(data['period']);
    final acceptance = MealAcceptanceWire.parse(data['acceptance']);
    final offered = NutritionFieldParse.number(data['offered_grams']);
    final fedAt = NutritionFieldParse.dateTime(data['fed_at']);
    final recordedBy = NutritionFieldParse.recordedBy(data['recorded_by']);
    final schema = NutritionFieldParse.positiveInt(data['schema_version']);
    final revision = NutritionFieldParse.positiveInt(data['revision']);

    if (offered == null) {
      throw const HealthDomainException(
        'missing_offered_grams',
        'offered_grams é obrigatório',
      );
    }
    if (fedAt == null) {
      throw const HealthDomainException(
        'missing_fed_at',
        'fed_at é obrigatório',
      );
    }
    if (recordedBy == null) {
      throw const HealthDomainException(
        'missing_recorded_by',
        'recorded_by é obrigatório',
      );
    }
    if (schema == null || schema <= 0) {
      throw const HealthDomainException(
        'invalid_schema_version',
        'schema_version inválido',
      );
    }
    if (revision == null || revision < 1) {
      throw const HealthDomainException(
        'invalid_revision',
        'revision inválido',
      );
    }

    return MealLog(
      id: id,
      dogId: dogId,
      period: period,
      offeredGrams: offered,
      acceptance: acceptance,
      fedAt: fedAt,
      recordedBy: recordedBy,
      schemaVersion: schema,
      revision: revision,
      planId: NutritionFieldParse.nonEmptyString(data['plan_id']),
      plannedMealId: NutritionFieldParse.nonEmptyString(
        data['planned_meal_id'],
      ),
      mealOccurrenceId: NutritionFieldParse.nonEmptyString(
        data['meal_occurrence_id'],
      ),
      scheduledFor: NutritionFieldParse.dateTime(data['scheduled_for']),
      consumedGrams: NutritionFieldParse.number(data['consumed_grams']),
      observations: NutritionFieldParse.nonEmptyString(data['observations']),
      attachmentRefs: NutritionFieldParse.stringList(data['attachment_refs']),
      legacyPhotoBalanceUrl: NutritionFieldParse.nonEmptyString(
        data['legacy_photo_balance_url'],
      ),
      prescriptionAmountAtTime: NutritionFieldParse.number(
        data['prescription_amount_at_time'],
      ),
      divergencePercent: NutritionFieldParse.number(data['divergence_percent']),
      divergenceReason: NutritionFieldParse.nonEmptyString(
        data['divergence_reason'],
      ),
      source: NutritionFieldParse.nonEmptyString(data['source']),
      legacySource: NutritionFieldParse.nonEmptyString(data['legacy_source']),
      legacyId: NutritionFieldParse.nonEmptyString(data['legacy_id']),
      legacyAmountGrams: NutritionFieldParse.number(
        data['legacy_amount_grams'],
      ),
    );
  }
}

/// Parser canônico de documento `supplement_logs`.
abstract final class SupplementLogDocumentParser {
  SupplementLogDocumentParser._();

  static SupplementLog parse({
    required String id,
    required String dogId,
    required Map<String, Object?> data,
  }) {
    final name = NutritionFieldParse.nonEmptyString(data['supplement_name']);
    final dose = NutritionFieldParse.number(data['dose']);
    final unitParsed = SupplementDoseUnit.parse(data['unit']);
    final administeredAt = NutritionFieldParse.dateTime(
      data['administered_at'],
    );
    final recordedBy = NutritionFieldParse.recordedBy(data['recorded_by']);
    final schema = NutritionFieldParse.positiveInt(data['schema_version']);
    final revision = NutritionFieldParse.positiveInt(data['revision']);

    if (name == null) {
      throw const HealthDomainException(
        'missing_supplement_name',
        'supplement_name é obrigatório',
      );
    }
    if (dose == null) {
      throw const HealthDomainException('missing_dose', 'dose é obrigatória');
    }
    if (!unitParsed.isKnown || unitParsed.value == null) {
      throw HealthDomainException(
        'invalid_unit',
        'unit inválida: ${unitParsed.raw}',
      );
    }
    if (administeredAt == null) {
      throw const HealthDomainException(
        'missing_administered_at',
        'administered_at é obrigatório',
      );
    }
    if (recordedBy == null) {
      throw const HealthDomainException(
        'missing_recorded_by',
        'recorded_by é obrigatório',
      );
    }
    if (schema == null || schema <= 0) {
      throw const HealthDomainException(
        'invalid_schema_version',
        'schema_version inválido',
      );
    }
    if (revision == null || revision < 1) {
      throw const HealthDomainException(
        'invalid_revision',
        'revision inválido',
      );
    }

    return SupplementLog(
      id: id,
      dogId: dogId,
      supplementName: name,
      dose: dose,
      unit: unitParsed.value!,
      administeredAt: administeredAt,
      recordedBy: recordedBy,
      schemaVersion: schema,
      revision: revision,
      notes: NutritionFieldParse.nonEmptyString(data['notes']),
      batchNumber: NutritionFieldParse.nonEmptyString(data['batch_number']),
      protocolId: NutritionFieldParse.nonEmptyString(data['protocol_id']),
      nutritionPlanId: NutritionFieldParse.nonEmptyString(
        data['nutrition_plan_id'],
      ),
      supplementRegimenId: NutritionFieldParse.nonEmptyString(
        data['supplement_regimen_id'],
      ),
      legacySource: NutritionFieldParse.nonEmptyString(data['legacy_source']),
      legacyId: NutritionFieldParse.nonEmptyString(data['legacy_id']),
    );
  }
}
