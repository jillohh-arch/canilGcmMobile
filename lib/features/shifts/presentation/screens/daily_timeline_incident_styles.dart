part of 'daily_timeline_screen.dart';

extension _DailyTimelineIncidentStyles on _DailyTimelineScreenState {
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

  _IncidentBadgeStyle _resolveIncidentOutcomeBadgeStyle(String outcome) {
    final normalized = outcome.toLowerCase();

    if (normalized.contains('droga') || normalized.contains('apreens')) {
      return const _IncidentBadgeStyle(
        icon: Icons.inventory_2_rounded,
        iconColor: Color(0xFFFBBF24),
        textColor: Color(0xFFFCD34D),
        backgroundColor: Color(0x14FBBF24),
        borderColor: Color(0x33FBBF24),
      );
    }

    if (normalized.contains('detido') || normalized.contains('preso')) {
      return const _IncidentBadgeStyle(
        icon: Icons.gpp_good_rounded,
        iconColor: Color(0xFFFB7185),
        textColor: Color(0xFFFDA4AF),
        backgroundColor: Color(0x14FB7185),
        borderColor: Color(0x33FB7185),
      );
    }

    if (normalized.contains('localiz')) {
      return const _IncidentBadgeStyle(
        icon: Icons.location_searching_rounded,
        iconColor: Color(0xFF38BDF8),
        textColor: Color(0xFF7DD3FC),
        backgroundColor: Color(0x1438BDF8),
        borderColor: Color(0x3338BDF8),
      );
    }

    if (normalized.contains('apoio') ||
        normalized.contains('encaminhamento') ||
        normalized.contains('socorrida') ||
        normalized.contains('transito') ||
        normalized.contains('trânsito') ||
        normalized.contains('preservado')) {
      return const _IncidentBadgeStyle(
        icon: Icons.volunteer_activism_rounded,
        iconColor: Color(0xFF2DD4BF),
        textColor: Color(0xFF99F6E4),
        backgroundColor: Color(0x142DD4BF),
        borderColor: Color(0x332DD4BF),
      );
    }

    if (normalized.contains('sem constat')) {
      return const _IncidentBadgeStyle(
        icon: Icons.search_off_rounded,
        iconColor: Color(0xFF94A3B8),
        textColor: Color(0xFFCBD5E1),
        backgroundColor: Color(0x1494A3B8),
        borderColor: Color(0x3394A3B8),
      );
    }

    return const _IncidentBadgeStyle(
      icon: Icons.fact_check_rounded,
      iconColor: Color(0xFFA78BFA),
      textColor: Color(0xFFC4B5FD),
      backgroundColor: Color(0x14A78BFA),
      borderColor: Color(0x33A78BFA),
    );
  }
}
