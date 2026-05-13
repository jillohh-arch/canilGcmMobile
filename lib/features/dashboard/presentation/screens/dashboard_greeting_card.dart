part of 'dashboard_screen.dart';

class _GreetingCard extends StatelessWidget {
  final String displayName;
  final int trainingAlerts;
  final int healthAlerts;
  const _GreetingCard({
    required this.displayName,
    required this.trainingAlerts,
    required this.healthAlerts,
  });

  @override
  Widget build(BuildContext context) {
    final total = trainingAlerts + healthAlerts;
    final now = DateTime.now();
    final months = [
      'Jan',
      'Fev',
      'Mar',
      'Abr',
      'Mai',
      'Jun',
      'Jul',
      'Ago',
      'Set',
      'Out',
      'Nov',
      'Dez',
    ];
    final dateStr = '${now.day} de ${months[now.month - 1]}';

    if (total == 0) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _hudPanel.withAlpha(225),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _hudCyan.withAlpha(65)),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: _hudCyan, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tudo em dia',
                    style: GoogleFonts.oxanium(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$dateStr · Sem alertas operacionais',
                    style: GoogleFonts.robotoMono(
                      color: Colors.white54,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _hudPanel.withAlpha(235),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _hudDanger.withAlpha(105), width: 0.8),
        boxShadow: [BoxShadow(color: _hudDanger.withAlpha(24), blurRadius: 16)],
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: _hudDanger, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$total alerta${total > 1 ? 's' : ''} operacional${total > 1 ? 'is' : ''}',
                  style: GoogleFonts.oxanium(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.7,
                  ),
                ),
                if (trainingAlerts > 0)
                  Text(
                    '• $trainingAlerts cão sem treino há +3 dias',
                    style: GoogleFonts.robotoMono(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (healthAlerts > 0)
                  Text(
                    '• $healthAlerts vacina${healthAlerts > 1 ? 's' : ''} vencida${healthAlerts > 1 ? 's' : ''}',
                    style: GoogleFonts.robotoMono(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
