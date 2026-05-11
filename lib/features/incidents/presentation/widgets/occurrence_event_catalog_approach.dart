part of 'occurrence_event_catalog.dart';

OccurrenceEventCategory _approachEventCategory() {
  return const OccurrenceEventCategory(
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
  );
}
