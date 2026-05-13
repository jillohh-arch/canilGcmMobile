part of 'active_shift_dashboard_screen.dart';

/// Seção "ALERTAS" com dados vindos do Firestore.
class _AlertsSection extends StatelessWidget {
  final List<DashboardAlert> alerts;
  final int totalAlerts;

  const _AlertsSection({required this.alerts, required this.totalAlerts});

  @override
  Widget build(BuildContext context) {
    if (alerts.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.notifications_active_outlined,
              color: _hudCyan,
              size: 16,
            ),
            const SizedBox(width: 6),
            Text(
              'ALERTAS',
              style: GoogleFonts.robotoMono(
                color: _hudCyan,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
              ),
            ),
            const Spacer(),
            if (totalAlerts > alerts.length)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'ver todos',
                    style: GoogleFonts.inter(
                      color: _hudCyan,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: _hudCyan,
                    size: 16,
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 12),
        for (int i = 0; i < alerts.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _AlertCard(alert: alerts[i]),
        ],
      ],
    );
  }
}

class _AlertCard extends StatelessWidget {
  final DashboardAlert alert;

  const _AlertCard({required this.alert});

  @override
  Widget build(BuildContext context) {
    final color = _priorityColor(alert.prioridade);
    final icon = _resolveAlertIcon(alert.icone);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withAlpha(30),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alert.titulo,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  alert.descricao,
                  style: GoogleFonts.inter(
                    color: Colors.white38,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            color: Colors.white24,
            size: 20,
          ),
        ],
      ),
    );
  }

  Color _priorityColor(String prioridade) {
    switch (prioridade) {
      case 'critica':
        return _hudDanger;
      case 'atencao':
        return _hudAmber;
      case 'informativo':
      default:
        return _hudCyan;
    }
  }

  IconData _resolveAlertIcon(String icone) {
    switch (icone) {
      case 'vaccine':
      case 'vacina':
        return Icons.vaccines_rounded;
      case 'temperature':
      case 'calor':
        return Icons.thermostat_rounded;
      case 'training':
      case 'treino':
        return Icons.fitness_center_rounded;
      case 'health':
      case 'saude':
        return Icons.medical_services_outlined;
      case 'warning':
      default:
        return Icons.warning_amber_rounded;
    }
  }
}
