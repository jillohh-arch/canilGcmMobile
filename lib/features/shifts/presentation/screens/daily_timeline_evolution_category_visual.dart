part of 'daily_timeline_screen.dart';

extension _DailyTimelineEvolutionCategoryVisual on _DailyTimelineScreenState {
  ({IconData icon, Color color}) _resolveEvolutionCategoryVisual(
    String category,
  ) {
    switch (category) {
      case 'Faro':
        return (icon: Icons.sensors_rounded, color: const Color(0xFF38BDF8));
      case 'Busca & Captura':
        return (
          icon: Icons.crisis_alert_rounded,
          color: const Color(0xFFF97316),
        );
      case 'Guarda':
        return (icon: Icons.shield_rounded, color: const Color(0xFF4ADE80));
      case 'Obediência':
        return (icon: Icons.rule_rounded, color: const Color(0xFFA78BFA));
      default:
        return (icon: Icons.pets_rounded, color: const Color(0xFFFBBF24));
    }
  }
}
