import 'package:flutter/material.dart';

/// Seções internas oficiais do shell Health v1.0.
///
/// Ordem e labels fixos conforme arquitetura e mockup 01.
enum HealthShellSection {
  resumo,
  historico,
  agenda,
  nutricao;

  /// Ordem de exibição da navegação.
  static const List<HealthShellSection> navigationOrder = [
    HealthShellSection.resumo,
    HealthShellSection.historico,
    HealthShellSection.agenda,
    HealthShellSection.nutricao,
  ];

  String get label {
    switch (this) {
      case HealthShellSection.resumo:
        return 'Resumo';
      case HealthShellSection.historico:
        return 'Histórico';
      case HealthShellSection.agenda:
        return 'Agenda';
      case HealthShellSection.nutricao:
        return 'Nutrição';
    }
  }

  IconData get icon {
    switch (this) {
      case HealthShellSection.resumo:
        return Icons.bar_chart_rounded;
      case HealthShellSection.historico:
        return Icons.history_rounded;
      case HealthShellSection.agenda:
        return Icons.calendar_today_outlined;
      case HealthShellSection.nutricao:
        return Icons.restaurant_rounded;
    }
  }

  int get navigationIndex => navigationOrder.indexOf(this);

  static HealthShellSection fromNavigationIndex(int index) {
    if (index < 0 || index >= navigationOrder.length) {
      return HealthShellSection.resumo;
    }
    return navigationOrder[index];
  }
}
