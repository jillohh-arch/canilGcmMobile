part of 'daily_timeline_screen.dart';

extension _DailyTimelineDetailTile on _DailyTimelineScreenState {
  Widget _buildTimelineDetailTile({
    required String label,
    required String value,
    required IconData icon,
    required Color accent,
    required bool expanded,
  }) {
    return Container(
      width: expanded ? double.infinity : null,
      constraints: BoxConstraints(minHeight: expanded ? 0 : 74),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1020).withAlpha(230),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: accent.withAlpha(70)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withAlpha(20),
            const Color(0xFF0F1726),
            const Color(0xFF070B14),
          ],
        ),
      ),
      child: expanded
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTimelineDetailIcon(icon, accent),
                const SizedBox(width: 9),
                Expanded(child: _buildTimelineDetailText(label, value, true)),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTimelineDetailIcon(icon, accent),
                const SizedBox(height: 8),
                _buildTimelineDetailText(label, value, false),
              ],
            ),
    );
  }

  Widget _buildTimelineDetailIcon(IconData icon, Color accent) {
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent.withAlpha(22),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: accent.withAlpha(110)),
      ),
      child: Icon(icon, size: 14, color: accent.withAlpha(230)),
    );
  }

  Widget _buildTimelineDetailText(String label, String value, bool expanded) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: GoogleFonts.robotoMono(
            color: Colors.white38,
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.7,
          ),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
        const SizedBox(height: 5),
        Text(
          value,
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: expanded ? 12 : 13,
            fontWeight: expanded ? FontWeight.w500 : FontWeight.w800,
            height: 1.35,
          ),
          overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis,
          maxLines: expanded ? null : 2,
        ),
      ],
    );
  }
}
