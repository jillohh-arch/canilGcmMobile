part of 'daily_timeline_screen.dart';

extension _DailyTimelineEntryActions on _DailyTimelineScreenState {
  Widget _buildTimelineEditAction({
    required _TimelineEntry entry,
    required Color color,
    required String dogId,
    required String dogName,
  }) {
    return Align(
      alignment: Alignment.centerRight,
      child: Wrap(
        spacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: () => _openTimelineEntryEditor(
              entry: entry,
              dogId: dogId,
              dogName: dogName,
            ),
            icon: const Icon(Icons.edit_rounded, size: 14),
            label: Text(
              'EDITAR REGISTRO',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: color,
              side: BorderSide(color: color.withAlpha(180)),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
