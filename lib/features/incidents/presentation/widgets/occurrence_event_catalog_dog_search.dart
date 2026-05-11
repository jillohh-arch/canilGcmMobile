part of 'occurrence_event_catalog.dart';

OccurrenceEventCategory _dogSearchEventCategory() {
  return const OccurrenceEventCategory(
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
  );
}
