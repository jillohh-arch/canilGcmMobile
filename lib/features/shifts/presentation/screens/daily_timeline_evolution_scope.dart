// ignore_for_file: invalid_use_of_protected_member

part of 'daily_timeline_screen.dart';

extension _DailyTimelineEvolutionScope on _DailyTimelineScreenState {
  Widget _buildTrainingsTab(String dogId) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeaderDate(),
          _buildDateSelector(),
          _buildTimelineList(dogId, filterType: 'Training'),
        ],
      ),
    );
  }

  Widget _buildEvolutionTab(String dogId) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildEvolutionSummarySection(dogId),
          _buildTrainingFilterChips(),
          const SizedBox(height: 14),
          _buildEvolutionSectionTitle(
            _buildEvolutionVolumeTitle(),
            icon: Icons.bar_chart_rounded,
          ),
          const SizedBox(height: 8),
          _buildEvolutionBarChart(dogId),
          const SizedBox(height: 16),
          _buildCompetencyEvolutionSection(dogId),
          const SizedBox(height: 16),
          _buildEvolutionAttentionSection(dogId),
          const SizedBox(height: 16),
          _buildEvolutionSectionTitle(
            _buildEvolutionRecentSessionsTitle(),
            icon: Icons.history_rounded,
          ),
          _buildRecentPerformanceSessions(dogId),
        ],
      ),
    );
  }
}
