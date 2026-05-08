part of 'daily_timeline_screen.dart';

extension _DailyTimelineList on _DailyTimelineScreenState {
  Widget _buildTimelineList(String dogId, {String? filterType}) {
    final timelineData = _buildTimelineEntries(dogId, filterType: filterType);
    final entries = timelineData.entries;
    if (entries.isEmpty) {
      final bool isIncidentsTab = filterType == 'Ocorrência';
      final hasOpenIncidents = timelineData.hasOpenIncidents;
      if (hasOpenIncidents) {
        return const SizedBox.shrink();
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isIncidentsTab
                    ? Icons.shield_outlined
                    : Icons.assignment_turned_in_outlined,
                size: 80,
                color: Colors.white.withAlpha(50),
              ),
              const SizedBox(height: 16),
              Text(
                isIncidentsTab
                    ? 'Nenhuma ocorrência encontrada'
                    : 'Plantão Tranquilo',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 8),
              if (!isIncidentsTab)
                Text(
                  'Puxe o card abaixo para registrar a primeira atividade do K9.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.white38,
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(0, 16, 10, 32),
      itemCount: entries.length,
      itemBuilder: (context, index) => _buildTimelineTile(
        entry: entries[index],
        index: index,
        total: entries.length,
        dogId: dogId,
        dogName: timelineData.dogName,
      ),
    );
  }
}
