part of 'daily_timeline_screen.dart';

extension _DailyTimelineIncidentSelectionChip on _DailyTimelineScreenState {
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
