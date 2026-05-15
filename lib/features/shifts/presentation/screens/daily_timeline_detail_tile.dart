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
            AppTheme.background,
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
}
