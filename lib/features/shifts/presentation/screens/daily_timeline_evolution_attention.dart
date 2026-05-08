part of 'daily_timeline_screen.dart';

extension _DailyTimelineEvolutionAttention on _DailyTimelineScreenState {
  Widget _buildEvolutionAttentionSection(String dogId) {
    final alerts = _buildEvolutionAttentionAlerts(dogId);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
            child: Text(
              _selectedTrainingFilter == null
                  ? 'ATENÇÃO DO PERÍODO'
                  : 'ATENÇÃO EM ${_selectedTrainingFilter!.toUpperCase()}',
              style: GoogleFonts.robotoMono(
                color: _hudCyan.withAlpha(210),
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
              ),
            ),
          ),
          if (alerts.isEmpty)
            _buildEvolutionMessageCard(
              icon: Icons.verified_rounded,
              title: _selectedTrainingFilter == null
                  ? 'Rotina consistente'
                  : 'Recorte consistente',
              description: _selectedTrainingFilter == null
                  ? 'Os registros recentes mostram continuidade de treino sem alertas importantes.'
                  : 'Os registros recentes de ${_selectedTrainingFilter!} estão consistentes neste período.',
            )
          else
            ...alerts.map(
              (alert) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: alert,
              ),
            ),
        ],
      ),
    );
  }
}
