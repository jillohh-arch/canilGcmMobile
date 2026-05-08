part of 'daily_timeline_screen.dart';

extension _DailyTimelineEntryEditor on _DailyTimelineScreenState {
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
