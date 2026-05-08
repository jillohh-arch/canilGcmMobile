part of 'daily_timeline_screen.dart';

extension _DailyTimelineIncidentUpdateOutcomeSection
    on _DailyTimelineScreenState {
  Widget _buildIncidentUpdateOutcomeSection({
    required Incident incident,
    required Set<String> selectedOutcomes,
    required void Function(String outcome, bool isSelected) onOutcomeSelected,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'DESFECHOS PARCIAIS',
          style: GoogleFonts.inter(
            color: Colors.white38,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
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
