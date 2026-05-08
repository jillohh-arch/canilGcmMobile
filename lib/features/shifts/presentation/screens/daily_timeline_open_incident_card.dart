part of 'daily_timeline_screen.dart';

extension _DailyTimelineOpenIncidentCard on _DailyTimelineScreenState {
  Widget _buildOpenIncidentCard({
    required String dogId,
    required String dogName,
    required Incident incident,
  }) {
    final accent = const Color(0xFFFBBF24);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF161618),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white10),
        boxShadow: [
          BoxShadow(
            color: accent.withAlpha(18),
            blurRadius: 16,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildOpenIncidentHeader(incident: incident, accent: accent),
          const SizedBox(height: 10),
          ..._buildOpenIncidentDetails(incident),
          const SizedBox(height: 14),
          _buildOpenIncidentActions(
            dogId: dogId,
            dogName: dogName,
            incident: incident,
            accent: accent,
          ),
        ],
      ),
    );
  }
}
