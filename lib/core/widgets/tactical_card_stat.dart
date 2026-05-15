part of 'tactical_card.dart';

class TacticalCardStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;

  const TacticalCardStat({
    super.key,
    required this.label,
    required this.value,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: Colors.white54),
          const SizedBox(height: 2),
        ],
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
          textAlign: TextAlign.center,
        ),
        Text(
          label.toUpperCase(),
          style: GoogleFonts.inter(
            fontSize: 8,
            fontWeight: FontWeight.w600,
            color: Colors.white54,
            letterSpacing: 0.6,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
