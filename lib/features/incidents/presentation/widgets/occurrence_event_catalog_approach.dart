part of 'occurrence_event_catalog.dart';

OccurrenceEventCategory _approachEventCategory() {
  return const OccurrenceEventCategory(
    title: 'Abordagem',
    icon: Icons.person_search_rounded,
    color: AppTheme.warning,
    actions: [
      OccurrenceQuickAction(
        title: 'Veículo abordado',
        description: 'Veículo abordado durante a ocorrência.',
        icon: Icons.directions_car_rounded,
        color: AppTheme.warning,
      ),
      OccurrenceQuickAction(
        title: 'Pessoa identificada',
        description: 'Pessoa identificada pela equipe.',
        icon: Icons.badge_rounded,
        color: AppTheme.warning,
      ),
      OccurrenceQuickAction(
        title: 'Documento verificado',
        description: 'Documento consultado ou verificado.',
        icon: Icons.assignment_ind_rounded,
        color: AppTheme.warning,
      ),
      OccurrenceQuickAction(
        title: 'Revista pessoal',
        description: 'Revista pessoal realizada pela equipe.',
        icon: Icons.accessibility_new_rounded,
        color: AppTheme.warning,
      ),
    ],
  );
}
