part of 'daily_timeline_screen.dart';

extension _DailyTimelineIncidentCloseResults on _DailyTimelineScreenState {
  Widget _buildIncidentCloseResultsSection({
    required Incident incident,
    required Set<String> selectedOutcomes,
    required void Function(String outcome, bool isSelected) onOutcomeSelected,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'RESULTADOS FINAIS',
          style: GoogleFonts.inter(
            color: Colors.white54,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _quickCloseOutcomeOptionsForSubtype(incident.type).map((
            outcome,
          ) {
            final isSelected = selectedOutcomes.contains(outcome);
            return _buildIncidentSelectionChip(
              label: outcome,
              selected: isSelected,
              style: _resolveIncidentOutcomeBadgeStyle(outcome),
              onTap: () => onOutcomeSelected(outcome, isSelected),
            );
          }).toList(),
        ),
      ],
    );
  }
}
