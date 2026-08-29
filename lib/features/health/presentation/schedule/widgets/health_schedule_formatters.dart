import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_item_view.dart';
import 'package:canil_gcm/features/health/presentation/schedule/widgets/health_schedule_user_copy.dart';
import 'package:flutter/material.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';

/// Formatação e semântica visual da Agenda (sem regras temporais).
abstract final class HealthScheduleFormatters {
  static String statusLabel(HealthScheduleTemporalStatus status) =>
      switch (status) {
        HealthScheduleTemporalStatus.overdue =>
          HealthScheduleUserCopy.statusOverdue,
        HealthScheduleTemporalStatus.pending =>
          HealthScheduleUserCopy.statusPending,
        HealthScheduleTemporalStatus.today =>
          HealthScheduleUserCopy.statusToday,
        HealthScheduleTemporalStatus.upcoming =>
          HealthScheduleUserCopy.statusUpcoming,
        HealthScheduleTemporalStatus.scheduled =>
          HealthScheduleUserCopy.statusScheduled,
        HealthScheduleTemporalStatus.completed =>
          HealthScheduleUserCopy.statusCompleted,
        HealthScheduleTemporalStatus.cancelled =>
          HealthScheduleUserCopy.statusCancelled,
      };

  static Color statusColor(HealthScheduleTemporalStatus status) =>
      switch (status) {
        HealthScheduleTemporalStatus.overdue => AppTheme.error,
        HealthScheduleTemporalStatus.pending => AppTheme.warning,
        HealthScheduleTemporalStatus.today => AppTheme.primary,
        HealthScheduleTemporalStatus.upcoming => AppTheme.success,
        HealthScheduleTemporalStatus.scheduled => AppTheme.primary,
        HealthScheduleTemporalStatus.completed => AppTheme.success,
        HealthScheduleTemporalStatus.cancelled => AppTheme.textTertiary,
      };

  static IconData typeIcon(ScheduleType type) => switch (type) {
    ScheduleType.dose => Icons.medication_rounded,
    ScheduleType.vaccination => Icons.vaccines_rounded,
    ScheduleType.exam => Icons.biotech_rounded,
    ScheduleType.consultation => Icons.medical_services_rounded,
    ScheduleType.weighing => Icons.monitor_weight_rounded,
    ScheduleType.reevaluation => Icons.assignment_turned_in_rounded,
    ScheduleType.deworming => Icons.bug_report_rounded,
    ScheduleType.bath => Icons.shower_rounded,
    ScheduleType.general => Icons.event_note_rounded,
  };

  /// Labels canônicos amigáveis (Gate 5 / domínio).
  static String typeLabel(ScheduleType type) => switch (type) {
    ScheduleType.dose => 'Dose',
    ScheduleType.vaccination => 'Vacinação',
    ScheduleType.exam => 'Exame',
    ScheduleType.consultation => 'Consulta',
    ScheduleType.weighing => 'Pesagem',
    ScheduleType.reevaluation => 'Reavaliação',
    ScheduleType.deworming => 'Vermifugação',
    ScheduleType.bath => 'Banho',
    ScheduleType.general => 'Geral',
  };

  /// Data/hora de apresentação a partir de [scheduledFor] (UTC absoluto).
  static String whenLabel(
    HealthScheduleItemView item, {
    required DateTime now,
  }) {
    final local = item.scheduledFor.toLocal();
    final nowLocal = now.toLocal();
    final sameDay =
        local.year == nowLocal.year &&
        local.month == nowLocal.month &&
        local.day == nowLocal.day;
    final time =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    if (sameDay) return time;
    final date =
        '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}';
    return '$date · $time';
  }
}
