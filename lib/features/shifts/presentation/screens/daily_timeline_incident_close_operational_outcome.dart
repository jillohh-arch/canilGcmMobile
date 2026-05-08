part of 'daily_timeline_screen.dart';

extension _DailyTimelineIncidentCloseOperationalOutcome
    on _DailyTimelineScreenState {
  Widget _buildIncidentCloseOperationalOutcomeSection({
    required bool operationalSuccess,
    required ValueChanged<bool> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'DESFECHO OPERACIONAL',
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
          children: [
            _buildIncidentSelectionChip(
              label: 'Com êxito',
              selected: operationalSuccess,
              style: const _IncidentBadgeStyle(
                icon: Icons.task_alt_rounded,
                iconColor: Color(0xFF4ADE80),
                textColor: Color(0xFF86EFAC),
                backgroundColor: Color(0x144ADE80),
                borderColor: Color(0x334ADE80),
              ),
              onTap: () => onChanged(true),
            ),
            _buildIncidentSelectionChip(
              label: 'Sem êxito',
              selected: !operationalSuccess,
              style: const _IncidentBadgeStyle(
                icon: Icons.cancel_rounded,
                iconColor: Color(0xFFF87171),
                textColor: Color(0xFFFCA5A5),
                backgroundColor: Color(0x14F87171),
                borderColor: Color(0x33F87171),
              ),
              onTap: () => onChanged(false),
            ),
          ],
        ),
      ],
    );
  }
}
