import 'package:flutter/material.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/domain/health_v1_value_objects.dart';

/// Formatadores de apresentação da timeline (sem regras clínicas).
abstract final class HealthTimelineFormatters {
  HealthTimelineFormatters._();

  static const _monthLabels = <String>[
    'JAN',
    'FEV',
    'MAR',
    'ABR',
    'MAI',
    'JUN',
    'JUL',
    'AGO',
    'SET',
    'OUT',
    'NOV',
    'DEZ',
  ];

  /// Label de grupo de dia: `HOJE`, `ONTEM` ou `15 JUL 2026`.
  ///
  /// [day] deve ser meia-noite local (como em [HealthTimelineDayGroup.date]).
  /// [now] é injetável para testes (timezone local do device).
  static String dayGroupLabel(DateTime day, {DateTime? now}) {
    final reference = (now ?? DateTime.now()).toLocal();
    final today = DateTime(reference.year, reference.month, reference.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final localDay = DateTime(day.year, day.month, day.day);

    if (localDay == today) return 'HOJE';
    if (localDay == yesterday) return 'ONTEM';

    final dd = localDay.day.toString().padLeft(2, '0');
    final mon = _monthLabels[localDay.month - 1];
    return '$dd $mon ${localDay.year}';
  }

  /// Horário local `HH:mm`.
  static String timeOfDay(DateTime at) {
    final local = at.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  /// Label de adendos: `Adendo registrado` / `2 adendos`.
  static String? amendmentsLabel({
    required bool hasAmendments,
    required int amendmentCount,
  }) {
    if (!hasAmendments || amendmentCount <= 0) return null;
    if (amendmentCount == 1) return 'Adendo registrado';
    return '$amendmentCount adendos';
  }

  /// Label de anexos: `1 anexo` / `2 anexos`.
  static String? attachmentsLabel({
    required bool hasAttachments,
    int? attachmentCount,
  }) {
    if (!hasAttachments) return null;
    final count = attachmentCount;
    if (count == null || count <= 0) return 'Anexo';
    if (count == 1) return '1 anexo';
    return '$count anexos';
  }

  /// Prefixo de quem registrou no sistema.
  ///
  /// Retorna `null` se [name] for vazio — evita "Registrado por" órfão.
  static String? recordedByLabel(String name) {
    final t = name.trim();
    if (t.isEmpty) return null;
    return 'Registrado por $t';
  }

  /// Contagem visual de filtros: nunca negativa; `null` → 0.
  static int normalizeFilterCount(int? count) {
    if (count == null) return 0;
    if (count < 0) return 0;
    return count;
  }

  /// Texto de impacto operacional a partir do contrato de domínio.
  ///
  /// Escala oficial: `none | low | medium | high | critical`
  /// ([OperationalImpactLevel] — Domain Model §5).
  /// [OperationalImpactLevel.none] não deve ser renderizado pela UI.
  /// Label de nível é tradução 1:1 do enum; description é o texto canônico.
  static String operationalImpactLabel(OperationalImpact impact) {
    final description = impact.description.trim();
    final levelLabel = switch (impact.level) {
      OperationalImpactLevel.none => null,
      OperationalImpactLevel.low => 'baixo',
      OperationalImpactLevel.medium => 'médio',
      OperationalImpactLevel.high => 'alto',
      OperationalImpactLevel.critical => 'crítico',
    };
    if (levelLabel == null) return description;
    if (description.isEmpty) return 'Impacto $levelLabel';
    return 'Impacto $levelLabel · $description';
  }

  static Color operationalImpactColor(OperationalImpactLevel level) {
    return switch (level) {
      OperationalImpactLevel.none => AppTheme.textMuted,
      OperationalImpactLevel.low => AppTheme.warningAccent,
      OperationalImpactLevel.medium => AppTheme.attention,
      OperationalImpactLevel.high => AppTheme.error,
      OperationalImpactLevel.critical => AppTheme.errorStrong,
    };
  }
}
