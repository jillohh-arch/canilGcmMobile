import 'package:flutter/material.dart';

/// Modelo de dados para um selo de conformidade profissional.
/// Usado pelo SealDetailSheet para exibir detalhes contextualizados.
class SealData {
  final String id;
  final String name;
  final bool isActive;
  final String subtitle;
  final IconData icon;

  // Campos para selos ATIVOS
  final String? criterion;
  final String? activity;
  final String? howToMaintain;

  // Campos para selos INATIVOS
  final String? currentState;
  final String? requiredAction;
  final String? actionButtonLabel;
  final String? actionRoute;

  const SealData({
    required this.id,
    required this.name,
    required this.isActive,
    required this.subtitle,
    required this.icon,
    this.criterion,
    this.activity,
    this.howToMaintain,
    this.currentState,
    this.requiredAction,
    this.actionButtonLabel,
    this.actionRoute,
  });
}
