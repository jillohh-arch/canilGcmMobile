part of 'daily_timeline_screen.dart';

extension _DailyTimelineEvolutionWeekComparisonCopy
    on _DailyTimelineScreenState {
  String _buildEvolutionWeekComparisonHeadline({
    required double previousMinutes,
    required bool isUp,
    required bool isDown,
    required String scopeText,
  }) {
    if (previousMinutes <= 0) {
      return 'Primeira base comparável de $scopeText';
    }
    if (isUp) {
      return '$scopeText acima da semana anterior';
    }
    if (isDown) {
      return '$scopeText abaixo da semana anterior';
    }
    return 'Mesmo volume de $scopeText na semana anterior';
  }

  String _buildEvolutionWeekComparisonDetail({
    required double currentMinutes,
    required double previousMinutes,
    required int currentSessions,
    required double deltaMinutes,
    required int deltaSessions,
  }) {
    if (previousMinutes <= 0) {
      return 'Esta semana soma ${_formatEvolutionMinutes(currentMinutes)} em $currentSessions sessão(ões).';
    }

    final percent = ((deltaMinutes.abs() / previousMinutes) * 100)
        .toStringAsFixed(0);
    return '${deltaMinutes.abs().toStringAsFixed(0)} min e ${deltaSessions.abs()} sessão(ões) de diferença • $percent% em relação à semana passada.';
  }
}
