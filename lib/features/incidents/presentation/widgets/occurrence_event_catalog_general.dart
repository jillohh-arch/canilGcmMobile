part of 'occurrence_event_catalog.dart';

OccurrenceEventCategory _generalEventCategory(Color accent) {
  return OccurrenceEventCategory(
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
  );
}
