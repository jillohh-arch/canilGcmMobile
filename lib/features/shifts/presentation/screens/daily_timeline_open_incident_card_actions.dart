part of 'daily_timeline_screen.dart';

extension _DailyTimelineOpenIncidentCardActions on _DailyTimelineScreenState {
  Widget _buildOpenIncidentActions({
    required String dogId,
    required String dogName,
    required Incident incident,
    required Color accent,
  }) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _showUnifiedUpdateSheet(
              incident: incident,
              dogId: dogId,
              dogName: dogName,
            ),
            icon: const Icon(Icons.edit_rounded, size: 16),
            label: Text(
              'Atualizar',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white70,
              side: const BorderSide(color: Colors.white12),
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton.icon(
            onPressed: () => _showQuickCloseIncidentSheet(
              dogId: dogId,
              dogName: dogName,
              incident: incident,
            ),
            icon: const Icon(Icons.task_alt_rounded, size: 16),
            label: Text(
              'Encerrar',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
