part of 'daily_timeline_screen.dart';

extension _DailyTimelineOccurrencesTab on _DailyTimelineScreenState {
  // Conteúdo da aba de ocorrências
  Widget _buildOccurrencesTab(String dogId) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 112),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeaderDate(),
          _buildDateSelector(),
          _buildOpenIncidentsSection(dogId),
          _buildTimelineList(dogId, filterType: 'Ocorrência'),
        ],
      ),
    );
  }

  // Mostra ocorrências abertas para retomada rápida.
  Widget _buildOpenIncidentsSection(String dogId) {
    final dogVM = Provider.of<DogViewModel>(context, listen: false);
    final dogName = _resolveTimelineDogName(dogId, dogVM);
    final openIncidents = _openIncidentsForDog(dogId);

    if (openIncidents.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildOpenIncidentsHeader(openIncidents.length),
          const SizedBox(height: 12),
          ...openIncidents.map(
            (incident) => _buildOpenIncidentCard(
              dogId: dogId,
              dogName: dogName,
              incident: incident,
            ),
          ),
        ],
      ),
    );
  }
}
