part of 'active_shift_dashboard_screen.dart';

/// Seção "Alertas" com dados vindos do Firestore.
class _AlertsSection extends StatelessWidget {
  final List<DashboardAlert> alerts;
  final int totalAlerts;

  const _AlertsSection({required this.alerts, required this.totalAlerts});

  @override
  Widget build(BuildContext context) {
    if (alerts.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'ALERTAS',
              style: GoogleFonts.inter(
                color: AppTheme.textTertiary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const Spacer(),
            if (totalAlerts > alerts.length)
              Text(
                'ver todos ($totalAlerts)',
                style: GoogleFonts.inter(
                  color: AppTheme.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        ...alerts.map((alert) => _AlertTile(alert: alert)),
      ],
    );
  }
}

class _AlertTile extends StatelessWidget {
  final DashboardAlert alert;

  const _AlertTile({required this.alert});

  @override
  Widget build(BuildContext context) {
    final color = _alertColor(alert.tipo);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withAlpha(8),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(40)),
      ),
      child: Row(
        children: [
          Icon(_alertIcon(alert.tipo), color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alert.titulo,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                if (alert.descricao.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    alert.descricao,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _alertColor(String tipo) {
    switch (tipo) {
      case 'critico':
        return AppTheme.error;
      case 'atencao':
        return AppTheme.warning;
      case 'info':
        return AppTheme.primary;
      default:
        return AppTheme.warning;
    }
  }

  IconData _alertIcon(String tipo) {
    switch (tipo) {
      case 'critico':
        return Icons.error_outline_rounded;
      case 'atencao':
        return Icons.warning_amber_rounded;
      case 'info':
        return Icons.info_outline_rounded;
      default:
        return Icons.notifications_outlined;
    }
  }
}