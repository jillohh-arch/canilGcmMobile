part of 'dashboard_screen.dart';

class _InlineStatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;

  const _InlineStatusPill({
    required this.label,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(80), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 9, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.robotoMono(
              fontSize: 8,
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _TinyAlert extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _TinyAlert({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Icon(icon, size: 14, color: color);
}

class _MicroStat extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;

  const _MicroStat({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: GoogleFonts.oxanium(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: highlight ? _hudAmber : Colors.white,
            letterSpacing: 0.5,
          ),
        ),
        Text(
          label.toUpperCase(),
          style: GoogleFonts.robotoMono(
            fontSize: 8,
            fontWeight: FontWeight.w600,
            color: Colors.white54,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}
