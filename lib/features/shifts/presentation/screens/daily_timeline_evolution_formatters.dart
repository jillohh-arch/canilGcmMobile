part of 'daily_timeline_screen.dart';

extension _DailyTimelineEvolutionFormatters on _DailyTimelineScreenState {
  String _formatEvolutionDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final difference = today.difference(target).inDays;

    if (difference == 0) return 'Hoje';
    if (difference == 1) return 'Ontem';
    return DateFormat('dd/MM').format(date);
  }

  String _formatEvolutionMinutes(double minutes) {
    if (minutes <= 0) return '0 min';
    return '${minutes.toStringAsFixed(0)} min';
  }
}
