import 'package:flutter/material.dart';

import 'occurrence_quick_action.dart';

class OccurrenceQuickActionCatalog {
  const OccurrenceQuickActionCatalog._();

  static List<OccurrenceQuickAction> primaryActions({
    required Color amber,
    required Color green,
    required Color cyan,
  }) {
    return [
      OccurrenceQuickAction(
        title: 'Abordagem feita',
        description: 'Pessoa ou veículo abordado no local.',
        icon: Icons.person_search_rounded,
        color: amber,
        assetPath: 'assets/images/actions/k9_abordagem.png',
      ),
      OccurrenceQuickAction(
        title: 'Cão em ação',
        description: 'K9 empregado em varredura operacional.',
        icon: Icons.pets_rounded,
        color: cyan,
        assetPath: 'assets/images/actions/k9_emprego.png',
      ),
      OccurrenceQuickAction(
        title: 'Busca feita',
        description: 'Busca realizada pela equipe no ponto indicado.',
        icon: Icons.search_rounded,
        color: green,
        assetPath: 'assets/images/actions/k9_busca.png',
      ),
      const OccurrenceQuickAction(
        title: 'Material localizado',
        description: 'Material localizado pela equipe.',
        icon: Icons.inventory_2_rounded,
        color: Color(0xFF9B5CFF),
        assetPath: 'assets/images/actions/k9_materialEncontrado.png',
        options: [
          OccurrenceQuickAction(
            title: 'Entorpecente localizado',
            description: 'Entorpecente localizado, aguardando quantificação.',
            icon: Icons.science_rounded,
            color: Color(0xFF9B5CFF),
          ),
          OccurrenceQuickAction(
            title: 'Arma localizada',
            description: 'Arma localizada durante a ocorrência.',
            icon: Icons.gps_fixed_rounded,
            color: Color(0xFFFF3B5C),
          ),
          OccurrenceQuickAction(
            title: 'Munição localizada',
            description: 'Munição localizada durante a ocorrência.',
            icon: Icons.adjust_rounded,
            color: Color(0xFFFFB84D),
          ),
          OccurrenceQuickAction(
            title: 'Objeto ilícito localizado',
            description: 'Objeto ilícito localizado durante a averiguação.',
            icon: Icons.inventory_2_rounded,
            color: Color(0xFF00E5FF),
          ),
        ],
      ),
      const OccurrenceQuickAction(
        title: 'Parte conduzida',
        description: 'Parte conduzida para providências posteriores.',
        icon: Icons.person_rounded,
        color: Color(0xFFFF8A3D),
        assetPath: 'assets/images/actions/k9_parteConduzida.png',
      ),
      const OccurrenceQuickAction(
        title: 'Sem alteração',
        description: 'Nada ilícito localizado ou constatado no local.',
        icon: Icons.cancel_rounded,
        color: Colors.white54,
        assetPath: 'assets/images/actions/k9_naoConstatado.png',
      ),
    ];
  }
}
