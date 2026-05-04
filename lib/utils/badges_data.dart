import 'package:flutter/material.dart';

class BadgeData {
  final String id;
  final String name;
  final String description;
  final IconData icon;
  final Color color;

  const BadgeData({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.color,
  });
}

class BadgesConfig {
  static const List<BadgeData> badges = [
    BadgeData(
      id: 'pe_na_estrada',
      name: 'Pé na Estrada',
      description: 'Atribuído ao assumir seu primeiro plantão com um K9.',
      icon: Icons.directions_walk_rounded,
      color: Colors.blueAccent,
    ),
    BadgeData(
      id: 'faro_afiado',
      name: 'Faro Afiado',
      description:
          'Atribuído ao realizar a primeira apreensão registrada com sucesso.',
      icon: Icons.search_rounded,
      color: Colors.orangeAccent,
    ),
    BadgeData(
      id: 'guardiao',
      name: 'Guardião K9',
      description:
          'Concedido ao manter a prontidão operacional de seu cão acima de 90% por 30 dias contínuos.',
      icon: Icons.shield_rounded,
      color: Colors.greenAccent,
    ),
    BadgeData(
      id: 'faro_de_elite',
      name: 'Faro de Elite',
      description:
          'Registrar 10 ocorrências com apreensão positiva, onde o cão indicou e o material foi localizado.',
      icon: Icons.track_changes_rounded,
      color: Colors.amber,
    ),
    BadgeData(
      id: 'binomio_de_ferro',
      name: 'Binômio de Ferro',
      description:
          'Concedido ao completar 30 turnos registrados com K9 no sistema.',
      icon: Icons.handshake_rounded,
      color: Color(0xFF9E9E9E),
    ),
    BadgeData(
      id: 'mestre_do_adestramento',
      name: 'Mestre do Adestramento',
      description:
          'Concedido ao acumular 50 horas de treinamento registradas no sistema.',
      icon: Icons.psychology_rounded,
      color: Color(0xFFCD7F32),
    ),
    BadgeData(
      id: 'sentinela_da_saude',
      name: 'Sentinela da Saúde',
      description:
          'Concedido ao manter a barra de prontidão operacional acima de 95% por 90 dias consecutivos.',
      icon: Icons.health_and_safety_rounded,
      color: Colors.lightBlueAccent,
    ),
    BadgeData(
      id: 'rastro_perfeito',
      name: 'Rastro Perfeito',
      description:
          'Concedido ao concluir com sucesso 3 missões de busca e captura em que o cão foi determinante.',
      icon: Icons.explore_rounded,
      color: Color(0xFF556B2F),
    ),
  ];

  static List<BadgeData> getUserBadges(List<String> userBadgeIds) {
    return badges.where((badge) => userBadgeIds.contains(badge.id)).toList();
  }

  static BadgeData? getById(String badgeId) {
    for (final badge in badges) {
      if (badge.id == badgeId) {
        return badge;
      }
    }
    return null;
  }
}
