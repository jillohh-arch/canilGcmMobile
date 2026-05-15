part of 'incident_form_screen.dart';

Color _incidentFeedResultColor(String result) {
  final normalized = result.toLowerCase();

  if (normalized.contains('Ãªxito') ||
      normalized.contains('exito') ||
      normalized.contains('sucesso') ||
      normalized.contains('localiz')) {
    return AppTheme.statusActive;
  }
  if (normalized.contains('falso') || normalized.contains('negativo')) {
    return AppTheme.statusLeave;
  }
  if (normalized.contains('cancel')) {
    return AppTheme.statusAlert;
  }
  return const Color(0xFF4ECDE4);
}

IconData _incidentFeedTypeIcon(String? type) {
  switch (type) {
    case 'Busca de Entorpecentes':
      return Icons.track_changes_rounded;
    case 'Apoio Ã  Viatura':
      return Icons.local_police_rounded;
    case 'Varredura de Local':
      return Icons.radar_rounded;
    case 'Busca de Pessoa':
      return Icons.person_search_rounded;
    case 'Outros':
      return Icons.report_gmailerrorred_rounded;
    default:
      return Icons.report_rounded;
  }
}

class _IncidentFeedTag extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color iconColor;
  final Color textColor;

  const _IncidentFeedTag({
    required this.icon,
    required this.text,
    required this.iconColor,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: cs.outlineVariant, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: iconColor),
          const SizedBox(width: 4),
          Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}
