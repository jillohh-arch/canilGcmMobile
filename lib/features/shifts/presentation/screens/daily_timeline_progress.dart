part of 'daily_timeline_screen.dart';

extension _DailyTimelineProgress on _DailyTimelineScreenState {
  Widget _buildIncidentProgressTimeline({
    required List updates,
    required Color accent,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 4),
      decoration: BoxDecoration(
        color: const Color(0xFF070B14).withAlpha(230),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: accent.withAlpha(95)),
        boxShadow: [
          BoxShadow(
            color: accent.withAlpha(24),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          for (var index = 0; index < updates.length; index++)
            _buildIncidentProgressNode(
              step: updates[index],
              index: index,
              isLast: index == updates.length - 1,
              accent: accent,
            ),
        ],
      ),
    );
  }
}
