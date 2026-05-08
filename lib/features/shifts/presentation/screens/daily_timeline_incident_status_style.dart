part of 'daily_timeline_screen.dart';

extension _DailyTimelineIncidentStatusStyle on _DailyTimelineScreenState {
  _IncidentBadgeStyle _resolveIncidentStatusBadgeStyle(String status) {
    final normalized = status.toLowerCase();

    if (normalized.contains('concl')) {
      return const _IncidentBadgeStyle(
        icon: Icons.task_alt_rounded,
        iconColor: Color(0xFF4ADE80),
        textColor: Color(0xFF86EFAC),
        backgroundColor: Color(0x144ADE80),
        borderColor: Color(0x334ADE80),
      );
    }

    if (normalized.contains('cancel')) {
      return const _IncidentBadgeStyle(
        icon: Icons.cancel_rounded,
        iconColor: Color(0xFFF87171),
        textColor: Color(0xFFFCA5A5),
        backgroundColor: Color(0x14F87171),
        borderColor: Color(0x33F87171),
      );
    }

    return const _IncidentBadgeStyle(
      icon: Icons.radar_rounded,
      iconColor: Color(0xFFFBBF24),
      textColor: Color(0xFFFCD34D),
      backgroundColor: Color(0x14FBBF24),
      borderColor: Color(0x33FBBF24),
    );
  }
}
