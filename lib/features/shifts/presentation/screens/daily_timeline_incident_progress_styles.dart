part of 'daily_timeline_screen.dart';

extension _DailyTimelineIncidentProgressStyles on _DailyTimelineScreenState {
  _IncidentProgressStyle _resolveIncidentProgressStyle(
    String? title,
    String? description,
  ) {
    final normalizedTitle = (title ?? '').toLowerCase();
    final normalizedDescription = (description ?? '').toLowerCase();

    if (normalizedTitle.contains('encerramento')) {
      return const _IncidentProgressStyle(
        icon: Icons.task_alt_rounded,
        iconColor: Color(0xFF4ADE80),
        iconBackground: Color(0x1F4ADE80),
        titleColor: Color(0xFF86EFAC),
        backgroundColor: Color(0x1418241C),
        borderColor: Color(0x334ADE80),
      );
    }

    if (normalizedTitle.contains('apreens') ||
        normalizedTitle.contains('resultado') ||
        normalizedTitle.contains('detido') ||
        normalizedTitle.contains('localizada') ||
        normalizedDescription.contains('resultados parciais')) {
      return const _IncidentProgressStyle(
        icon: Icons.fact_check_rounded,
        iconColor: Color(0xFFFBBF24),
        iconBackground: Color(0x1FFBBF24),
        titleColor: Color(0xFFFCD34D),
        backgroundColor: Color(0x14FBBF24),
        borderColor: Color(0x33FBBF24),
      );
    }

    return const _IncidentProgressStyle(
      icon: Icons.timeline_rounded,
      iconColor: Color(0xFF38BDF8),
      iconBackground: Color(0x1F38BDF8),
      titleColor: Color(0xFF7DD3FC),
      backgroundColor: Color(0x1438BDF8),
      borderColor: Color(0x3338BDF8),
    );
  }
}
