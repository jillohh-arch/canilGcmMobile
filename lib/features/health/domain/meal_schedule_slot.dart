import 'health_v1_enums.dart';
import 'health_v1_models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MealScheduleSlot — slot estável de NutritionPlan.meal_schedule (D5 / D41).
// Identidade = [id] na versão do plano — NÃO o índice do array.
// ─────────────────────────────────────────────────────────────────────────────

/// Horário local do slot no timezone do plano (`"HH:mm"`).
final class ScheduledTimeOfDay {
  ScheduledTimeOfDay(String raw) : value = _normalize(raw);

  final String value;

  int get hour => int.parse(value.substring(0, 2));
  int get minute => int.parse(value.substring(3, 5));

  static final RegExp _pattern = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$');

  static String _normalize(String raw) {
    final trimmed = raw.trim();
    if (!_pattern.hasMatch(trimmed)) {
      throw HealthDomainException(
        'invalid_scheduled_time',
        'scheduled_time deve ser HH:mm (00:00–23:59); recebido "$raw"',
      );
    }
    return trimmed;
  }

  @override
  bool operator ==(Object other) =>
      other is ScheduledTimeOfDay && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// Slot de refeição planejada dentro de um [NutritionPlan].
final class MealScheduleSlot {
  MealScheduleSlot({
    required String id,
    required this.period,
    required this.scheduledTime,
    required num targetGrams,
  }) : id = _requireId(id),
       targetGrams = targetGrams.toDouble() {
    if (period.isAbsent) {
      throw const HealthDomainException(
        'missing_meal_period',
        'meal_schedule.period é obrigatório',
      );
    }
    if (!this.targetGrams.isFinite || this.targetGrams <= 0) {
      throw const HealthDomainException(
        'invalid_target_grams',
        'meal_schedule.target_grams deve ser finito e maior que zero',
      );
    }
  }

  final String id;

  /// Período do slot — known ou unknown preservado (nunca fallback silencioso).
  final ParsedHealthEnum<MealPeriod> period;
  final ScheduledTimeOfDay scheduledTime;
  final double targetGrams;

  static String _requireId(String id) {
    final trimmed = id.trim();
    if (trimmed.isEmpty) {
      throw const HealthDomainException(
        'missing_meal_schedule_slot_id',
        'meal_schedule.id é obrigatório e deve ser estável',
      );
    }
    return trimmed;
  }

  @override
  bool operator ==(Object other) =>
      other is MealScheduleSlot &&
      other.id == id &&
      other.period == period &&
      other.scheduledTime == scheduledTime &&
      other.targetGrams == targetGrams;

  @override
  int get hashCode => Object.hash(id, period, scheduledTime, targetGrams);
}
