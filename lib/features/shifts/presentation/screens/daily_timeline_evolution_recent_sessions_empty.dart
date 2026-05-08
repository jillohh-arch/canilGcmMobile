part of 'daily_timeline_screen.dart';

extension _DailyTimelineEvolutionRecentSessionsEmpty
    on _DailyTimelineScreenState {
  Widget _buildRecentPerformanceSessionsEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.track_changes_rounded,
              size: 60,
              color: Colors.white.withAlpha(30),
            ),
            const SizedBox(height: 12),
            Text(
              'Nenhuma sessão de performance registrada',
              style: GoogleFonts.inter(color: Colors.white38, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
