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
    final iVM = Provider.of<IncidentViewModel>(context);
    final dogVM = Provider.of<DogViewModel>(context, listen: false);
    final dogName = dogVM.dogs
        .firstWhere(
          (d) => d.id == dogId,
          orElse: () => dogVM.dogs.isNotEmpty
              ? dogVM.dogs.first
              : throw Exception('Cão não encontrado'),
        )
        .name;

    final openIncidents =
        iVM.incidents
            .where(
              (incident) => incident.dogId == dogId && incident.isInProgress,
            )
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    if (openIncidents.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFBBF24).withAlpha(28),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: const Color(0xFFFBBF24).withAlpha(90),
                  ),
                ),
                child: const Icon(
                  Icons.pending_actions_rounded,
                  color: Color(0xFFFBBF24),
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'OCORRÊNCIAS EM ANDAMENTO',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${openIncidents.length} caso(s) aberto(s) para continuidade',
                      style: GoogleFonts.inter(
                        color: Colors.white54,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
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
