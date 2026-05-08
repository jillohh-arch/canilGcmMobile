part of 'daily_timeline_screen.dart';

extension _DailyTimelineEvolutionVolumeAlert on _DailyTimelineScreenState {
  Widget _buildEvolutionVolumeAlert({
    required IconData icon,
    required String title,
    required double variation,
    required String directionLabel,
    required String comparisonLabel,
  }) {
    return _buildEvolutionMessageCard(
      icon: icon,
      title: title,
      description:
          'O volume $directionLabel ${(variation * 100).toStringAsFixed(0)}% $comparisonLabel semana passada.',
    );
  }
}
