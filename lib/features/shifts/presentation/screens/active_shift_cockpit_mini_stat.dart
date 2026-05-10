part of 'active_shift_dashboard_screen.dart';

class _CockpitMiniStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _CockpitMiniStat({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 104,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: _hudPanelAlt.withAlpha(210),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _hudCyan.withAlpha(75)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: _hudCyan.withAlpha(190), size: 22),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value.toUpperCase(),
              style: GoogleFonts.oxanium(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 0.6,
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            label.toUpperCase(),
            style: GoogleFonts.robotoMono(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: Colors.white54,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}
