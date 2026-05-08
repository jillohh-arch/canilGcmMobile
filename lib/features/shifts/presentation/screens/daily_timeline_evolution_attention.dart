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

  List<Widget> _buildEvolutionAttentionAlerts(String dogId) {
    final currentWindow = _getPerformanceTrainings(dogId, lastDays: 7);
    final previousWindow = _getPerformanceTrainings(dogId, lastDays: 14).where((
      training,
    ) {
      final cutoff = DateTime.now().subtract(const Duration(days: 7));
      return training.date.isBefore(cutoff);
    }).toList();

    final currentMinutes = currentWindow.fold<double>(
      0,
      (sum, training) => sum + ((training.searchDuration ?? 0) / 60),
    );
    final previousMinutes = previousWindow.fold<double>(
      0,
      (sum, training) => sum + ((training.searchDuration ?? 0) / 60),
    );

    final alerts = <Widget>[];
    final scopeLabel = _selectedTrainingFilter ?? 'performance';

    if (currentWindow.isEmpty) {
      alerts.add(
        _buildEvolutionMessageCard(
          icon: Icons.warning_amber_rounded,
          title: 'Sem registros recentes de $scopeLabel',
          description:
              'Nenhum treino desse recorte foi registrado nos últimos 7 dias.',
        ),
      );
    } else if (previousMinutes > 0 && currentMinutes < previousMinutes) {
      final variation =
          ((previousMinutes - currentMinutes) / previousMinutes) * 100;
      alerts.add(
        _buildEvolutionMessageCard(
          icon: Icons.trending_down_rounded,
          title: '$scopeLabel abaixo da semana anterior',
          description:
              'O volume caiu ${variation.toStringAsFixed(0)}% em comparação com a semana passada.',
        ),
      );
    } else if (previousMinutes > 0 && currentMinutes > previousMinutes) {
      final variation =
          ((currentMinutes - previousMinutes) / previousMinutes) * 100;
      alerts.add(
        _buildEvolutionMessageCard(
          icon: Icons.trending_up_rounded,
          title: '$scopeLabel acima da semana anterior',
          description:
              'O volume subiu ${variation.toStringAsFixed(0)}% em relação à semana passada.',
        ),
      );
    }

    alerts.addAll(_buildStaleCategoryAlerts(dogId));
    return alerts;
  }

  List<Widget> _buildStaleCategoryAlerts(String dogId) {
    final alerts = <Widget>[];

    for (final category in const [
      'Faro',
      'Busca & Captura',
      'Guarda',
      'Obediência',
    ]) {
      if (_selectedTrainingFilter != null &&
          category != _selectedTrainingFilter) {
        continue;
      }

      final categoryTrainings =
          _getPerformanceTrainings(dogId, applyFilter: false)
              .where(
                (training) =>
                    _normalizePerformanceCategory(training.trainingType) ==
                    category,
              )
              .toList();

      if (categoryTrainings.isEmpty) continue;

      final latest = categoryTrainings.first.date;
      final daysWithout = DateTime.now()
          .difference(DateTime(latest.year, latest.month, latest.day))
          .inDays;

      if (daysWithout >= 7) {
        alerts.add(
          _buildEvolutionMessageCard(
            icon: Icons.schedule_rounded,
            title: '$category sem registro recente',
            description:
                'A última sessão dessa competência foi há $daysWithout dias.',
          ),
        );
      }
    }

    return alerts;
  }
}
