part of 'health_dashboard_screen.dart';

class _HealthLogCardHeader extends StatelessWidget {
  final HealthLogModel log;
  final Color accentColor;
  final IconData iconData;

  const _HealthLogCardHeader({
    required this.log,
    required this.accentColor,
    required this.iconData,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.15),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(6),
          topRight: Radius.circular(6),
        ),
      ),
      child: Row(
        children: [
          Icon(iconData, size: 16, color: accentColor),
          const SizedBox(width: 8),
          Text(
            log.logType.toUpperCase(),
            style: GoogleFonts.shareTechMono(
              color: accentColor,
              fontWeight: FontWeight.bold,
              fontSize: 14,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          Text(
            _formatMilitaryDate(log.date),
            style: GoogleFonts.shareTechMono(
              color: AppTheme.textPrimary.withAlpha(179),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
