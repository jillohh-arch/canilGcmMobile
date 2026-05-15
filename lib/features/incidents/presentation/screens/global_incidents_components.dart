part of 'global_incidents_screen.dart';

Color _globalIncidentResultColor(String result) {
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
  return AppTheme.primary;
}

IconData _globalIncidentTypeIcon(String? type) {
  switch (type) {
    case 'Busca de Entorpecentes':
      return Icons.track_changes_rounded;
    case 'Apoio Ã  Viatura':
      return Icons.local_police_rounded;
    case 'Varredura de Local':
      return Icons.radar_rounded;
    case 'Busca de Pessoa':
      return Icons.person_search_rounded;
    default:
      return Icons.report_rounded;
  }
}

class _GlobalIncidentTag extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _GlobalIncidentTag({
    required this.icon,
    required this.text,
    required this.color,
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
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
