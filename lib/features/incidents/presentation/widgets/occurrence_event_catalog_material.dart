part of 'occurrence_event_catalog.dart';

OccurrenceEventCategory _materialEventCategory() {
  return const OccurrenceEventCategory(
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
  );
}
