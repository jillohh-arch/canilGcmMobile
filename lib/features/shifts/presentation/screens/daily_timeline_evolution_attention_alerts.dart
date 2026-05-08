part of 'daily_timeline_screen.dart';

extension _DailyTimelineEvolutionAttentionAlerts on _DailyTimelineScreenState {
  List<Widget> _buildEvolutionAttentionAlerts(String dogId) {
    final currentWindow = _getPerformanceTrainings(dogId, lastDays: 7);
    final previousWindow = _getPerformanceTrainings(dogId, lastDays: 14).where((
      training,
    ) {
      final cutoff = DateTime.now().subtract(const Duration(days: 7));
      return training.date.isBefore(cutoff);
    }).toList();

    final currentMinutes = _sumEvolutionMinutes(currentWindow);
    final previousMinutes = _sumEvolutionMinutes(previousWindow);
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
      alerts.add(
        _buildEvolutionVolumeAlert(
          icon: Icons.trending_down_rounded,
          title: '$scopeLabel abaixo da semana anterior',
          variation: (previousMinutes - currentMinutes) / previousMinutes,
          directionLabel: 'caiu',
          comparisonLabel: 'em comparação com a',
        ),
      );
    } else if (previousMinutes > 0 && currentMinutes > previousMinutes) {
      alerts.add(
        _buildEvolutionVolumeAlert(
          icon: Icons.trending_up_rounded,
          title: '$scopeLabel acima da semana anterior',
          variation: (currentMinutes - previousMinutes) / previousMinutes,
          directionLabel: 'subiu',
          comparisonLabel: 'em relação à',
        ),
      );
    }

    alerts.addAll(_buildStaleCategoryAlerts(dogId));
    return alerts;
  }
}
