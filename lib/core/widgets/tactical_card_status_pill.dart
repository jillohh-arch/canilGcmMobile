part of 'tactical_card.dart';

class StatusPill extends StatelessWidget {
  final String status;
  final Color color;
  final IconData icon;

  const StatusPill({
    super.key,
    required this.status,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.background.withAlpha(50),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: AppTheme.textPrimary.withAlpha(61),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            status,
            style: GoogleFonts.inter(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}
