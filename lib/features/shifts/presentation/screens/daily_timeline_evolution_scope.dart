// ignore_for_file: invalid_use_of_protected_member

part of 'daily_timeline_screen.dart';

extension _DailyTimelineEvolutionScope on _DailyTimelineScreenState {
  static const _performanceAllowlist = [
    'Faro',
    'Busca & Captura',
    'Busca de Pessoa',
    'Guarda e Proteção',
    'Guarda',
    'Obediência',
  ];

  Widget _buildTrainingsTab(String dogId) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeaderDate(),
          _buildDateSelector(),
          _buildTimelineList(dogId, filterType: 'Training'),
        ],
      ),
    );
  }

  Widget _buildEvolutionTab(String dogId) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildEvolutionSummarySection(dogId),
          _buildTrainingFilterChips(),
          const SizedBox(height: 14),
          _buildEvolutionSectionTitle(
            _buildEvolutionVolumeTitle(),
            icon: Icons.bar_chart_rounded,
          ),
          const SizedBox(height: 8),
          _buildEvolutionBarChart(dogId),
          const SizedBox(height: 16),
          _buildCompetencyEvolutionSection(dogId),
          const SizedBox(height: 16),
          _buildEvolutionAttentionSection(dogId),
          const SizedBox(height: 16),
          _buildEvolutionSectionTitle(
            _buildEvolutionRecentSessionsTitle(),
            icon: Icons.history_rounded,
          ),
          _buildRecentPerformanceSessions(dogId),
        ],
      ),
    );
  }

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
              style: GoogleFonts.robotoMono(
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
    if (_selectedTrainingFilter == null) {
      return 'CARGA DE TREINO NOS ÚLTIMOS 7 DIAS';
    }
    return 'CARGA DE ${_selectedTrainingFilter!.toUpperCase()} NOS ÚLTIMOS 7 DIAS';
  }

  String _buildEvolutionRecentSessionsTitle() {
    if (_selectedTrainingFilter == null) {
      return 'ÚLTIMAS SESSÕES';
    }
    return 'ÚLTIMAS SESSÕES DE ${_selectedTrainingFilter!.toUpperCase()}';
  }

  String _buildEvolutionScopeHeadline() {
    if (_selectedTrainingFilter == null) {
      return 'Panorama geral de performance';
    }
    return 'Esta semana de ${_selectedTrainingFilter!}';
  }

  String _buildEvolutionScopeDescription() {
    if (_selectedTrainingFilter == null) {
      return 'Leitura consolidada dos treinos de performance registrados nesta semana.';
    }
    return 'Resumo do recorte atual para ${_selectedTrainingFilter!}, usando apenas registros reais deste período.';
  }

  bool _isPerformanceType(String trainingType) {
    for (final allowed in _performanceAllowlist) {
      if (trainingType.toLowerCase().contains(allowed.toLowerCase())) {
        return true;
      }
    }
    return false;
  }

  bool _matchesTrainingFilter(String trainingType) {
    if (_selectedTrainingFilter == null) return true;
    return trainingType.toLowerCase().contains(
          _selectedTrainingFilter!.toLowerCase(),
        ) ||
        (_selectedTrainingFilter == 'Busca & Captura' &&
            (trainingType.contains('Busca') ||
                trainingType.contains('Captura')));
  }

  String _normalizePerformanceCategory(String trainingType) {
    final normalized = trainingType.toLowerCase();
    if (normalized.contains('faro')) return 'Faro';
    if (normalized.contains('busca') || normalized.contains('captura')) {
      return 'Busca & Captura';
    }
    if (normalized.contains('guarda') || normalized.contains('prote')) {
      return 'Guarda';
    }
    if (normalized.contains('obedi')) return 'Obediência';
    return trainingType;
  }

  List<TrainingSessionModel> _getPerformanceTrainings(
    String dogId, {
    int? lastDays,
    bool applyFilter = true,
  }) {
    final tVM = Provider.of<TrainingViewModel>(context, listen: false);
    final now = DateTime.now();
    final startDate = lastDays == null
        ? null
        : DateTime(
            now.year,
            now.month,
            now.day,
          ).subtract(Duration(days: lastDays - 1));

    final trainings = tVM.trainings.where((training) {
      if (training.dogId != dogId) return false;
      if (!_isPerformanceType(training.trainingType)) return false;
      if (applyFilter && !_matchesTrainingFilter(training.trainingType)) {
        return false;
      }
      if (startDate != null && training.date.isBefore(startDate)) return false;
      return true;
    }).toList()..sort((a, b) => b.date.compareTo(a.date));

    return trainings;
  }
}
