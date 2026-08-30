import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_query.dart';

/// Presets de período da timeline (limites inclusivos, 3A).
///
/// [now] deve ser injetado — nunca espalhar [DateTime.now] nos widgets.
enum HealthTimelinePeriodPreset {
  days7,
  days30,
  days90,
  months6,
  year1,
  allHistory,
  custom,
}

/// Resolução de presets relativos com relógio injetável.
///
/// ## Boundaries
/// - `start`: início do dia local (inclusivo);
/// - `end`: último microsegundo do dia local (inclusivo, alinhado a 3A).
///
/// ## 6 meses / 1 ano
/// Usam calendário (`DateTime` com month/year), não 183/365 dias fixos.
/// Dia 31 + subtração de mês segue a normalização do Dart (ex.: 31/ago − 6m).
abstract final class HealthTimelinePeriodPresets {
  HealthTimelinePeriodPresets._();

  static DateTime startOfLocalDay(DateTime reference) {
    final local = reference.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  /// Fim inclusivo do dia local (23:59:59.999999).
  static DateTime endOfLocalDay(DateTime reference) {
    final local = reference.toLocal();
    return DateTime(local.year, local.month, local.day, 23, 59, 59, 999, 999);
  }

  static HealthTimelinePeriod resolve(
    HealthTimelinePeriodPreset preset, {
    required DateTime now,
    HealthTimelinePeriod? customPeriod,
  }) {
    // Uma única referência temporal por resolve.
    final anchor = now;
    switch (preset) {
      case HealthTimelinePeriodPreset.allHistory:
        return HealthTimelinePeriod();
      case HealthTimelinePeriodPreset.custom:
        if (customPeriod == null) {
          throw ArgumentError(
            'customPeriod é obrigatório para preset personalizado',
          );
        }
        return customPeriod;
      case HealthTimelinePeriodPreset.days7:
        return _relativeDays(anchor, 7);
      case HealthTimelinePeriodPreset.days30:
        return _relativeDays(anchor, 30);
      case HealthTimelinePeriodPreset.days90:
        return _relativeDays(anchor, 90);
      case HealthTimelinePeriodPreset.months6:
        return _relativeCalendarMonths(anchor, 6);
      case HealthTimelinePeriodPreset.year1:
        return _relativeCalendarMonths(anchor, 12);
    }
  }

  static HealthTimelinePeriod _relativeDays(DateTime now, int days) {
    final end = endOfLocalDay(now);
    final start = startOfLocalDay(now).subtract(Duration(days: days - 1));
    return HealthTimelinePeriod(start: start, end: end);
  }

  /// Subtrai [months] calendário do início do dia de [now].
  static HealthTimelinePeriod _relativeCalendarMonths(
    DateTime now,
    int months,
  ) {
    final end = endOfLocalDay(now);
    final dayStart = startOfLocalDay(now);
    final start = DateTime(
      dayStart.year,
      dayStart.month - months,
      dayStart.day,
    );
    return HealthTimelinePeriod(start: startOfLocalDay(start), end: end);
  }

  static String? validateCustom({DateTime? start, DateTime? end}) {
    if (start == null || end == null) {
      return 'Informe a data inicial e a data final.';
    }
    final s = startOfLocalDay(start);
    final e = startOfLocalDay(end);
    if (s.isAfter(e)) {
      return 'A data inicial não pode ser posterior à data final.';
    }
    return null;
  }

  static HealthTimelinePeriod customInclusive({
    required DateTime start,
    required DateTime end,
  }) {
    final error = validateCustom(start: start, end: end);
    if (error != null) {
      throw ArgumentError(error);
    }
    return HealthTimelinePeriod(
      start: startOfLocalDay(start),
      end: endOfLocalDay(end),
    );
  }
}
