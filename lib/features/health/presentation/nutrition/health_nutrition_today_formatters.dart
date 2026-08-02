import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';
import 'package:canil_gcm/features/health/domain/meal_occurrence.dart';
import 'package:canil_gcm/features/health/domain/meal_schedule_slot.dart';
import 'package:canil_gcm/features/health/domain/nutrition_read_models.dart';
import 'package:canil_gcm/features/health/domain/nutrition_read_state.dart';
import 'package:intl/intl.dart';

/// Copy e formatação de apresentação — Nutrição Hoje (Gate 5B).
/// Sem write. Sem inventar slots/legados.
abstract final class HealthNutritionTodayFormatters {
  HealthNutritionTodayFormatters._();

  static String periodLabel(ParsedHealthEnum<MealPeriod> period) {
    if (period.isKnown && period.value != null) {
      return switch (period.value!) {
        MealPeriod.morning => 'Manhã',
        MealPeriod.afternoon => 'Almoço',
        MealPeriod.evening => 'Tarde',
        MealPeriod.night => 'Noite',
        MealPeriod.extra => 'Extra',
      };
    }
    if (period.isUnknown) return period.raw ?? 'Período';
    return 'Período';
  }

  static String acceptanceLabel(ParsedHealthEnum<MealAcceptance> acceptance) {
    if (acceptance.isKnown && acceptance.value != null) {
      return switch (acceptance.value!) {
        MealAcceptance.full => 'Aceitou tudo',
        MealAcceptance.partial => 'Aceitação parcial',
        MealAcceptance.refused => 'Recusou',
        MealAcceptance.unknown => 'Não informado',
      };
    }
    if (acceptance.isUnknown) return 'Não informado';
    return 'Não informado';
  }

  static String grams(num? value) {
    if (value == null) return '—';
    if (!value.isFinite) return '—';
    final rounded = value.round();
    return '$rounded g';
  }

  /// Consumido desconhecido ≠ zero.
  ///
  /// - sem refeições → `null` (nada a somar)
  /// - todas com `consumedGrams == null` → `null`
  /// - mistura: soma só os conhecidos e marca [hasUnknownConsumed]
  static ({double? knownSum, bool hasUnknownConsumed, bool hasAnyMeal})
  consumedAggregation(Iterable<NutritionMealReadItem> meals) {
    var known = 0.0;
    var anyKnown = false;
    var anyUnknown = false;
    var count = 0;
    for (final item in meals) {
      count++;
      final c = item.meal.consumedGrams;
      if (c == null) {
        anyUnknown = true;
      } else if (c.isFinite) {
        anyKnown = true;
        known += c;
      } else {
        anyUnknown = true;
      }
    }
    return (
      knownSum: anyKnown ? known : null,
      hasUnknownConsumed: anyUnknown,
      hasAnyMeal: count > 0,
    );
  }

  static double offeredSum(Iterable<NutritionMealReadItem> meals) {
    var sum = 0.0;
    for (final item in meals) {
      final o = item.meal.offeredGrams;
      if (o.isFinite && o > 0) sum += o;
    }
    return sum;
  }

  static String dateShort(DateTime instant, {required String timezone}) {
    final date = LocalServiceDate.fromInstant(instant, timezone: timezone);
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  static String timeShort(DateTime instant, {required String timezone}) {
    final d = LocalServiceDate.instantInTimezone(instant, timezone: timezone);
    return DateFormat('HH:mm').format(d);
  }

  /// Contexto temporal inequívoco usando a mesma data civil do read model.
  static String recentDateTimeLabel({
    required DateTime instant,
    required String serviceDate,
    required String timezone,
  }) {
    final itemDate = LocalServiceDate.fromInstant(instant, timezone: timezone);
    final service = LocalServiceDate.fromIso(serviceDate);
    final local = LocalServiceDate.instantInTimezone(
      instant,
      timezone: timezone,
    );
    final time = DateFormat('HH:mm').format(local);
    if (itemDate == service) return 'Hoje · $time';

    final yesterday = DateTime.utc(
      service.year,
      service.month,
      service.day,
    ).subtract(const Duration(days: 1));
    final yesterdayIso =
        '${yesterday.year.toString().padLeft(4, '0')}-'
        '${yesterday.month.toString().padLeft(2, '0')}-'
        '${yesterday.day.toString().padLeft(2, '0')}';
    if (itemDate == LocalServiceDate.fromIso(yesterdayIso)) {
      return 'Ontem · $time';
    }
    return '${itemDate.day.toString().padLeft(2, '0')}/'
        '${itemDate.month.toString().padLeft(2, '0')} · $time';
  }

  static String originBadge(NutritionDataOrigin origin) {
    return switch (origin) {
      NutritionDataOrigin.canonical => 'Canônico',
      NutritionDataOrigin.legacy => 'Registro legado',
      NutritionDataOrigin.legacyFeedingEvents => 'Registro legado',
      NutritionDataOrigin.legacyFeedings => 'Registro legado',
    };
  }

  static String planSourceLabel(NutritionActivePlanRef? plan) {
    return switch (plan) {
      NutritionActiveCanonicalPlan() => 'Plano alimentar ativo',
      NutritionActiveLegacyPlan() => 'Dados do plano anterior',
      NutritionActivePlanIntegrityConflict() => 'Integridade do plano',
      null => 'Plano alimentar',
    };
  }

  static String foodTypeOf(NutritionActivePlanRef? plan) {
    return switch (plan) {
      NutritionActiveCanonicalPlan(:final plan) => plan.foodType,
      NutritionActiveLegacyPlan(:final view) => view.foodType,
      _ => '—',
    };
  }

  static String? planNotes(NutritionActivePlanRef? plan) {
    return switch (plan) {
      NutritionActiveCanonicalPlan(:final plan) => plan.specialInstructions,
      NutritionActiveLegacyPlan(:final view) => view.notes,
      _ => null,
    };
  }

  static String? responsibleName(NutritionActivePlanRef? plan) {
    return switch (plan) {
      NutritionActiveCanonicalPlan(:final plan) => plan.recordedBy.name,
      NutritionActiveLegacyPlan(:final view) => view.professionalName,
      _ => null,
    };
  }
}

/// Status de slot para UI (derivado; nunca persistido).
enum NutritionTodaySlotUiStatus { pending, late, completed }

abstract final class NutritionTodaySlotUi {
  NutritionTodaySlotUi._();

  /// Completa se há meal com plannedMealId; late se pending e horário civil passou.
  static NutritionTodaySlotUiStatus statusFor({
    required MealScheduleSlot slot,
    required NutritionMealReadItem? meal,
    required DateTime serverNow,
    required String timezone,
  }) {
    if (meal != null) return NutritionTodaySlotUiStatus.completed;
    // Late: comparação civil simples HH:mm vs agora no TZ do plano.
    // Sem inventar occurrence; só apresentação.
    final parts = slot.scheduledTime.value.split(':');
    if (parts.length < 2) return NutritionTodaySlotUiStatus.pending;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return NutritionTodaySlotUiStatus.pending;
    final local = LocalServiceDate.instantInTimezone(
      serverNow,
      timezone: timezone,
    );
    final nowMinutes = local.hour * 60 + local.minute;
    final slotMinutes = h * 60 + m;
    if (nowMinutes > slotMinutes) return NutritionTodaySlotUiStatus.late;
    return NutritionTodaySlotUiStatus.pending;
  }

  static String label(NutritionTodaySlotUiStatus s) => switch (s) {
    NutritionTodaySlotUiStatus.pending => 'Pendente',
    NutritionTodaySlotUiStatus.late => 'Atrasada',
    NutritionTodaySlotUiStatus.completed => 'Concluída',
  };
}
