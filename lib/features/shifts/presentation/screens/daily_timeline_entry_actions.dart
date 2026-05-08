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
              style: GoogleFonts.oxanium(
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

  void _openTimelineEntryEditor({
    required _TimelineEntry entry,
    required String dogId,
    required String dogName,
  }) {
    HapticFeedback.lightImpact();

    final data = entry.originalModel.toJson() as Map<String, dynamic>;
    data['_rawDate'] = entry.time;

    if (entry.category == 'Ocorrência') {
      final handlerId = entry.originalModel.handlerId?.toString() ?? '';
      if (handlerId.isNotEmpty) {
        data['_rawHandlerId'] = handlerId;
      }
    }

    if (entry.category == 'Ocorrência' && entry.originalModel is Incident) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OccurrenceFlowScreen(
            dogId: dogId,
            dogName: dogName,
            incident: entry.originalModel as Incident,
          ),
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DynamicActivitySheet(
        category: entry.category,
        dogId: dogId,
        dogName: dogName,
        initialData: data,
        documentId: entry.id,
      ),
    );
  }
}
