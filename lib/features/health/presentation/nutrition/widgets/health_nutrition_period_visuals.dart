import 'package:flutter/material.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';
import 'package:canil_gcm/features/health/presentation/nutrition/health_nutrition_today_formatters.dart';

/// Identidade visual LOCAL da Nutrição — cor e ícone por faixa do dia.
///
/// Escopo deliberadamente local: `health_timeline_type_visuals.dart` (timeline
/// clínica global) NÃO é alterado. Alimentação e suplemento continuam
/// compartilhando `AppTheme.attention` lá, e o dashboard segue contratado a ele.
///
/// AUTORIDADE: nada aqui decide período. O período é o valor PERSISTIDO
/// (`MealScheduleSlot.period` / `meal.period`). Este arquivo apenas agrupa
/// valores existentes para apresentação. O relógio não participa.
enum HealthNutritionPeriodGroup { morning, afternoon, night, extra, supplement }

/// Cor + ícone + rótulo de uma faixa visual.
@immutable
class HealthNutritionPeriodVisual {
  const HealthNutritionPeriodVisual({
    required this.label,
    required this.icon,
    required this.accent,
  });

  final String label;
  final IconData icon;
  final Color accent;
}

abstract final class HealthNutritionPeriodVisuals {
  HealthNutritionPeriodVisuals._();

  /// Índigo próprio da Noite.
  ///
  /// Não reusa `AppTheme.info`: azul informativo já significa "pesagem /
  /// observação" no Health. Um tom deslocado evita que a Noite seja lida como
  /// categoria clínica.
  static const Color nightAccent = Color(0xFF6C8DEA);

  /// Verde próprio do Suplemento.
  ///
  /// Não reusa `AppTheme.success`: verde de sucesso significa "Concluída" no
  /// badge de status, e o quadrante precisa ser distinguível do próprio estado
  /// que ele exibe. Este tom puxa para esmeralda.
  static const Color supplementAccent = Color(0xFF2FC98B);

  /// Agrupamento de apresentação.
  ///
  /// `evening` e `night` colapsam em Noite — é a convenção de produto aprovada.
  /// O enum de domínio permanece com cinco valores; nada é reescrito.
  /// Período desconhecido/ausente NÃO é forçado a uma faixa: retorna `extra`,
  /// que é renderizado fora do grid preservando o rótulo bruto.
  static HealthNutritionPeriodGroup groupFor(
    ParsedHealthEnum<MealPeriod> period,
  ) {
    if (!period.isKnown || period.value == null) {
      return HealthNutritionPeriodGroup.extra;
    }
    return switch (period.value!) {
      MealPeriod.morning => HealthNutritionPeriodGroup.morning,
      MealPeriod.afternoon => HealthNutritionPeriodGroup.afternoon,
      MealPeriod.evening => HealthNutritionPeriodGroup.night,
      MealPeriod.night => HealthNutritionPeriodGroup.night,
      MealPeriod.extra => HealthNutritionPeriodGroup.extra,
    };
  }

  static HealthNutritionPeriodVisual resolve(HealthNutritionPeriodGroup group) {
    return switch (group) {
      HealthNutritionPeriodGroup.morning => const HealthNutritionPeriodVisual(
        label: 'Manhã',
        icon: Icons.wb_twilight_rounded,
        accent: AppTheme.amber,
      ),
      HealthNutritionPeriodGroup.afternoon => const HealthNutritionPeriodVisual(
        label: 'Tarde',
        icon: Icons.wb_sunny_rounded,
        accent: AppTheme.attention,
      ),
      HealthNutritionPeriodGroup.night => const HealthNutritionPeriodVisual(
        label: 'Noite',
        icon: Icons.nightlight_round,
        accent: nightAccent,
      ),
      HealthNutritionPeriodGroup.extra => const HealthNutritionPeriodVisual(
        label: 'Extra',
        icon: Icons.more_time_rounded,
        accent: AppTheme.textSecondary,
      ),
      HealthNutritionPeriodGroup.supplement =>
        const HealthNutritionPeriodVisual(
          label: 'Suplemento',
          icon: Icons.medication_rounded,
          accent: supplementAccent,
        ),
    };
  }

  /// Rótulo de apresentação de um período persistido.
  ///
  /// Harmoniza a divergência que existia entre a tela (`afternoon` → "Almoço",
  /// `evening` → "Tarde") e o formulário de registro (`afternoon` → "Tarde",
  /// `evening` → "Noite"). A derivação por hora do formulário
  /// (`18–22h → evening`) confirma que "Noite" é a leitura correta de `evening`.
  ///
  /// Valor desconhecido continua ecoado verbatim por
  /// [HealthNutritionTodayFormatters.periodLabel] — não coagimos para uma faixa.
  static String labelFor(ParsedHealthEnum<MealPeriod> period) {
    if (!period.isKnown || period.value == null) {
      return HealthNutritionTodayFormatters.periodLabel(period);
    }
    return resolve(groupFor(period)).label;
  }

  /// Acento de um período persistido, para timeline e cards de registro.
  static Color accentFor(ParsedHealthEnum<MealPeriod> period) =>
      resolve(groupFor(period)).accent;

  /// Ícone de um período persistido.
  static IconData iconFor(ParsedHealthEnum<MealPeriod> period) =>
      resolve(groupFor(period)).icon;
}
