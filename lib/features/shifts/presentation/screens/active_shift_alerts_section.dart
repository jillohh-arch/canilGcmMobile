part of 'active_shift_dashboard_screen.dart';

/// Seção "Alertas" fiel ao mockup: cards com border-left colorido.
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
        _SectionLabel(emoji: '⚠', text: 'ALERTAS'),
        ...alerts.map((alert) => _AlertCard(alert: alert)),
      ],
    );
  }
}

class _AlertCard extends StatelessWidget {
  final DashboardAlert alert;

  const _AlertCard({required this.alert});

  @override
  Widget build(BuildContext context) {
    final color = _alertColor(alert.tipo);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(color: color, width: 3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(_alertIcon(alert.tipo), color: color, size: 16),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    alert.titulo,
                    style: GoogleFonts.inter(
                      color: _kTextPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (alert.descricao.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(
                      alert.descricao,
                      style: GoogleFonts.inter(
                        color: _kTextSecondary,
                        fontSize: 10,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              color: _kTextMuted,
              size: 14,
            ),
          ],
        ),
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
