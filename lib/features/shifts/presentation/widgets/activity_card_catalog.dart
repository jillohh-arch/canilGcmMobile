import 'package:flutter/material.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/core/domain/activity_subtype_ids.dart';

abstract final class ActivityCardCatalog {
  static const occurrenceCards = [
    {
      'id': ActivitySubtypeIds.detection,
      'image': 'assets/images/card_deteccao.png',
      'glow': AppTheme.attention,
    },
    {
      'id': ActivitySubtypeIds.supportVehicle,
      'image': 'assets/images/card_apoio.png',
      'glow': AppTheme.attention,
    },
    {
      'id': ActivitySubtypeIds.missingPerson,
      'image': 'assets/images/card_busca_captura.png',
      'glow': AppTheme.error,
    },
    {
      'id': ActivitySubtypeIds.serviceOrder,
      'image': 'assets/images/card_ordem_servico.png',
      'glow': AppTheme.textMuted,
    },
    {
      'id': ActivitySubtypeIds.event,
      'image': 'assets/images/card_palestras.png',
      'glow': AppTheme.success,
    },
    {
      'id': ActivitySubtypeIds.other,
      'image': 'assets/images/card_outros.png',
      'glow': AppTheme.textSecondary,
    },
  ];

  static const trainingCards = [
    {
      'id': ActivitySubtypeIds.obedience,
      'image': 'assets/images/card_obediencia.png',
      'glow': AppTheme.info,
    },
    {
      'id': ActivitySubtypeIds.scentWork,
      'image': 'assets/images/card_faro.png',
      'glow': AppTheme.attention,
    },
    {
      'id': ActivitySubtypeIds.guardProtection,
      'image': 'assets/images/card_protecao.png',
      'glow': AppTheme.error,
    },
    {
      'id': ActivitySubtypeIds.searchCapture,
      'image': 'assets/images/card_treino_busca.png',
      'glow': AppTheme.success,
    },
    {
      'id': ActivitySubtypeIds.physicalConditioning,
      'image': 'assets/images/card_condicionamento.png',
      'glow': AppTheme.primary,
    },
  ];

  static const healthCards = [
    {
      'id': ActivitySubtypeIds.consultation,
      'image': 'assets/images/card_consulta.png',
      'glow': AppTheme.primary,
    },
    {
      'id': ActivitySubtypeIds.vaccine,
      'image': 'assets/images/card_vacina.png',
      'glow': AppTheme.info,
    },
    {
      'id': ActivitySubtypeIds.exam,
      'image': 'assets/images/card_exame.png',
      'glow': AppTheme.healthAccent,
    },
    {
      'id': ActivitySubtypeIds.bath,
      'image': 'assets/images/card_banho.png',
      'glow': AppTheme.primary,
    },
  ];

  static List<Map<String, dynamic>> forCategory(String category) {
    if (category == 'Treino') return trainingCards;
    if (category == 'Saude') return healthCards;
    return occurrenceCards;
  }

  static Map<String, dynamic>? findById({
    required String category,
    required String? id,
  }) {
    if (id == null) return null;
    for (final card in forCategory(category)) {
      if (card['id'] == id) {
        return card;
      }
    }
    return null;
  }

  static String? imageFor({required String category, required String? id}) {
    return findById(category: category, id: id)?['image'] as String?;
  }

  static Color glowFor({
    required String category,
    required String? id,
    required Color fallback,
  }) {
    final glow = findById(category: category, id: id)?['glow'];
    return glow is Color ? glow : fallback;
  }
}
