part of 'daily_timeline_screen.dart';

extension _DailyTimelineItemPresentation on _DailyTimelineScreenState {
  _TimelineTilePresentation _resolveTimelineTilePresentation(
    _TimelineEntry entry,
  ) {
    final incident = entry.originalModel is Incident
        ? entry.originalModel as Incident
        : null;
    final isActiveIncident = incident?.isInProgress ?? false;
    final (icon, color) = _resolveTimelineTileIcon(entry, isActiveIncident);

    return _TimelineTilePresentation(
      icon: icon,
      color: color,
      title: _cleanTimelineTitle(entry),
      subtitle: _buildTimelineSubtitle(entry, _formatTimelineEntryTime(entry)),
      mainMetric: _resolveTimelineMainMetric(entry, isActiveIncident),
    );
  }

  (IconData, Color) _resolveTimelineTileIcon(
    _TimelineEntry entry,
    bool isActiveIncident,
  ) {
    switch (entry.type) {
      case 'Treino':
        return (Icons.track_changes_rounded, const Color(0xFFFFB300));
      case 'Rotina':
        return (Icons.pets_rounded, const Color(0xFF43A047));
      case 'Ocorrência':
        final icon = isActiveIncident
            ? Icons.pending_actions_rounded
            : Icons.shield_outlined;
        final color = isActiveIncident ? _hudAmber : const Color(0xFFE53935);
        return (icon, color);
      case 'Saude':
        return (Icons.vaccines_rounded, const Color(0xFF8E24AA));
      default:
        return (Icons.info_outline, Colors.blueGrey);
    }
  }

  String _resolveTimelineMainMetric(
    _TimelineEntry entry,
    bool isActiveIncident,
  ) {
    if (entry.type == 'Treino' && entry.details['Duração'] != null) {
      return entry.details['Duração'].toString();
    }

    if (isActiveIncident) {
      return 'EM ANDAMENTO';
    }

    if (entry.type == 'Ocorrência' && entry.details['Resultado'] != null) {
      return entry.details['Resultado'].toString().toUpperCase();
    }

    return '';
  }

  String _formatTimelineEntryTime(_TimelineEntry entry) {
    final hour = entry.time.hour.toString().padLeft(2, '0');
    final minute = entry.time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
