part of 'daily_timeline_screen.dart';

extension _DailyTimelineEvolutionTitles on _DailyTimelineScreenState {
  Widget _buildEvolutionSectionTitle(String title, {required IconData icon}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: _hudCyan.withAlpha(18),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _hudCyan.withAlpha(90)),
            ),
            child: Icon(icon, color: _hudCyan, size: 15),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.inter(
                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _buildEvolutionVolumeTitle() {
    final filter = _selectedTrainingFilter;
    if (filter == null) {
      return 'CARGA DE TREINO NOS ÚLTIMOS 7 DIAS';
    }
    return 'CARGA DE ${filter.toUpperCase()} NOS ÚLTIMOS 7 DIAS';
  }

  String _buildEvolutionRecentSessionsTitle() {
    final filter = _selectedTrainingFilter;
    if (filter == null) {
      return 'ÚLTIMAS SESSÕES';
    }
    return 'ÚLTIMAS SESSÕES DE ${filter.toUpperCase()}';
  }

  String _buildEvolutionScopeHeadline() {
    final filter = _selectedTrainingFilter;
    if (filter == null) {
      return 'Panorama geral de performance';
    }
    return 'Esta semana de $filter';
  }

  String _buildEvolutionScopeDescription() {
    final filter = _selectedTrainingFilter;
    if (filter == null) {
      return 'Leitura consolidada dos treinos de performance registrados nesta semana.';
    }
    return 'Resumo do recorte atual para $filter, usando apenas registros reais deste período.';
  }
}
