import 'package:flutter/material.dart';

import 'occurrence_event_category.dart';
import 'occurrence_quick_action.dart';

class OccurrenceEventCatalog {
  const OccurrenceEventCatalog._();

  static List<OccurrenceEventCategory> categories(Color accent) {
    return [
      OccurrenceEventCategory(
        title: 'Geral',
        icon: Icons.star_rounded,
        color: accent,
        actions: [
          OccurrenceQuickAction(
            title: 'Averiguação de denúncia',
            description: 'Denúncia averiguada pela equipe.',
            icon: Icons.campaign_rounded,
            color: accent,
          ),
          OccurrenceQuickAction(
            title: 'Local já vistoriado',
            description: 'Local vistoriado sem alteração aparente.',
            icon: Icons.fact_check_rounded,
            color: accent,
          ),
          OccurrenceQuickAction(
            title: 'Guarnição em espera',
            description: 'Equipe aguardando novas orientações.',
            icon: Icons.hourglass_bottom_rounded,
            color: accent,
          ),
          OccurrenceQuickAction(
            title: 'Apoio a outra equipe',
            description: 'Apoio prestado a outra equipe no local.',
            icon: Icons.groups_rounded,
            color: accent,
          ),
        ],
      ),
      const OccurrenceEventCategory(
        title: 'Abordagem',
        icon: Icons.person_search_rounded,
        color: Color(0xFFFFB84D),
        actions: [
          OccurrenceQuickAction(
            title: 'Veículo abordado',
            description: 'Veículo abordado durante a ocorrência.',
            icon: Icons.directions_car_rounded,
            color: Color(0xFFFFB84D),
          ),
          OccurrenceQuickAction(
            title: 'Pessoa identificada',
            description: 'Pessoa identificada pela equipe.',
            icon: Icons.badge_rounded,
            color: Color(0xFFFFB84D),
          ),
          OccurrenceQuickAction(
            title: 'Documento verificado',
            description: 'Documento consultado ou verificado.',
            icon: Icons.assignment_ind_rounded,
            color: Color(0xFFFFB84D),
          ),
          OccurrenceQuickAction(
            title: 'Revista pessoal',
            description: 'Revista pessoal realizada pela equipe.',
            icon: Icons.accessibility_new_rounded,
            color: Color(0xFFFFB84D),
          ),
        ],
      ),
      const OccurrenceEventCategory(
        title: 'Busca / Cão',
        icon: Icons.pets_rounded,
        color: Color(0xFF00F5A0),
        actions: [
          OccurrenceQuickAction(
            title: 'Cão em ação',
            description: 'K9 empregado em varredura operacional.',
            icon: Icons.pets_rounded,
            color: Color(0xFF00F5A0),
          ),
          OccurrenceQuickAction(
            title: 'Busca iniciada',
            description: 'Busca iniciada pela equipe no local.',
            icon: Icons.search_rounded,
            color: Color(0xFF00F5A0),
          ),
          OccurrenceQuickAction(
            title: 'Indicação positiva',
            description: 'K9 apresentou indicação positiva.',
            icon: Icons.check_circle_rounded,
            color: Color(0xFF00F5A0),
          ),
          OccurrenceQuickAction(
            title: 'Busca sem êxito',
            description: 'Busca encerrada sem localização de ilícitos.',
            icon: Icons.cancel_rounded,
            color: Color(0xFF00F5A0),
          ),
        ],
      ),
      const OccurrenceEventCategory(
        title: 'Material',
        icon: Icons.inventory_2_rounded,
        color: Color(0xFF9B5CFF),
        actions: [
          OccurrenceQuickAction(
            title: 'Material localizado',
            description: 'Material localizado durante a averiguação.',
            icon: Icons.inventory_2_rounded,
            color: Color(0xFF9B5CFF),
          ),
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
            title: 'Objeto apreendido',
            description: 'Objeto apreendido ou preservado pela equipe.',
            icon: Icons.archive_rounded,
            color: Color(0xFF9B5CFF),
          ),
        ],
      ),
      const OccurrenceEventCategory(
        title: 'Encaminhamento',
        icon: Icons.local_hospital_rounded,
        color: Color(0xFFFF3B5C),
        actions: [
          OccurrenceQuickAction(
            title: 'Parte conduzida',
            description: 'Parte conduzida para providências posteriores.',
            icon: Icons.person_rounded,
            color: Color(0xFFFF8A3D),
          ),
          OccurrenceQuickAction(
            title: 'Encaminhado à Santa Casa',
            description: 'Parte encaminhada à Santa Casa para atendimento.',
            icon: Icons.local_hospital_rounded,
            color: Color(0xFFFF3B5C),
          ),
          OccurrenceQuickAction(
            title: 'Encaminhado à UPA',
            description: 'Parte encaminhada à UPA para atendimento.',
            icon: Icons.medical_services_rounded,
            color: Color(0xFFFF3B5C),
          ),
          OccurrenceQuickAction(
            title: 'Apresentado no DP',
            description: 'Ocorrência apresentada no Distrito Policial.',
            icon: Icons.account_balance_rounded,
            color: Color(0xFF4FA3FF),
          ),
        ],
      ),
    ];
  }
}
