part of 'daily_timeline_screen.dart';

extension _DailyTimelineIncidentChips on _DailyTimelineScreenState {
  Widget _buildIncidentBadge({
    required String label,
    required _IncidentBadgeStyle style,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: style.backgroundColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: style.borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, size: 13, color: style.iconColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              color: style.textColor,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIncidentMetaPill({
    required IconData icon,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(8),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white54),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.inter(
              color: Colors.white60,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIncidentSelectionChip({
    required String label,
    required bool selected,
    required _IncidentBadgeStyle style,
    required VoidCallback onTap,
  }) {
    final effectiveStyle = selected
        ? style
        : _IncidentBadgeStyle(
            icon: style.icon,
            iconColor: Colors.white54,
            textColor: Colors.white70,
            backgroundColor: Colors.white.withAlpha(6),
            borderColor: Colors.white12,
          );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: effectiveStyle.backgroundColor,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: effectiveStyle.borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              effectiveStyle.icon,
              size: 13,
              color: effectiveStyle.iconColor,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.inter(
                color: effectiveStyle.textColor,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
