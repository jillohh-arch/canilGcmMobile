part of 'daily_timeline_screen.dart';

extension _DailyTimelineEvolutionChartLegend on _DailyTimelineScreenState {
  Widget _buildEvolutionLegend() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _trainingCategories.map((category) {
        final visual = _resolveEvolutionCategoryVisual(category);
        return _buildEvolutionLegendChip(
          label: category,
          color: visual.color,
          icon: visual.icon,
        );
      }).toList(),
    );
  }

  Widget _buildEvolutionLegendChip({
    required String label,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(70)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
